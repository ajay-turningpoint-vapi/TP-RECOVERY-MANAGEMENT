const { withTransaction } = require('../config/db');
const outcomeEditRepository = require('../repositories/outcomeEditRepository');
const customerRepository = require('../repositories/customerRepository');
const ptpRepository = require('../repositories/ptpRepository');
const disputeRepository = require('../repositories/disputeRepository');
const paymentClaimRepository = require('../repositories/paymentClaimRepository');
const taskRepository = require('../repositories/taskRepository');
const auditRepository = require('../repositories/auditRepository');
const userRepository = require('../repositories/userRepository');
const customerService = require('./customerService');
const { notifyDecision } = require('./decisionNotify');
const { NotFoundError, ForbiddenError, ValidationError } = require('../errors/AppError');

const KINDS = ['PTP', 'PaymentClaim', 'Dispute', 'FollowUp', 'Simple', 'NoAnswerReplacement'];

function disputePriority(amount) {
  return amount >= 100000 ? 'High' : amount >= 30000 ? 'Medium' : 'Low';
}

function num(v) {
  const n = Number(v);
  return Number.isFinite(n) ? n : 0;
}

/**
 * Loads the live artifact this request targets and returns
 * { originalPayload, apply(conn, customer, requestedPayload, actorName) }.
 * originalPayload is built here on the server — never trusted from the client.
 */
async function resolveTarget(kind, artifactId, customer, salesmanId) {
  switch (kind) {
    case 'PTP': {
      const ptp = await ptpRepository.findById(artifactId);
      if (!ptp || ptp.customerId !== customer.id) throw new NotFoundError('PTP for this outcome');
      if (!['scheduled', 'pendingVerification'].includes(ptp.status)) {
        throw new ValidationError('This PTP is no longer editable (already matured).');
      }
      return {
        originalPayload: {
          amount: ptp.amountPromised,
          promiseDate: ptp.promiseDate,
          paymentMode: ptp.paymentMode,
        },
        // Approving replaces the old promise with the new one — status
        // resets to 'scheduled' regardless of where it was in its
        // verification cycle (even mid-grace-period), so the edited PTP
        // runs the full scheduled -> pendingVerification -> verified
        // lifecycle again against its new date/amount, rather than staying
        // stuck against the old cycle. A rejected request never reaches
        // here at all, so the original schedule is left completely
        // untouched by rejection.
        apply: async (conn, _customer, p) => {
          await ptpRepository.update(
            artifactId,
            { amountPromised: num(p.amount), promiseDate: new Date(p.promiseDate), paymentMode: p.paymentMode, status: 'scheduled' },
            conn
          );
        },
      };
    }
    case 'Dispute': {
      const dispute = await disputeRepository.findById(artifactId);
      if (!dispute || dispute.customerId !== customer.id) throw new NotFoundError('Dispute for this outcome');
      return {
        originalPayload: { amount: dispute.amount, reason: dispute.reason },
        apply: async (conn, _customer, p) => {
          await disputeRepository.update(
            artifactId,
            { amount: num(p.amount), reason: p.reason, priority: disputePriority(num(p.amount)) },
            conn
          );
          await customerRepository.update(customer.id, { reasonForAction: `Dispute: ${p.reason}` }, conn);
        },
      };
    }
    case 'PaymentClaim': {
      const claim = await paymentClaimRepository.findById(artifactId);
      if (!claim || claim.customerId !== customer.id) throw new NotFoundError('Payment claim for this outcome');
      return {
        originalPayload: { amount: claim.amount, claimDate: claim.claimDate, reference: claim.reference },
        apply: async (conn, _customer, p) => {
          await paymentClaimRepository.update(
            artifactId,
            { amount: num(p.amount), claimDate: new Date(p.claimDate), reference: p.reference || null },
            conn
          );
        },
      };
    }
    case 'FollowUp': {
      const task = await taskRepository.findById(artifactId);
      if (!task || task.customerId !== customer.id) throw new NotFoundError('Follow-up task for this outcome');
      return {
        originalPayload: { deadline: task.deadline },
        apply: async (conn, _customer, p) => {
          // Re-run the side effect: the follow-up now falls on the edited date.
          await taskRepository.update(artifactId, { deadline: new Date(p.deadline) }, conn);
        },
      };
    }
    case 'Simple': {
      return {
        originalPayload: { reason: customer.reasonForAction },
        apply: async (conn, _customer, p) => {
          await customerRepository.update(customer.id, { reasonForAction: p.reason }, conn);
        },
      };
    }
    case 'NoAnswerReplacement': {
      // The same-day self-service replace on the client (see
      // customerService.recordOutcome's `replacingNoAnswer`) only exists
      // for the day the No Answer was recorded — once that window has
      // passed, correcting it goes through this RE-approved request
      // instead, same as every other outcome kind above. Re-validated here
      // (not just trusted from when the request was raised) in case the
      // customer moved on to some other outcome in the meantime.
      if (!(customer.primaryNextAction === 'Call Customer' && customer.reasonForAction === 'No Answer')) {
        throw new ValidationError('This customer no longer has a No Answer recorded to replace.');
      }
      return {
        originalPayload: { reason: 'No Answer', attempts: customer.noAnswerAttempts },
        // Applies the exact same logic the same-day self-service path
        // uses (customerService.applyOutcome with replacingNoAnswer:
        // true) — erases the old "No Answer Logged" audit row, corrects
        // the attempt counter, and records whatever the salesman actually
        // asked for (which may itself create a PTP/dispute/task, same as
        // a normal Record Outcome). Attributed to the original salesman
        // (whose task/PTP/etc this becomes), not the RE clicking approve.
        apply: async (conn, liveCustomer, p) => {
          const salesmanRow = await userRepository.findById(salesmanId);
          if (!salesmanRow) throw new NotFoundError('Salesperson who requested this edit');
          await customerService.applyOutcome(
            conn,
            liveCustomer,
            { id: salesmanRow.id, fullName: salesmanRow.full_name },
            {
              nextAction: p.nextAction,
              reason: p.reason,
              details: p.details,
              followUpAt: p.followUpAt ? new Date(p.followUpAt) : undefined,
              ptpAmountValue: p.ptpAmountValue,
              ptpDate: p.ptpDate ? new Date(p.ptpDate) : undefined,
              ptpMode: p.ptpMode,
              attachmentPath: p.attachmentPath,
              replacingNoAnswer: true,
            }
          );
        },
      };
    }
    default:
      throw new ValidationError(`Unknown outcome kind "${kind}"`);
  }
}

function summarize(kind, payload) {
  if (!payload) return kind;
  switch (kind) {
    case 'PTP':
      return `PTP ₹${payload.amount} on ${new Date(payload.promiseDate).toISOString().slice(0, 10)} via ${payload.paymentMode}`;
    case 'Dispute':
      return `Dispute ₹${payload.amount} — ${payload.reason}`;
    case 'PaymentClaim':
      return `Claim ₹${payload.amount} ref ${payload.reference || '—'}`;
    case 'FollowUp':
      return `Follow-up on ${new Date(payload.deadline).toISOString().slice(0, 16).replace('T', ' ')}`;
    case 'Simple':
      return payload.reason;
    case 'NoAnswerReplacement':
      return payload.nextAction ? `${payload.nextAction} — ${payload.reason}` : `No Answer (${payload.attempts ?? 0} attempt(s) logged)`;
    default:
      return kind;
  }
}

async function listForUser(user) {
  if (user.role === 'SALESPERSON') return outcomeEditRepository.findBySalesman(user.id);
  return outcomeEditRepository.findAll();
}

async function getOrThrow(id) {
  const req = await outcomeEditRepository.findById(id);
  if (!req) throw new NotFoundError('Outcome edit request');
  return req;
}

/**
 * A salesperson cannot silently rewrite a recorded outcome's values — the
 * change is staged here and only takes effect on RE approval (same guarantee
 * as PTP corrections). original_payload is read from the live artifact on the
 * server, so the request can never misrepresent what was actually recorded.
 */
async function request(customerId, user, { outcomeKind, artifactId, requestedPayload, editReason }) {
  if (!KINDS.includes(outcomeKind)) throw new ValidationError(`Unknown outcome kind "${outcomeKind}"`);
  const customer = await customerRepository.findById(customerId);
  if (!customer) throw new NotFoundError('Customer');
  if (user.role === 'SALESPERSON' && customer.assignedSalesmanId !== user.id) {
    throw new ForbiddenError('This customer is not in your portfolio');
  }

  const target = await resolveTarget(outcomeKind, artifactId ?? null, customer, user.id);

  const existing = await outcomeEditRepository.findPendingForArtifact(customerId, artifactId ?? null);
  if (existing.length > 0) {
    throw new ValidationError('An edit request for this outcome is already awaiting RE review.');
  }

  let id;
  await withTransaction(async (conn) => {
    id = await outcomeEditRepository.insert(
      {
        customerId,
        salesmanId: user.id,
        outcomeKind,
        artifactId: artifactId ?? null,
        originalPayload: target.originalPayload,
        requestedPayload,
        editReason,
      },
      conn
    );
    await auditRepository.record(
      customerId,
      {
        type: 'SALESPERSON_REQUESTED_OUTCOME_EDIT',
        description: `${user.fullName} requested an edit to a recorded ${outcomeKind} outcome: "${summarize(
          outcomeKind,
          target.originalPayload
        )}" → "${summarize(outcomeKind, requestedPayload)}". Reason: "${editReason}".`,
        actor: user.fullName,
        previousState: summarize(outcomeKind, target.originalPayload),
        newState: summarize(outcomeKind, requestedPayload),
        source: 'Outcome Edit Request',
      },
      conn
    );
  });
  return outcomeEditRepository.findById(id);
}

async function approve(id, user) {
  const req = await getOrThrow(id);
  if (req.status !== 'Pending') {
    throw new ValidationError(`This request is already "${req.status}" — it can only be decided once`);
  }
  const customer = await customerRepository.findById(req.customerId);
  if (!customer) throw new NotFoundError('Customer');

  const target = await resolveTarget(req.outcomeKind, req.artifactId, customer, req.salesmanId);

  await withTransaction(async (conn) => {
    await target.apply(conn, customer, req.requestedPayload, user.fullName);
    await outcomeEditRepository.update(id, { status: 'Approved', resolvedAt: new Date() }, conn);
    await auditRepository.record(
      req.customerId,
      {
        type: 'RE_APPROVED_OUTCOME_EDIT',
        description: `${user.fullName} approved an outcome edit (${req.outcomeKind}): "${summarize(
          req.outcomeKind,
          req.originalPayload
        )}" → "${summarize(req.outcomeKind, req.requestedPayload)}". Salesperson's reason: "${req.editReason}".`,
        actor: user.fullName,
        previousState: summarize(req.outcomeKind, req.originalPayload),
        newState: summarize(req.outcomeKind, req.requestedPayload),
        source: 'Outcome Edit Review',
      },
      conn
    );
  });

  // Covers replacing a stale No Answer with "Unable / Refused" — same
  // system-raised L2 escalation customerService.recordOutcome's direct
  // path triggers, attributed to the salesperson whose outcome this
  // actually is, not the RE clicking approve. Best-effort, post-commit —
  // see customerService.maybeEscalateCustomerRefused's own doc comment.
  if (req.outcomeKind === 'NoAnswerReplacement') {
    const salesmanRow = await userRepository.findById(req.salesmanId);
    if (salesmanRow) {
      await customerService.maybeEscalateCustomerRefused(req.customerId, { id: salesmanRow.id, fullName: salesmanRow.full_name }, req.requestedPayload);
    }
  }

  await notifyDecision(req.salesmanId, {
    approved: true,
    title: req.outcomeKind === 'PTP' ? 'PTP edit approved — new schedule is live' : 'Outcome edit approved',
    body:
      req.outcomeKind === 'PTP'
        ? `${user.fullName} approved your PTP edit for this customer. The promise is now rescheduled to "${summarize('PTP', req.requestedPayload)}" — it will go through verification again against the new date.`
        : `${user.fullName} approved your edit to the recorded ${req.outcomeKind} outcome. The new values are now live.`,
    customerId: req.customerId,
  });
  return outcomeEditRepository.findById(id);
}

async function reject(id, user, reason) {
  const req = await getOrThrow(id);
  if (req.status !== 'Pending') {
    throw new ValidationError(`This request is already "${req.status}" — it can only be decided once`);
  }
  await outcomeEditRepository.update(id, { status: 'Rejected', rejectionReason: reason, resolvedAt: new Date() });
  await auditRepository.record(req.customerId, {
    type: 'RE_REJECTED_OUTCOME_EDIT',
    description: `${user.fullName} rejected an outcome edit request (${req.outcomeKind}). Reason: "${reason}". The recorded values stand unchanged.`,
    actor: user.fullName,
    source: 'Outcome Edit Review',
  });
  await notifyDecision(req.salesmanId, {
    approved: false,
    title: req.outcomeKind === 'PTP' ? 'PTP edit rejected — original schedule continues' : 'Outcome edit rejected',
    body:
      req.outcomeKind === 'PTP'
        ? `${user.fullName} rejected your PTP edit. Reason: "${reason}". The original promise — "${summarize('PTP', req.originalPayload)}" — stands unchanged and continues on its existing schedule.`
        : `${user.fullName} rejected your edit to the recorded ${req.outcomeKind} outcome. Reason: "${reason}". The values stand unchanged.`,
    customerId: req.customerId,
  });
  return outcomeEditRepository.findById(id);
}

module.exports = { listForUser, request, approve, reject };
