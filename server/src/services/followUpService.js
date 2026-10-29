const customerRepository = require('../repositories/customerRepository');
const auditRepository = require('../repositories/auditRepository');
const { driveRecoveryTask, outcomeWait } = require('./recoveryTaskService');
const { emitChange } = require('../realtime/eventBus');
const logger = require('../config/logger');

// Customer states that mean "salesperson recorded a Will Confirm /
// Follow-up and is waiting for the confirm time" — mirrors the outcome
// names customerService.recordOutcome accepts for this branch.
const FOLLOW_UP_ACTIONS = new Set(['Follow-up Scheduled', 'Follow-up']);

/**
 * The exact-time counterpart to a matured PTP/verified claim: called by
 * followUpWorker once the promised "Will Confirm" callback time genuinely
 * passes. Creates the salesman's call task and re-opens Record Outcome —
 * nothing does either before this runs (see customerService.recordOutcome's
 * reconcileState skip for 'Follow-up'/'Follow-up Scheduled').
 *
 * Pure/pluggable like ptpVerificationService's functions — callable
 * directly from tests without a live BullMQ worker.
 */
async function resolveFollowUp({ customerId, dueAt, note }) {
  const customer = await customerRepository.findById(customerId);
  // The customer may have moved on since this was scheduled (RE took
  // control, a different outcome got recorded in the meantime, ...) — only
  // act if this is still genuinely the open Will-Confirm wait.
  if (!customer || !FOLLOW_UP_ACTIONS.has(customer.primaryNextAction)) {
    logger.info('[followUpService] skipped — customer moved on since scheduling', { customerId });
    return { skipped: true };
  }

  await driveRecoveryTask(customerId, {
    headline: `Call ${customer.name || 'the customer'} — the confirm time has passed with nothing recorded.${note ? ` Note: "${note}".` : ''}`,
    priority: 'Normal',
    deadlineHour: 18,
    // This job IS rule 3's trigger — the one caller allowed past the Will
    // Confirm wait in driveRecoveryTask.
    resolves: 'Will Confirm',
  });

  // Nothing overdue (e.g. the whole balance is future-due) → no task is
  // created, and the customer must not stay parked on "Follow-up
  // Scheduled": that kept Record Outcome locked forever with nothing
  // pending (NAKODA LAMINATES / VANDANA ATUL SHAH, 24 Oct). Release it;
  // once an invoice falls due, the daily sweep creates the task as usual.
  const after = await customerRepository.findById(customerId);
  const taskCreated = !FOLLOW_UP_ACTIONS.has(after.primaryNextAction);
  // ...unless another rule still holds the account (an open PTP / claim /
  // Internal Action) — that rule's own trigger decides, not this one.
  const released = !taskCreated && !(await outcomeWait(customerId, { customer: after }));
  if (released) {
    await customerRepository.update(customerId, {
      primaryNextAction: 'Nothing Pending',
      reasonForAction: 'Will Confirm time passed — nothing overdue to collect right now.',
    });
  }
  const when = new Date(dueAt).toLocaleString('en-IN', { timeZone: 'Asia/Kolkata' });
  await auditRepository.record(customerId, {
    type: 'FOLLOWUP_TIME_PASSED',
    description: taskCreated
      ? `The "Will Confirm" time (${when}) passed with nothing recorded — a fresh call task was created.${note ? ` Note: "${note}".` : ''}`
      : !released
      ? `The "Will Confirm" time (${when}) passed — no call task yet: another open step (PTP / claim / Internal Action) still holds this account.${note ? ` Note: "${note}".` : ''}`
      : `The "Will Confirm" time (${when}) passed — nothing is overdue right now, so no call task was needed; Record Outcome is open again.${note ? ` Note: "${note}".` : ''}`,
    actor: 'System',
    source: 'Recovery',
  });

  emitChange(['tasks', 'customers'], { customerId, reason: 'followup.due' });
  logger.info('[followUpService] Will-Confirm time reached', { customerId, taskCreated, released });
  return { rolled: true };
}

module.exports = { resolveFollowUp, FOLLOW_UP_ACTIONS };
