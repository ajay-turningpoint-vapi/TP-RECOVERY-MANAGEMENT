const { withTransaction } = require('../config/db');
const outcomeCorrectionRepository = require('../repositories/outcomeCorrectionRepository');
const customerRepository = require('../repositories/customerRepository');
const auditRepository = require('../repositories/auditRepository');
const { notifyDecision } = require('./decisionNotify');
const { NotFoundError, ForbiddenError, ValidationError } = require('../errors/AppError');

async function listForUser(user) {
  if (user.role === 'SALESPERSON') {
    return outcomeCorrectionRepository.findBySalesman(user.id);
  }
  return outcomeCorrectionRepository.findAll();
}

async function getOrThrow(id) {
  const req = await outcomeCorrectionRepository.findById(id);
  if (!req) throw new NotFoundError('Outcome correction request');
  return req;
}

/**
 * A salesperson cannot silently rewrite an already-recorded outcome — real
 * RE approval is required, the same pattern already used for PTP
 * corrections. The "original" outcome/reason are read from the customer's
 * own current record here on the server (not trusted from the client),
 * so the request can never misrepresent what was actually recorded.
 */
async function request(customerId, user, { requestedOutcome, requestedReason, requestNote }) {
  const customer = await customerRepository.findById(customerId);
  if (!customer) throw new NotFoundError('Customer');
  if (user.role === 'SALESPERSON' && customer.assignedSalesmanId !== user.id) {
    throw new ForbiddenError('This customer is not in your portfolio');
  }

  let id;
  await withTransaction(async (conn) => {
    id = await outcomeCorrectionRepository.insert(
      {
        customerId,
        salesmanId: user.id,
        originalOutcome: customer.primaryNextAction,
        originalReason: customer.reasonForAction,
        requestedOutcome,
        requestedReason,
        requestNote,
      },
      conn
    );
    await auditRepository.record(
      customerId,
      {
        type: 'SALESPERSON_REQUESTED_OUTCOME_CORRECTION',
        description: `${user.fullName} requested a correction to the recorded outcome: from "${customer.primaryNextAction}" (${customer.reasonForAction}) to "${requestedOutcome}" (${requestedReason}). Reason: "${requestNote}".`,
        actor: user.fullName,
        previousState: customer.primaryNextAction,
        newState: requestedOutcome,
        source: 'Outcome Correction Request',
      },
      conn
    );
  });
  return outcomeCorrectionRepository.findById(id);
}

async function approve(id, user) {
  const req = await getOrThrow(id);
  if (req.status !== 'Pending') throw new ValidationError(`This request is already "${req.status}" — it can only be decided once`);

  await withTransaction(async (conn) => {
    await outcomeCorrectionRepository.update(id, { status: 'Approved', resolvedAt: new Date() }, conn);
    await customerRepository.update(req.customerId, { primaryNextAction: req.requestedOutcome, reasonForAction: req.requestedReason }, conn);
    await auditRepository.record(
      req.customerId,
      {
        type: 'RE_APPROVED_OUTCOME_CORRECTION',
        description: `${user.fullName} approved ${req.salesmanId}'s correction request: recorded outcome changed from "${req.originalOutcome}" (${req.originalReason}) to "${req.requestedOutcome}" (${req.requestedReason}). Salesperson's stated reason: "${req.requestNote}".`,
        actor: user.fullName,
        previousState: req.originalOutcome,
        newState: req.requestedOutcome,
        source: 'Outcome Correction Review',
      },
      conn
    );
  });
  await notifyDecision(req.salesmanId, {
    approved: true,
    title: 'Outcome correction approved',
    body: `${user.fullName} approved your correction — the recorded outcome is now "${req.requestedOutcome}".`,
    customerId: req.customerId,
  });
  return outcomeCorrectionRepository.findById(id);
}

async function reject(id, user, reason) {
  const req = await getOrThrow(id);
  if (req.status !== 'Pending') throw new ValidationError(`This request is already "${req.status}" — it can only be decided once`);

  await outcomeCorrectionRepository.update(id, { status: 'Rejected', rejectionReason: reason, resolvedAt: new Date() });
  await auditRepository.record(req.customerId, {
    type: 'RE_REJECTED_OUTCOME_CORRECTION',
    description: `${user.fullName} rejected ${req.salesmanId}'s outcome correction request. Reason: "${reason}". The recorded outcome stands unchanged.`,
    actor: user.fullName,
    source: 'Outcome Correction Review',
  });
  await notifyDecision(req.salesmanId, {
    approved: false,
    title: 'Outcome correction rejected',
    body: `${user.fullName} rejected your outcome correction request. Reason: "${reason}". The recorded outcome stands unchanged.`,
    customerId: req.customerId,
  });
  return outcomeCorrectionRepository.findById(id);
}

module.exports = { listForUser, request, approve, reject };
