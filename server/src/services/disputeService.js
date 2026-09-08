const { withTransaction } = require('../config/db');
const disputeRepository = require('../repositories/disputeRepository');
const taskRepository = require('../repositories/taskRepository');
const auditRepository = require('../repositories/auditRepository');
const customerRepository = require('../repositories/customerRepository');
const taskService = require('./taskService');
const { enqueueNotification } = require('../queues/notificationQueue');
const { notifyDecision, salesmanForCustomer } = require('./decisionNotify');
const { NotFoundError, ValidationError } = require('../errors/AppError');

async function listForUser(user) {
  if (user.role === 'SALESPERSON') {
    const customers = await customerRepository.findBySalesman(user.id);
    const ids = new Set(customers.map((c) => c.id));
    const all = await disputeRepository.findAll();
    return all.filter((d) => ids.has(d.customerId));
  }
  return disputeRepository.findAll();
}

async function getOrThrow(id) {
  const dispute = await disputeRepository.findById(id);
  if (!dispute) throw new NotFoundError('Dispute');
  return dispute;
}

async function approve(disputeId, user, { resolutionOwner, deadline, description }) {
  const dispute = await getOrThrow(disputeId);

  await withTransaction(async (conn) => {
    await disputeRepository.update(disputeId, { status: 'Approved', statusDetail: 'Approved – Resolution In Progress', resolutionOwner }, conn);

    // Approve only creates the resolution-owner task — no separate
    // call-customer follow-up here (that's reject-only; an approved
    // dispute is being worked by the resolution owner, not something the
    // salesperson needs to immediately call about).
    await taskRepository.insert(
      { type: 'customerCall', customerId: dispute.customerId, ownerId: resolutionOwner, deadline, priority: 'High', reason: `DISPUTE RESOLUTION: ${description}`, source: 'Dispute Review' },
      conn
    );
    await auditRepository.record(
      dispute.customerId,
      {
        type: 'RE_APPROVED_DISPUTE',
        description: `${user.fullName} approved the disputed amount of ₹${dispute.amount.toFixed(0)} — this amount is now shielded from active recovery while the undisputed balance continues normally. Resolution was assigned to ${resolutionOwner} with instructions "${description}".`,
        actor: user.fullName,
        previousState: 'Pending Approval',
        newState: 'Approved',
        source: 'Dispute Review',
      },
      conn
    );
  });
  await enqueueNotification({
    userId: resolutionOwner,
    severity: 'warning',
    title: `Dispute resolution assigned — ₹${dispute.amount.toFixed(0)}`,
    body: description,
    customerId: dispute.customerId,
  });
  await notifyDecision(await salesmanForCustomer(dispute.customerId), {
    approved: true,
    title: 'Dispute approved',
    body: `${user.fullName} approved the ₹${dispute.amount.toFixed(0)} dispute you raised. It is now with the resolution owner.`,
    customerId: dispute.customerId,
  });

  return disputeRepository.findById(disputeId);
}

async function reject(disputeId, user, reason) {
  const dispute = await getOrThrow(disputeId);

  await withTransaction(async (conn) => {
    await disputeRepository.update(disputeId, { status: 'Rejected', statusDetail: 'Rejected', rejectionReason: reason }, conn);
    await auditRepository.record(
      dispute.customerId,
      {
        type: 'RE_REJECTED_DISPUTE',
        description: `${user.fullName} rejected the ₹${dispute.amount.toFixed(0)} dispute claim as invalid. Rejection reason: "${reason}". The full amount remains in active recovery.`,
        actor: user.fullName,
        previousState: 'Pending Approval',
        newState: 'Rejected',
        source: 'Dispute Review',
      },
      conn
    );

    // The disputed amount is confirmed still owed — the salesperson must
    // call and re-collect it. High priority: this is a real balance still
    // due, not just an FYI. requireDueBalance: false since it must fire
    // on every rejection, not gated on the customer's wider totalDue.
    const created = await taskService.ensureFollowUpIfNeeded(
      dispute.customerId,
      null,
      {
        reason: 'Dispute rejected',
        auditType: 'DISPUTE_REJECTED_FOLLOWUP',
        source: 'Dispute Review',
        priority: 'High',
        note: `${user.fullName} rejected the ₹${dispute.amount.toFixed(0)} dispute as invalid. Reason: "${reason}". The full amount stays in active recovery.`,
        attachmentPath: dispute.attachmentPath,
        requireDueBalance: false,
      },
      conn
    );
    if (created) {
      await customerRepository.update(dispute.customerId, { currentRecoveryState: 'Action Required', primaryNextAction: 'CALL CUSTOMER' }, conn);
    }
  });

  await notifyDecision(await salesmanForCustomer(dispute.customerId), {
    approved: false,
    title: 'Dispute rejected',
    body: `${user.fullName} rejected the ₹${dispute.amount.toFixed(0)} dispute. Reason: "${reason}". The full amount stays in active recovery.`,
    customerId: dispute.customerId,
  });
  return disputeRepository.findById(disputeId);
}

/**
 * Second-stage verification on an already-Approved dispute — real
 * confirmation of whether the resolution genuinely came through, not just
 * a status label. There's no live payment-gateway integration to detect
 * this automatically, so — like every other reconciliation in this system
 * (PTP maturity, payment claims) — it's a real, evidence-backed RE/Manager
 * action after checking with accounts/BUSY.
 *
 * 'Resolved' IS the confirmed receipt — it genuinely reduces the
 * customer's financial exposure by the disputed amount (Product Law 3).
 * 'Returned to Recovery' means the amount was never actually received, so
 * no money moves — the full amount simply stays in active recovery (it was
 * never removed from totalDue when the dispute was raised in the first
 * place, so there's nothing to reverse).
 */
async function resolve(disputeId, user, { outcome, note }) {
  const dispute = await getOrThrow(disputeId);
  if (dispute.status !== 'Approved') {
    throw new ValidationError(`This dispute is "${dispute.status}" — only an Approved dispute can be verified/resolved`);
  }

  await withTransaction(async (conn) => {
    await disputeRepository.update(disputeId, { status: outcome, statusDetail: outcome }, conn);

    if (outcome === 'Resolved') {
      const customer = await customerRepository.findById(dispute.customerId);
      const newTotalDue = Math.max(0, customer.totalDue - dispute.amount);
      const newTotalOutstanding = Math.max(0, customer.totalOutstanding - dispute.amount);
      await customerRepository.update(dispute.customerId, { totalDue: newTotalDue, totalOutstanding: newTotalOutstanding }, conn);
      await auditRepository.record(
        dispute.customerId,
        {
          type: 'RE_RESOLVED_DISPUTE',
          description: `${user.fullName} verified the dispute resolution against BUSY and confirmed the disputed amount (₹${dispute.amount.toFixed(0)}) was genuinely received — financial exposure reduced by the same amount.${note ? ` Note: "${note}".` : ''}`,
          actor: user.fullName,
          previousState: `₹${customer.totalDue.toFixed(0)} due`,
          newState: `₹${newTotalDue.toFixed(0)} due`,
          source: 'Dispute Resolution Verification',
        },
        conn
      );
    } else {
      await auditRepository.record(
        dispute.customerId,
        {
          type: 'RE_RETURNED_DISPUTE_TO_RECOVERY',
          description: `${user.fullName} verified against BUSY that the disputed amount (₹${dispute.amount.toFixed(0)}) was still unpaid despite the resolution being marked complete — it stays in active recovery, nothing is silently written off.${note ? ` Note: "${note}".` : ''}`,
          actor: user.fullName,
          source: 'Dispute Resolution Verification',
        },
        conn
      );
    }
  });

  await notifyDecision(await salesmanForCustomer(dispute.customerId), {
    approved: outcome === 'Resolved',
    title: outcome === 'Resolved' ? 'Dispute resolved' : 'Dispute returned to recovery',
    body:
      outcome === 'Resolved'
        ? `${user.fullName} confirmed the ₹${dispute.amount.toFixed(0)} dispute was settled — exposure reduced.`
        : `${user.fullName} found the ₹${dispute.amount.toFixed(0)} disputed amount still unpaid — it stays in active recovery.`,
    customerId: dispute.customerId,
  });
  return disputeRepository.findById(disputeId);
}

async function requestInfo(disputeId, user, { salesmanId, desc, deadline }) {
  const dispute = await getOrThrow(disputeId);

  await withTransaction(async (conn) => {
    await disputeRepository.update(disputeId, { status: 'Need More Information', statusDetail: 'Awaiting Additional Information', infoRequestNote: desc }, conn);
    await taskRepository.insert(
      { type: 'customerCall', customerId: dispute.customerId, ownerId: salesmanId, deadline, priority: 'High', reason: `DISPUTE INFO REQUIRED: ${desc}`, source: 'Dispute Review' },
      conn
    );
    await auditRepository.record(
      dispute.customerId,
      {
        type: 'RE_REQUESTED_INFORMATION',
        description: `${user.fullName} could not approve the ₹${dispute.amount.toFixed(0)} dispute as submitted and requested more information from ${salesmanId}: "${desc}". The dispute stays open pending this clarification.`,
        actor: user.fullName,
        previousState: 'Pending Approval',
        newState: 'Need More Information',
        source: 'Dispute Review',
      },
      conn
    );
  });
  await enqueueNotification({
    userId: salesmanId,
    severity: 'warning',
    title: `More information needed — ₹${dispute.amount.toFixed(0)} dispute`,
    body: desc,
    customerId: dispute.customerId,
  });
  return disputeRepository.findById(disputeId);
}

module.exports = { listForUser, approve, reject, requestInfo, resolve };
