import {
  createCorrectionRequest,
  getCorrectionRequest,
  updateCorrectionRequest,
  updatePtp,
  getPtp,
  updateCustomer,
  appendAuditEvent,
} from '../store/repository.js';

// One generic processor for both PTP-amount/date corrections and recorded-
// outcome corrections — the source Dart app implements these as two
// parallel bespoke methods; the workflow audit recommended standardizing
// the repeated "user cannot silently rewrite a recorded fact, must go
// through RE approval" idiom into a single request/approve/reject shape.

async function request(data) {
  const { correctionType, customerId, actor } = data;
  if (correctionType !== 'ptp' && correctionType !== 'outcome') {
    throw new Error(`correction-request request job requires correctionType "ptp" or "outcome", got "${correctionType}"`);
  }
  if (!customerId) throw new Error('correction-request request job requires customerId');

  if (correctionType === 'ptp') {
    const { ptpId, requestedAmount, requestedDate, reason } = data;
    if (!ptpId || !requestedAmount || !requestedDate) throw new Error('ptp correction request requires ptpId, requestedAmount, requestedDate');
    getPtp(ptpId); // fail fast if unknown
    await updatePtp(ptpId, () => ({ correctionStatus: 'Pending' }));
    const record = createCorrectionRequest({ correctionType, customerId, ptpId, requestedAmount, requestedDate, reason, actor });
    appendAuditEvent({
      customerId,
      type: 'SALESPERSON_REQUESTED_PTP_CORRECTION',
      description: `Correction requested for PTP ${ptpId}: amount/date change to ₹${requestedAmount} on ${requestedDate}. ${reason || ''}`.trim(),
      actor: actor || 'Salesperson',
      source: 'Correction Request',
      relatedEntityType: 'PTP',
      relatedEntityId: ptpId,
    });
    return { correctionRequestId: record.id };
  }

  const { originalOutcome, originalReason, requestedOutcome, requestedReason, note } = data;
  if (!requestedOutcome) throw new Error('outcome correction request requires requestedOutcome');
  const record = createCorrectionRequest({ correctionType, customerId, originalOutcome, originalReason, requestedOutcome, requestedReason, note, actor });
  appendAuditEvent({
    customerId,
    type: 'SALESPERSON_REQUESTED_OUTCOME_CORRECTION',
    description: `Correction requested: change recorded outcome from "${originalOutcome}" to "${requestedOutcome}". ${note || ''}`.trim(),
    actor: actor || 'Salesperson',
    source: 'Correction Request',
  });
  return { correctionRequestId: record.id };
}

async function approve(data) {
  const { correctionRequestId, actor } = data;
  if (!correctionRequestId) throw new Error('correction-request approve job requires correctionRequestId');
  const existing = getCorrectionRequest(correctionRequestId);
  if (existing.status !== 'Pending') return { correctionRequestId, status: existing.status, skipped: true };

  const updated = await updateCorrectionRequest(correctionRequestId, () => ({ status: 'Approved' }));

  if (updated.correctionType === 'ptp') {
    const before = getPtp(updated.ptpId);
    await updatePtp(updated.ptpId, () => ({
      amountPromised: updated.requestedAmount,
      promiseDate: new Date(updated.requestedDate).toISOString(),
      correctionStatus: 'Approved',
    }));
    appendAuditEvent({
      customerId: updated.customerId,
      type: 'RE_APPROVED_PTP_CORRECTION',
      description: `PTP ${updated.ptpId} corrected from ₹${before.amountPromised}/${before.promiseDate} to ₹${updated.requestedAmount}/${updated.requestedDate}.`,
      actor: actor || 'Recovery Executive',
      previousState: `₹${before.amountPromised} on ${before.promiseDate}`,
      newState: `₹${updated.requestedAmount} on ${updated.requestedDate}`,
      source: 'Approval Inbox',
      relatedEntityType: 'PTP',
      relatedEntityId: updated.ptpId,
    });
  } else {
    await updateCustomer(updated.customerId, () => ({
      primaryNextAction: updated.requestedOutcome,
      reasonForAction: updated.requestedReason,
    }));
    appendAuditEvent({
      customerId: updated.customerId,
      type: 'RE_APPROVED_OUTCOME_CORRECTION',
      description: `Outcome correction approved: "${updated.originalOutcome}" -> "${updated.requestedOutcome}".`,
      actor: actor || 'Recovery Executive',
      previousState: updated.originalOutcome,
      newState: updated.requestedOutcome,
      source: 'Approval Inbox',
    });
  }

  return { correctionRequestId, status: 'Approved' };
}

async function reject(data) {
  const { correctionRequestId, reason, actor } = data;
  if (!correctionRequestId) throw new Error('correction-request reject job requires correctionRequestId');
  const existing = getCorrectionRequest(correctionRequestId);
  if (existing.status !== 'Pending') return { correctionRequestId, status: existing.status, skipped: true };

  const updated = await updateCorrectionRequest(correctionRequestId, () => ({ status: 'Rejected' }));
  if (updated.correctionType === 'ptp') {
    await updatePtp(updated.ptpId, () => ({ correctionStatus: 'Rejected' }));
  }
  appendAuditEvent({
    customerId: updated.customerId,
    type: updated.correctionType === 'ptp' ? 'RE_REJECTED_PTP_CORRECTION' : 'RE_REJECTED_OUTCOME_CORRECTION',
    description: `Correction request ${correctionRequestId} rejected: ${reason || 'no reason given'}.`,
    actor: actor || 'Recovery Executive',
    source: 'Approval Inbox',
    relatedEntityType: updated.correctionType === 'ptp' ? 'PTP' : undefined,
    relatedEntityId: updated.correctionType === 'ptp' ? updated.ptpId : undefined,
  });
  return { correctionRequestId, status: 'Rejected' };
}

const handlers = { request, approve, reject };

export async function processCorrectionRequest(job) {
  const handler = handlers[job.name];
  if (!handler) throw new Error(`Unknown correction-request job name: "${job.name}"`);
  return handler(job.data);
}
