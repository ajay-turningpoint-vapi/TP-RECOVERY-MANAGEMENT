const { connection } = require('../config/redis');
const logger = require('../config/logger');

// One Redis pub/sub channel carries every real-time event. Publishing is a
// normal Redis command, safe on the shared `connection` (BullMQ multiplexes
// the same one). Callable from BOTH the API process and the worker process
// — the API's SSE hub (realtime/sseHub.js) is the only subscriber and fans
// events out to connected clients.
const CHANNEL = 'rms:events';

// Every list the Flutter client keeps in memory. A mutating request can
// touch several of these transitively (record-outcome alone can create a
// task AND a PTP AND a dispute), so the generic post-write hook invalidates
// the whole set — the client debounces and each refresh is one cheap GET.
const RESOURCE_ALL = [
  'customers',
  'tasks',
  'ptps',
  'disputes',
  'paymentClaims',
  'escalations',
  'outcomeEdits',
  'outcomeCorrections',
  'salesmen',
];

/**
 * @param {object} event  one of:
 *   { type:'invalidate', resources:string[], customerId?, scope }
 *   { type:'sync', phase:'started'|'finished', since? }
 *   { type:'notification', scope }
 * scope = { broadcast:true } | { userId } | { userIds:[] } | { branch }
 */
function publish(event) {
  const payload = JSON.stringify({ ...event, ts: Date.now() });
  // Fire-and-forget — a failed publish must never break the request/job
  // that triggered it. Clients recover on their next event or reconnect.
  connection.publish(CHANNEL, payload).catch((err) => {
    logger.warn('[eventBus] publish failed', { message: err.message });
  });
}

/**
 * Convenience wrapper for the common case: "these lists changed". When the
 * affected salesperson is known, the event is scoped to them (+ every RE /
 * Manager, who see everything); otherwise it broadcasts.
 *
 * @param {string[]} resources  e.g. ['ptps','tasks','customers']
 * @param {{ customerId?, salesmanId?, salesmanIds?, reason?, branch? }} [meta]
 */
function emitChange(resources, meta = {}) {
  const { customerId = null, salesmanId, salesmanIds, reason, branch } = meta;
  let scope;
  if (branch) scope = { branch };
  else if (salesmanIds && salesmanIds.length) scope = { userIds: salesmanIds.filter(Boolean) };
  else if (salesmanId) scope = { userId: salesmanId };
  else scope = { broadcast: true };
  publish({ type: 'invalidate', resources, customerId, reason: reason || null, scope });
}

module.exports = { CHANNEL, RESOURCE_ALL, publish, emitChange };
