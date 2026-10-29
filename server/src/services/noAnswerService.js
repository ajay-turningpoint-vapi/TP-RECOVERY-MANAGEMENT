const customerRepository = require('../repositories/customerRepository');
const taskRepository = require('../repositories/taskRepository');
const auditRepository = require('../repositories/auditRepository');
const { emitChange } = require('../realtime/eventBus');
const logger = require('../config/logger');

/**
 * The exact-time counterpart to a matured PTP/verified claim/Will-Confirm:
 * called by noAnswerWorker once the 2-hour No-Answer callback window (or
 * the post-escalation 2nd-cycle callback) genuinely passes. Creates the
 * single 'No Answer'-sourced call task — nothing does so before this runs
 * (see customerService.applyOutcome's No Answer branch, which schedules
 * this instead of inserting the task inline).
 *
 * Pure/pluggable like followUpService.resolveFollowUp — callable directly
 * from tests without a live BullMQ worker.
 */
async function resolveNoAnswerDue({ customerId, ownerId, attemptNumber, dueAt }) {
  const customer = await customerRepository.findById(customerId);
  // The customer may have moved on since this was scheduled — a different
  // outcome got recorded, or a NEWER No-Answer already superseded this
  // exact attempt (noAnswerAttempts has moved past what this job was
  // scheduled for — recorded here, not just "still No Answer", since
  // repeated No-Answer calls keep writing the same primaryNextAction/
  // reasonForAction pair). Only act if this is still genuinely the
  // current wait.
  if (!customer || customer.reasonForAction !== 'No Answer' || customer.noAnswerAttempts !== attemptNumber) {
    logger.info('[noAnswerService] skipped — customer moved on since scheduling', { customerId, attemptNumber });
    return { skipped: true };
  }

  const deadline = new Date(dueAt);
  const reason = `Call ${customer.name || 'the customer'} — no answer on the last attempt. Try again, or record what happened.`;
  await taskRepository.insert({
    type: 'customerCall',
    customerId,
    ownerId: ownerId || customer.assignedSalesmanId,
    deadline,
    priority: 'Normal',
    reason,
    source: 'No Answer',
  });

  await auditRepository.record(customerId, {
    type: 'NO_ANSWER_CALLBACK_DUE',
    description: 'The 2-hour No-Answer callback window passed with nothing recorded — a fresh call task was created.',
    actor: 'System',
    source: 'No Answer',
  });

  emitChange(['tasks', 'customers'], { customerId, reason: 'no-answer.due' });
  logger.info('[noAnswerService] callback window reached — call task created', { customerId, attemptNumber });
  return { created: true };
}

module.exports = { resolveNoAnswerDue };
