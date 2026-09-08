import { getDispute, updateDispute, createTask, appendAuditEvent, getBusySyncHealth, updateCustomer } from '../store/repository.js';
import { getQueue, QUEUE_NAMES } from '../queues/index.js';

const DEFAULT_PAYMENT_CONFIRMATION_DELAY_MS = 3 * 24 * 3600 * 1000;

async function approve(data) {
  const { disputeId, resolutionOwner, deadline, description, actor } = data;
  if (!disputeId || !resolutionOwner || !deadline) throw new Error('dispute approve job requires disputeId, resolutionOwner, deadline');
  const dispute = await updateDispute(disputeId, () => ({ status: 'Approved' }));
  const task = createTask({
    type: 'disputeResolution',
    customerId: dispute.customerId,
    ownerId: resolutionOwner,
    deadline: new Date(deadline).toISOString(),
    priority: 'High',
    reason: `DISPUTE RESOLUTION: ${description || dispute.reason}`,
    source: 'Dispute Review',
  });
  appendAuditEvent({
    customerId: dispute.customerId,
    type: 'RE_APPROVED_DISPUTE',
    description: `Dispute ${disputeId} approved — ₹${dispute.amount} is now shielded from active recovery while the undisputed balance continues normally.`,
    actor: actor || 'Recovery Executive',
    source: 'Dispute Review',
    relatedEntityType: 'Dispute',
    relatedEntityId: disputeId,
  });
  return { status: 'Approved', taskId: task.id };
}

async function reject(data) {
  const { disputeId, reason, actor } = data;
  if (!disputeId) throw new Error('dispute reject job requires disputeId');
  const dispute = await updateDispute(disputeId, () => ({ status: 'Rejected' }));
  appendAuditEvent({
    customerId: dispute.customerId,
    type: 'RE_REJECTED_DISPUTE',
    description: `Dispute ${disputeId} rejected: ${reason || 'no reason given'}. The full amount remains in active recovery.`,
    actor: actor || 'Recovery Executive',
    source: 'Dispute Review',
    relatedEntityType: 'Dispute',
    relatedEntityId: disputeId,
  });
  return { status: 'Rejected' };
}

async function requestInfo(data) {
  const { disputeId, salesmanId, description, deadline, actor } = data;
  if (!disputeId || !salesmanId || !deadline) throw new Error('dispute request-info job requires disputeId, salesmanId, deadline');
  const dispute = await updateDispute(disputeId, () => ({ status: 'Need More Information' }));
  const task = createTask({
    type: 'disputeResolution',
    customerId: dispute.customerId,
    ownerId: salesmanId,
    deadline: new Date(deadline).toISOString(),
    priority: 'Normal',
    reason: `DISPUTE INFO REQUIRED: ${description || ''}`,
    source: 'Dispute Review',
  });
  appendAuditEvent({
    customerId: dispute.customerId,
    type: 'RE_REQUESTED_INFORMATION',
    description: `Dispute ${disputeId} stays open pending clarification from ${salesmanId}.`,
    actor: actor || 'Recovery Executive',
    source: 'Dispute Review',
    relatedEntityType: 'Dispute',
    relatedEntityId: disputeId,
  });
  return { status: 'Need More Information', taskId: task.id };
}

// ---- Back half of the lifecycle: spec'd, but not implemented in the
// source Dart app (flagged explicitly by the workflow audit). ----

async function moveToResolution(data) {
  const { disputeId, actor } = data;
  if (!disputeId) throw new Error('dispute move-to-resolution job requires disputeId');
  const dispute = await updateDispute(disputeId, (d) => {
    if (d.status !== 'Approved') throw new Error(`Dispute ${disputeId} must be Approved before moving to In Resolution (current: ${d.status})`);
    return { status: 'In Resolution' };
  });
  appendAuditEvent({
    customerId: dispute.customerId,
    type: 'DISPUTE_IN_RESOLUTION',
    description: `Dispute ${disputeId} resolution work is underway.`,
    actor: actor || 'Recovery Executive',
    source: 'Dispute Resolution',
    relatedEntityType: 'Dispute',
    relatedEntityId: disputeId,
  });
  return { status: 'In Resolution' };
}

async function markAwaitingVerification(data) {
  const { disputeId, actor } = data;
  if (!disputeId) throw new Error('dispute mark-awaiting-verification job requires disputeId');
  const dispute = await updateDispute(disputeId, (d) => {
    if (d.status !== 'In Resolution') throw new Error(`Dispute ${disputeId} must be In Resolution before Awaiting Verification (current: ${d.status})`);
    return { status: 'Awaiting Verification' };
  });
  appendAuditEvent({
    customerId: dispute.customerId,
    type: 'DISPUTE_AWAITING_VERIFICATION',
    description: `Dispute ${disputeId} resolution submitted for BUSY financial verification.`,
    actor: actor || 'Recovery Executive',
    source: 'Dispute Resolution',
    relatedEntityType: 'Dispute',
    relatedEntityId: disputeId,
  });
  return { status: 'Awaiting Verification' };
}

/**
 * Resolves a dispute — gated on BUSY sync health (a dispute must never be
 * silently marked Resolved while financial data is stale, mirroring the
 * same invariant enforced for payment claims). Schedules a delayed
 * "did the customer actually pay?" follow-up rather than trusting
 * "Resolved" to mean "paid" — Non-Negotiable Law: resolved-but-unpaid
 * disputes return to active recovery, which the source Dart app declares
 * in spec but never implements.
 */
async function resolve(data) {
  const { disputeId, actor, paidConfirmed, verifyAfterMs } = data;
  if (!disputeId) throw new Error('dispute resolve job requires disputeId');

  if (!getBusySyncHealth()) {
    const dispute = getDispute(disputeId);
    appendAuditEvent({
      customerId: dispute.customerId,
      type: 'DISPUTE_RESOLUTION_SYNC_PENDING',
      description: `BUSY financial data is currently stale — dispute ${disputeId} resolution is held rather than falsely marked Resolved.`,
      actor: actor || 'Recovery Executive',
      source: 'Dispute Resolution',
      relatedEntityType: 'Dispute',
      relatedEntityId: disputeId,
    });
    return { status: dispute.status, held: true };
  }

  const dispute = await updateDispute(disputeId, (d) => {
    if (d.status !== 'Awaiting Verification') throw new Error(`Dispute ${disputeId} must be Awaiting Verification before Resolved (current: ${d.status})`);
    return { status: 'Resolved' };
  });
  appendAuditEvent({
    customerId: dispute.customerId,
    type: 'DISPUTE_RESOLVED',
    description: `Dispute ${disputeId} resolved and verified against BUSY.`,
    actor: actor || 'Recovery Executive',
    source: 'Dispute Resolution',
    relatedEntityType: 'Dispute',
    relatedEntityId: disputeId,
  });

  const disputeQueue = getQueue(QUEUE_NAMES.DISPUTE);
  await disputeQueue.add(
    'return-to-recovery-check',
    { disputeId, actor, paidConfirmed },
    { delay: verifyAfterMs ?? DEFAULT_PAYMENT_CONFIRMATION_DELAY_MS, attempts: 3, backoff: { type: 'exponential', delay: 1000 } },
  );

  return { status: 'Resolved' };
}

async function returnToRecoveryCheck(data) {
  const { disputeId, actor, paidConfirmed } = data;
  const dispute = getDispute(disputeId);
  if (paidConfirmed) {
    appendAuditEvent({
      customerId: dispute.customerId,
      type: 'DISPUTE_PAYMENT_CONFIRMED',
      description: `Dispute ${disputeId} payment confirmed — no further recovery action needed for this amount.`,
      actor: actor || 'System',
      source: 'Dispute Resolution',
      relatedEntityType: 'Dispute',
      relatedEntityId: disputeId,
    });
    return { returnedToRecovery: false };
  }

  await updateCustomer(dispute.customerId, () => ({
    currentRecoveryState: 'Waiting / Monitoring',
    primaryNextAction: 'CALL CUSTOMER',
    reasonForAction: `Resolved dispute ${disputeId} remains unpaid`,
  }));
  createTask({
    type: 'customerCall',
    customerId: dispute.customerId,
    ownerId: actor || 'Recovery Executive',
    deadline: new Date(Date.now() + 24 * 3600 * 1000).toISOString(),
    priority: 'High',
    reason: `Resolved dispute ${disputeId} still unpaid — resume active recovery`,
    source: 'Dispute Resolution',
  });
  appendAuditEvent({
    customerId: dispute.customerId,
    type: 'DISPUTE_RESOLVED_UNPAID_RETURNED_TO_RECOVERY',
    description: `Dispute ${disputeId} was resolved but the amount remains unpaid — customer returned to active recovery. Resolved status is never treated as equivalent to Paid.`,
    actor: actor || 'System',
    source: 'Dispute Resolution',
    relatedEntityType: 'Dispute',
    relatedEntityId: disputeId,
  });
  return { returnedToRecovery: true };
}

const handlers = {
  approve,
  reject,
  'request-info': requestInfo,
  'move-to-resolution': moveToResolution,
  'mark-awaiting-verification': markAwaitingVerification,
  resolve,
  'return-to-recovery-check': returnToRecoveryCheck,
};

export async function processDispute(job) {
  const handler = handlers[job.name];
  if (!handler) throw new Error(`Unknown dispute job name: "${job.name}"`);
  return handler(job.data);
}
