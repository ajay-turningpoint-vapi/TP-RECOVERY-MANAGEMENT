const { enqueueNotification } = require('../queues/notificationQueue');
const customerRepository = require('../repositories/customerRepository');
const { emitChange, RESOURCE_ALL } = require('../realtime/eventBus');

/**
 * Fire-and-forget in-app notification to one salesperson about an RE
 * approval / rejection on something they submitted or own. The Flutter
 * 90-second poll turns the new unread `notifications` row into a local OS
 * banner while the app is foregrounded. Never throws into the caller —
 * a decision must still succeed even if the notify enqueue fails.
 *
 * @param {string|null|undefined} userId  recipient salesperson id
 * @param {{title:string, body:string, customerId?:string|null, approved?:boolean}} opts
 */
async function notifyDecision(userId, { title, body, customerId = null, approved }) {
  if (!userId) return;
  // The generic post-write hook (middleware/emitOnWrite.js) already tells
  // every RE/Manager client. This adds the affected SALESPERSON to the
  // fan-out for an RE decision on their artifact (new task, status change,
  // reduced balance) — the emitOnWrite hook can't, since its req.user is
  // the RE, not this salesman.
  emitChange(RESOURCE_ALL, { customerId, salesmanId: userId, reason: 'decision' });
  try {
    await enqueueNotification({
      userId,
      // Approvals are informational; rejections / "needs rework" are a warning.
      severity: approved === false ? 'warning' : 'info',
      title,
      body,
      customerId,
    });
  } catch (err) {
    // eslint-disable-next-line no-console
    console.error('[decisionNotify] failed to enqueue notification', err);
  }
}

/** The salesperson who owns a customer — for artifacts with no salesman column. */
async function salesmanForCustomer(customerId) {
  const c = await customerRepository.findById(customerId);
  return c ? c.assignedSalesmanId : null;
}

module.exports = { notifyDecision, salesmanForCustomer };
