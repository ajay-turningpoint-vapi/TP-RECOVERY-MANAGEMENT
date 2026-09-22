const { connection } = require('../config/redis');
const logger = require('../config/logger');
const { CHANNEL } = require('./eventBus');

// Holds every open SSE response in THIS process and fans Redis pub/sub
// events out to the ones that should receive them. `init()` is called once
// on API boot; the worker process never touches this.
const clients = new Set(); // { res, userId, role, branch }

const RE_ROLES = new Set(['RECOVERY_EXECUTIVE', 'MANAGEMENT']);

function add(res, user) {
  const entry = { res, userId: user.id, role: user.role, branch: user.branch || null };
  clients.add(entry);
  return entry;
}

function remove(entry) {
  clients.delete(entry);
}

function write(res, type, data) {
  try {
    res.write(`event: ${type}\ndata: ${JSON.stringify(data)}\n\n`);
  } catch (_) {
    // Broken pipe — the 'close' handler on the request will clean it up.
  }
}

function matches(entry, event) {
  const scope = event.scope || {};
  switch (event.type) {
    case 'sync':
      return true; // the freeze overlay is for everyone
    case 'maintenance':
      return true; // the manager-only kill switch blocks everyone (see maintenanceService.js)
    case 'notification':
      if (scope.broadcast) return true;
      if (scope.userId) return entry.userId === scope.userId;
      if (scope.userIds) return scope.userIds.includes(entry.userId);
      return false;
    case 'invalidate':
      // RE / Manager see the whole company (branch-filtered client-side),
      // so every data change is relevant to them. Salespeople only get a
      // change explicitly scoped to them.
      if (RE_ROLES.has(entry.role)) return true;
      if (scope.broadcast) return true;
      if (scope.userId) return entry.userId === scope.userId;
      if (scope.userIds) return scope.userIds.includes(entry.userId);
      return false;
    default:
      return false;
  }
}

function dispatch(event) {
  for (const entry of clients) {
    if (matches(entry, event)) write(entry.res, event.type, event);
  }
}

let subscriber = null;

function init() {
  if (subscriber) return;
  // A subscriber connection can't run normal commands, so it must be its
  // own connection — duplicate() clones the config from the shared one.
  subscriber = connection.duplicate();
  subscriber.on('error', (err) => logger.warn('[sseHub] subscriber error', { message: err.message }));
  subscriber.subscribe(CHANNEL, (err) => {
    if (err) logger.error('[sseHub] failed to subscribe', { message: err.message });
    else logger.info(`[sseHub] subscribed to ${CHANNEL}`);
  });
  subscriber.on('message', (_channel, raw) => {
    try {
      dispatch(JSON.parse(raw));
    } catch (err) {
      logger.warn('[sseHub] bad event payload', { message: err.message });
    }
  });
}

/** End every open stream so server.close() can drain on shutdown. */
function closeAll() {
  for (const entry of clients) {
    try {
      entry.res.end();
    } catch (_) {
      /* already gone */
    }
  }
  clients.clear();
  if (subscriber) {
    subscriber.quit().catch(() => {});
    subscriber = null;
  }
}

function clientCount() {
  return clients.size;
}

module.exports = { init, add, remove, write, dispatch, closeAll, clientCount };
