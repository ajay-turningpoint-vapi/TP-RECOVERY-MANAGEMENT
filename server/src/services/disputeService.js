const { withTransaction } = require('../config/db');
const disputeRepository = require('../repositories/disputeRepository');
const taskRepository = require('../repositories/taskRepository');
const auditRepository = require('../repositories/auditRepository');
const customerRepository = require('../repositories/customerRepository');
const disputeMessageRepository = require('../repositories/disputeMessageRepository');
const taskService = require('./taskService');
const { enqueueNotification } = require('../queues/notificationQueue');
const { notifyDecision, salesmanForCustomer } = require('./decisionNotify');
const { driveRecoveryTask, rupees } = require('./recoveryTaskService');
const { NotFoundError, ValidationError } = require('../errors/AppError');

async function withMessages(disputes) {
  const byDispute = await disputeMessageRepository.listAllGrouped();
  return disputes.map((d) => ({ ...d, messages: byDispute[d.id] || [] }));
}

async function listForUser(user) {
  const all = await disputeRepository.findAll();
  if (user.role === 'SALESPERSON') {
    const customers = await customerRepository.findBySalesman(user.id);
    const ids = new Set(customers.map((c) => c.id));
    return withMessages(all.filter((d) => ids.has(d.customerId)));
  }
  return withMessages(all);
}

async function getOrThrow(id) {
  const dispute = await disputeRepository.findById(id);
  if (!dispute) throw new NotFoundError('Dispute');
  return dispute;
}

async function approve(disputeId, user, { resolutionOwner, deadline, description, note, attachmentPath }) {
  const dispute = await getOrThrow(disputeId);
  const evidencePath = attachmentPath || dispute.attachmentPath;

  await withTransaction(async (conn) => {
    await disputeRepository.update(disputeId, { status: 'Approved', statusDetail: 'Approved – Resolution In Progress', resolutionOwner }, conn);

    // The resolution-owner task — worked from the task itself (chat +
    // resolve), never via Record Outcome. dispute_id links it back.
    await taskRepository.insert(
      { type: 'customerCall', customerId: dispute.customerId, ownerId: resolutionOwner, deadline, priority: 'High', reason: `DISPUTE RESOLUTION: ${description}`, source: 'Dispute Review', note, attachmentPath: evidencePath, disputeId },
      conn
    );
    // Seed the resolution thread with the RE's assignment note (mandatory).
    await disputeMessageRepository.add(
      { disputeId, authorId: user.id, authorName: user.fullName, authorRole: user.role, kind: 'note', body: note, attachmentPath },
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

  // The disputed slice stays with the RE (resolution owner) — the
  // salesperson chases the rest of the overdue now. One `source='Recovery'`
  // task, due 9 PM, which also re-enables Record Outcome in the app.
  const cust = await customerRepository.findById(dispute.customerId);
  const remaining = Math.max(0, (Number(cust && cust.totalDue) || 0) - dispute.amount);
  await driveRecoveryTask(dispute.customerId, {
    headline: `Dispute of ${rupees(dispute.amount)} approved — the RE is resolving it.`,
    priority: 'Normal',
    deadlineHour: 21,
    collectAmount: remaining,
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
        attachmentPath: dispute.attachmentPath,
      },
      conn
    );

  });

  await notifyDecision(await salesmanForCustomer(dispute.customerId), {
    approved: false,
    title: 'Dispute rejected',
    body: `${user.fullName} rejected the ₹${dispute.amount.toFixed(0)} dispute. Reason: "${reason}". The full amount stays in active recovery.`,
    customerId: dispute.customerId,
  });

  // The disputed slice is confirmed still owed — drive the one
  // `source='Recovery'` task to the full outstanding, due 9 PM, High. This
  // also re-enables Record Outcome for the customer in the app.
  await driveRecoveryTask(dispute.customerId, {
    headline: `Dispute of ${rupees(dispute.amount)} rejected — the full amount stands. Reason: "${reason}".`,
    priority: 'High',
    deadlineHour: 21,
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
  // Resolved → totalDue dropped and the dispute stops covering; Returned
  // → the slice comes back. Either way, re-point the single recovery task.
  await driveRecoveryTask(dispute.customerId, {
    headline:
      outcome === 'Resolved'
        ? `Dispute of ${rupees(dispute.amount)} settled — work the remaining balance.`
        : `Dispute of ${rupees(dispute.amount)} returned to recovery — the full amount is back in play.`,
    priority: outcome === 'Resolved' ? 'Normal' : 'High',
    deadlineHour: 21,
  });
  return disputeRepository.findById(disputeId);
}

async function requestInfo(disputeId, user, { salesmanId, desc, deadline }) {
  const dispute = await getOrThrow(disputeId);

  await withTransaction(async (conn) => {
    await disputeRepository.update(disputeId, { status: 'Need More Information', statusDetail: 'Awaiting Additional Information', infoRequestNote: desc }, conn);
    // Thread the RE's question, and link the salesperson's task back to
    // this dispute so they answer from the task (not a Record Outcome).
    await disputeMessageRepository.add(
      { disputeId, authorId: user.id, authorName: user.fullName, authorRole: user.role, kind: 'question', body: desc },
      conn
    );
    await taskRepository.insert(
      { type: 'customerCall', customerId: dispute.customerId, ownerId: salesmanId, deadline: deadline || taskService.defaultCallDeadline(), priority: 'High', reason: `DISPUTE CLARIFICATION NEEDED: ${desc}`, source: 'Dispute Review', disputeId, attachmentPath: dispute.attachmentPath },
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

/**
 * Salesperson answers an RE clarification request from their linked task.
 * Appends the answer to the thread, closes the task, and flips the dispute
 * back to 'Pending Approval' so it re-enters the RE review queue (badge
 * reappears). The RE can then Approve / Reject / ask again — repeatable.
 */
async function answerClarification(disputeId, user, { taskId, body }) {
  const dispute = await getOrThrow(disputeId);
  if (dispute.status !== 'Need More Information') {
    throw new ValidationError(`This dispute is "${dispute.status}" — it is not awaiting clarification`);
  }

  const task = taskId ? await taskRepository.findById(taskId) : null;
  if (!task || task.disputeId !== disputeId) {
    throw new ValidationError('This task is not a clarification request for this dispute');
  }
  if (task.ownerId !== user.id) {
    throw new ValidationError('You can only answer your own clarification task');
  }

  await withTransaction(async (conn) => {
    await disputeMessageRepository.add(
      { disputeId, authorId: user.id, authorName: user.fullName, authorRole: user.role, kind: 'answer', body },
      conn
    );
    await taskRepository.update(
      taskId,
      { status: 'completed', outcome: 'Clarification provided', completedAt: new Date() },
      conn
    );
    await disputeRepository.update(
      disputeId,
      { status: 'Pending Approval', statusDetail: 'Clarification provided — awaiting RE re-review' },
      conn
    );
    await auditRepository.record(
      dispute.customerId,
      {
        type: 'SALESMAN_PROVIDED_CLARIFICATION',
        description: `${user.fullName} answered the RE's clarification request on the ₹${dispute.amount.toFixed(0)} dispute: "${body}". The dispute is back with the RE for a decision.`,
        actor: user.fullName,
        previousState: 'Need More Information',
        newState: 'Pending Approval',
        source: 'Dispute Review',
      },
      conn
    );
  });

  return disputeRepository.findById(disputeId);
}

/**
 * Free back-and-forth message on a dispute (RE ⇄ resolution-owner salesman)
 * while a dispute is being worked. Optionally carries an attachment. Does
 * not change dispute status.
 */
async function postMessage(disputeId, user, { body, attachmentPath }) {
  const dispute = await getOrThrow(disputeId);
  await disputeMessageRepository.add({
    disputeId,
    authorId: user.id,
    authorName: user.fullName,
    authorRole: user.role,
    kind: 'note',
    body,
    attachmentPath: attachmentPath || null,
  });
  return disputeRepository.findById(disputeId);
}

/**
 * The resolution-owner salesman marks the dispute resolved from their
 * resolution task. Same money effect as the RE's `resolve('Resolved')`
 * (disputed amount confirmed received → exposure reduced), closes the
 * resolution task, and hands a follow-up task to the salesman who
 * originally raised the dispute.
 */
async function resolveByOwner(disputeId, user, { taskId, note }) {
  const dispute = await getOrThrow(disputeId);
  if (dispute.status !== 'Approved') {
    throw new ValidationError(`This dispute is "${dispute.status}" — only an in-progress (Approved) dispute can be resolved`);
  }
  if (dispute.resolutionOwner !== user.id) {
    throw new ValidationError('Only the assigned resolution owner can resolve this dispute');
  }
  const task = taskId ? await taskRepository.findById(taskId) : null;
  if (!task || task.disputeId !== disputeId || task.ownerId !== user.id) {
    throw new ValidationError('This task is not your resolution task for this dispute');
  }

  const customer = await customerRepository.findById(dispute.customerId);
  const raiserId = customer ? customer.assignedSalesmanId : null;

  await withTransaction(async (conn) => {
    await disputeRepository.update(disputeId, { status: 'Resolved', statusDetail: 'Resolved by resolution owner' }, conn);

    const newTotalDue = Math.max(0, (customer?.totalDue || 0) - dispute.amount);
    const newTotalOutstanding = Math.max(0, (customer?.totalOutstanding || 0) - dispute.amount);
    await customerRepository.update(dispute.customerId, { totalDue: newTotalDue, totalOutstanding: newTotalOutstanding }, conn);

    await taskRepository.update(taskId, { status: 'completed', outcome: 'Dispute resolved', completedAt: new Date() }, conn);

    if (note) {
      await disputeMessageRepository.add(
        { disputeId, authorId: user.id, authorName: user.fullName, authorRole: user.role, kind: 'note', body: note },
        conn
      );
    }

    await auditRepository.record(
      dispute.customerId,
      {
        type: 'DISPUTE_RESOLVED_BY_OWNER',
        description: `${user.fullName} (resolution owner) resolved the ₹${dispute.amount.toFixed(0)} dispute. Financial exposure reduced by the same amount.${note ? ` Note: "${note}".` : ''}`,
        actor: user.fullName,
        previousState: `₹${(customer?.totalDue || 0).toFixed(0)} due`,
        newState: `₹${newTotalDue.toFixed(0)} due`,
        source: 'Dispute Review',
      },
      conn
    );

    // Follow-up for the salesman who originally raised the dispute.
    if (raiserId) {
      await taskRepository.insert(
        {
          type: 'customerCall',
          customerId: dispute.customerId,
          ownerId: raiserId,
          deadline: taskService.defaultCallDeadline(),
          priority: 'Normal',
          reason: `DISPUTE RESOLVED — confirm with customer & close: ${dispute.reason}`,
          source: 'Dispute Review',
          note: `The ₹${dispute.amount.toFixed(0)} dispute you raised has been resolved by ${user.fullName}. Confirm with the customer and continue recovery on the remaining balance.`,
        },
        conn
      );
      await customerRepository.update(dispute.customerId, { currentRecoveryState: 'Action Required', primaryNextAction: 'CALL CUSTOMER' }, conn);
    }
  });

  // The raiser already has a specific "confirm & close" call task from the
  // block above; driveRecoveryTask sees it and won't stack a second — it
  // just keeps the single-task invariant and re-points the figure if that
  // task is ever cleared without an outcome.
  await driveRecoveryTask(dispute.customerId, {
    headline: `Dispute of ${rupees(dispute.amount)} resolved — work the remaining balance.`,
    priority: 'Normal',
    deadlineHour: 21,
  });
  return disputeRepository.findById(disputeId);
}

module.exports = { listForUser, approve, reject, requestInfo, resolve, answerClarification, postMessage, resolveByOwner };
