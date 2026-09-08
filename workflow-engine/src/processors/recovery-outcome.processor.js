import { config } from '../config.js';
import {
  updateCustomer,
  appendAuditEvent,
  createPtp,
  createTask,
  createPaymentClaim,
  createDispute,
  listOpenTasksForCustomer,
  updateTask,
  nextNoAnswerAttempt,
  recordNoAnswerAttempt,
  resetNoAnswerAttempts,
  getCustomer,
} from '../store/repository.js';

// Mirrors AppStore.recordOutcome's action->label mapping (app_store.dart),
// used purely for a friendly audit description.
const OUTCOME_LABELS = {
  'PTP Scheduled': 'Promise To Pay Recorded',
  'Follow-up': 'Follow-Up Scheduled',
  'Follow-up Scheduled': 'Follow-Up Scheduled',
  'Customer Refused': 'Unable To Commit',
  'Internal Action': 'Internal Action Required',
  'Action Required': 'Internal Action Required',
  'Verification Pending': 'Payment Verification Requested',
};

function outcomeLabel(nextAction, reason) {
  if (nextAction === 'Call Customer' && reason === 'No Answer') return 'No Answer Logged';
  if (reason === 'Dispute Raised') return 'Dispute Raised';
  return OUTCOME_LABELS[nextAction] || nextAction;
}

function assertShape(data, required) {
  for (const key of required) {
    if (data[key] === undefined || data[key] === null) {
      throw new Error(`recovery-outcome job missing required field "${key}"`);
    }
  }
}

async function closeOpenTasksForCustomer(customerId) {
  const open = listOpenTasksForCustomer(customerId);
  for (const t of open) {
    await updateTask(t.id, () => ({ status: 'completed', completedAt: new Date().toISOString() }));
  }
  return open.length;
}

async function applyCommonOutcome({ customerId, actor, nextAction, reason, details }) {
  getCustomer(customerId); // throws NotFoundError if missing — fail fast, don't silently no-op
  const label = outcomeLabel(nextAction, reason);
  appendAuditEvent({
    customerId,
    type: label,
    description: `${reason || nextAction} — ${details || ''}`.trim(),
    actor: actor || 'System',
    source: 'Record Outcome',
    relatedEntityType: 'Customer',
    relatedEntityId: customerId,
  });
  await updateCustomer(customerId, () => ({
    primaryNextAction: nextAction,
    reasonForAction: reason,
    currentRecoveryState: 'Waiting / Monitoring',
  }));
  const closedCount = await closeOpenTasksForCustomer(customerId);
  return { label, closedCount };
}

const handlers = {
  async 'ptp-scheduled'(data) {
    assertShape(data, ['customerId', 'amountPromised', 'promiseDate', 'paymentMode']);
    const { customerId, actor, amountPromised, promiseDate, paymentMode } = data;
    const ptp = createPtp({ customerId, amountPromised, promiseDate, paymentMode });
    await applyCommonOutcome({
      customerId,
      actor,
      nextAction: 'PTP Scheduled',
      reason: `PTP of ₹${amountPromised} scheduled for ${new Date(promiseDate).toDateString()}`,
      details: `Payment mode: ${paymentMode}`,
    });
    return { ptpId: ptp.id };
  },

  async 'follow-up'(data) {
    assertShape(data, ['customerId']);
    const { customerId, actor, reason, followUpAt } = data;
    const deadline = followUpAt ? new Date(followUpAt) : new Date(Date.now() + 24 * 3600 * 1000);
    const task = createTask({
      type: 'customerCall',
      customerId,
      ownerId: actor,
      deadline: deadline.toISOString(),
      priority: 'Normal',
      reason: reason || 'Follow-up scheduled',
      source: 'Record Outcome',
    });
    await applyCommonOutcome({ customerId, actor, nextAction: 'Follow-up', reason: reason || 'Will Confirm', details: `Next follow-up: ${deadline.toISOString()}` });
    return { taskId: task.id };
  },

  async 'no-answer'(data) {
    assertShape(data, ['customerId']);
    const { customerId, actor } = data;
    const attempts = nextNoAnswerAttempt(customerId);
    let physicalVisitTaskId = null;
    if (attempts >= config.noAnswer.threshold) {
      resetNoAnswerAttempts(customerId);
      const task = createTask({
        type: 'physicalVisit',
        customerId,
        ownerId: actor,
        deadline: new Date(Date.now() + config.noAnswer.visitDeadlineHours * 3600 * 1000).toISOString(),
        priority: 'High',
        reason: 'Non-response threshold reached',
        source: 'Record Outcome',
      });
      physicalVisitTaskId = task.id;
    } else {
      recordNoAnswerAttempt(customerId, attempts);
    }
    await applyCommonOutcome({ customerId, actor, nextAction: 'Call Customer', reason: 'No Answer', details: `Attempt ${attempts} of ${config.noAnswer.threshold}` });
    return { attempts, physicalVisitTaskId };
  },

  async 'unable-to-commit'(data) {
    assertShape(data, ['customerId']);
    const { customerId, actor, reason, followUpAt } = data;
    const deadline = followUpAt ? new Date(followUpAt) : new Date(Date.now() + 3 * 24 * 3600 * 1000);
    const task = createTask({
      type: 'customerCall',
      customerId,
      ownerId: actor,
      deadline: deadline.toISOString(),
      priority: 'Normal',
      reason: reason || 'Customer unable to commit — retry scheduled',
      source: 'Record Outcome',
    });
    await applyCommonOutcome({ customerId, actor, nextAction: 'Unable To Commit', reason: 'Customer Refused', details: `Retry scheduled: ${deadline.toISOString()}` });
    return { taskId: task.id };
  },

  async 'internal-action'(data) {
    assertShape(data, ['customerId', 'details']);
    const { customerId, actor, details } = data;
    const task = createTask({
      type: 'financialTeamFollowUp',
      customerId,
      ownerId: 'Recovery Executive',
      deadline: new Date(Date.now() + 4 * 3600 * 1000).toISOString(),
      priority: 'High',
      reason: details,
      source: 'Record Outcome',
    });
    await applyCommonOutcome({ customerId, actor, nextAction: 'Internal Action', reason: 'Internal Action Required', details });
    return { taskId: task.id };
  },

  async 'verification-pending'(data) {
    assertShape(data, ['customerId', 'amount']);
    const { customerId, actor, amount, reference } = data;
    const customer = getCustomer(customerId);
    const claim = createPaymentClaim({
      customerId,
      customer: customer.name,
      amount,
      date: new Date().toISOString().slice(0, 10),
      reference: reference || `Claimed by ${actor} — no reference given`,
      status: 'Awaiting Verification',
    });
    await applyCommonOutcome({ customerId, actor, nextAction: 'Verification Pending', reason: 'Payment Already Made', details: `Claimed amount: ₹${amount}` });
    return { paymentClaimId: claim.id };
  },

  async 'dispute-raised'(data) {
    assertShape(data, ['customerId', 'amount', 'reason']);
    const { customerId, actor, amount, reason } = data;
    const customer = getCustomer(customerId);
    const priority = amount >= 100000 ? 'High' : amount >= 30000 ? 'Medium' : 'Low';
    const dispute = createDispute({
      customerId,
      customer: customer.name,
      amount,
      reason,
      priority,
      invoice: customer.invoices?.[0]?.number || 'N/A',
      raisedDate: new Date().toISOString(),
      raisedBy: actor,
    });
    await applyCommonOutcome({ customerId, actor, nextAction: 'Dispute Raised', reason: 'Dispute Raised', details: `Amt: ₹${amount}, Reason: ${reason}` });
    return { disputeId: dispute.id };
  },
};

export async function processRecoveryOutcome(job) {
  const handler = handlers[job.name];
  if (!handler) {
    throw new Error(`Unknown recovery-outcome job name: "${job.name}"`);
  }
  return handler(job.data);
}
