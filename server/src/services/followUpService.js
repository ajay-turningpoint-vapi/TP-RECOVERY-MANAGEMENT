const customerRepository = require('../repositories/customerRepository');
const auditRepository = require('../repositories/auditRepository');
const { driveRecoveryTask } = require('./recoveryTaskService');
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
async function resolveFollowUp({ customerId, dueAt }) {
  const customer = await customerRepository.findById(customerId);
  // The customer may have moved on since this was scheduled (RE took
  // control, a different outcome got recorded in the meantime, ...) — only
  // act if this is still genuinely the open Will-Confirm wait.
  if (!customer || !FOLLOW_UP_ACTIONS.has(customer.primaryNextAction)) {
    logger.info('[followUpService] skipped — customer moved on since scheduling', { customerId });
    return { skipped: true };
  }

  await auditRepository.record(customerId, {
    type: 'FOLLOWUP_TIME_PASSED',
    description: `The "Will Confirm" time (${new Date(dueAt).toLocaleString('en-IN')}) passed with nothing recorded — a fresh call task was created.`,
    actor: 'System',
    source: 'Recovery',
  });

  await driveRecoveryTask(customerId, {
    headline: `Call ${customer.name || 'the customer'} — the confirm time has passed with nothing recorded.`,
    priority: 'Normal',
    deadlineHour: 18,
  });

  emitChange(['tasks', 'customers'], { customerId, reason: 'followup.due' });
  logger.info('[followUpService] Will-Confirm time reached — call task created', { customerId });
  return { rolled: true };
}

module.exports = { resolveFollowUp, FOLLOW_UP_ACTIONS };
