const ptpRepository = require('../repositories/ptpRepository');
const customerRepository = require('../repositories/customerRepository');
const auditRepository = require('../repositories/auditRepository');
const escalationService = require('./escalationService');
const taskService = require('./taskService');
const { notifyDecision, salesmanForCustomer } = require('./decisionNotify');
const { driveRecoveryTask, rupees } = require('./recoveryTaskService');
const { NotFoundError, ValidationError } = require('../errors/AppError');

const OUTCOME_LABELS = {
  kept: { type: 'PTP_KEPT_PAYMENT_APPLIED', verb: 'kept' },
  partiallyKept: { type: 'PTP_PARTIALLY_KEPT_PAYMENT_APPLIED', verb: 'partially kept' },
  broken: { type: 'PTP_BROKEN', verb: 'broken' },
};

// Never auto-escalates to L4 (a human/RE judgment call) — 2 broken PTPs on
// the same customer reaches L2, 3+ reaches L3. Mirrors the same ladder the
// app used locally before the real API existed for this.
const BROKEN_PTP_ESCALATION_PLAN = {
  L2: 'RE Supervision — RE to call customer directly within 48 hours and supervise the salesperson\'s next attempt; escalate to RE Control if no response.',
  L3: 'RE Control — RE takes direct negotiation ownership from the salesperson; weekly review until resolved.',
};

async function listForUser(user) {
  if (user.role === 'SALESPERSON') {
    const customers = await customerRepository.findBySalesman(user.id);
    const ids = new Set(customers.map((c) => c.id));
    const all = await ptpRepository.findAll();
    return all.filter((p) => ids.has(p.customerId));
  }
  return ptpRepository.findAll();
}

async function getOrThrow(id) {
  const ptp = await ptpRepository.findById(id);
  if (!ptp) throw new NotFoundError('PTP');
  return ptp;
}

async function requestCorrection(ptpId, user, { amount, date, paymentMode, reason }) {
  const ptp = await getOrThrow(ptpId);
  // Same guarantee as outcome-edit requests: one pending request at a time,
  // so a second submission can't silently overwrite the first before the RE
  // has seen it.
  if (ptp.correctionStatus === 'Pending') {
    throw new ValidationError('A correction request for this PTP is already awaiting RE review.');
  }
  if (!(Number(amount) > 0)) {
    throw new ValidationError('A positive corrected amount is required.');
  }
  if (date == null || Number.isNaN(new Date(date).getTime())) {
    throw new ValidationError('A valid corrected date is required.');
  }
  await ptpRepository.update(ptpId, {
    correctionRequestedAmount: amount,
    correctionRequestedDate: date,
    correctionRequestedPaymentMode: paymentMode || null,
    correctionReason: reason,
    correctionStatus: 'Pending',
  });
  await auditRepository.record(ptp.customerId, {
    type: 'PTP_CORRECTION_REQUESTED',
    description: `${user.fullName} requested a correction to this PTP: amount ₹${ptp.amountPromised.toFixed(0)} → ₹${amount.toFixed(0)}, date ${new Date(ptp.promiseDate).toISOString()} → ${new Date(date).toISOString()}. Reason: "${reason}". Awaiting RE decision.`,
    actor: user.fullName,
    source: 'PTP Correction Request',
  });
  return ptpRepository.findById(ptpId);
}

async function approveCorrection(ptpId, user) {
  const ptp = await getOrThrow(ptpId);
  const newAmount = ptp.correctionRequestedAmount ?? ptp.amountPromised;
  const newDate = ptp.correctionRequestedDate ?? ptp.promiseDate;
  const newMode = ptp.correctionRequestedPaymentMode ?? ptp.paymentMode;

  await ptpRepository.update(ptpId, { amountPromised: newAmount, promiseDate: newDate, paymentMode: newMode, correctionStatus: 'Approved' });
  await auditRepository.record(ptp.customerId, {
    type: 'RE_APPROVED_PTP_CORRECTION',
    description: `${user.fullName} approved the salesperson's request to correct this PTP: amount changed from ₹${ptp.amountPromised.toFixed(0)} to ₹${newAmount.toFixed(0)}. Reason given: "${ptp.correctionReason || '-'}". The original commitment record is preserved in history, not overwritten.`,
    actor: user.fullName,
    source: 'PTP Correction Review',
  });
  await notifyDecision(await salesmanForCustomer(ptp.customerId), {
    approved: true,
    title: 'PTP correction approved',
    body: `${user.fullName} approved your PTP change — now ₹${newAmount.toFixed(0)} due ${new Date(newDate).toLocaleDateString('en-IN')}.`,
    customerId: ptp.customerId,
  });
  // Deliberately no driveRecoveryTask here — the PTP is still unverified
  // (still 'scheduled', just corrected). It must stay quiet, and Record
  // Outcome stays locked, until ptpVerificationService.finalizeDuePtps
  // actually verifies it against BUSY (kept/partiallyKept/broken).
  return ptpRepository.findById(ptpId);
}

async function rejectCorrection(ptpId, user, reason) {
  const ptp = await getOrThrow(ptpId);
  await ptpRepository.update(ptpId, { correctionStatus: 'Rejected' });
  await auditRepository.record(ptp.customerId, {
    type: 'RE_REJECTED_PTP_CORRECTION',
    description: `${user.fullName} rejected the salesperson's request to correct this PTP. Rejection reason: "${reason}". The original PTP commitment stands unchanged.`,
    actor: user.fullName,
    source: 'PTP Correction Review',
  });
  await notifyDecision(await salesmanForCustomer(ptp.customerId), {
    approved: false,
    title: 'PTP correction rejected',
    body: `${user.fullName} rejected your PTP correction request. Reason: "${reason}". The original PTP stands.`,
    customerId: ptp.customerId,
  });
  // The original PTP stands, still unverified — no driveRecoveryTask here
  // either; same reasoning as approveCorrection above.
  return ptpRepository.findById(ptpId);
}

const LEVEL_SEVERITY = { none: 0, L1: 1, L2: 2, L3: 3, L4: 4 };

/**
 * A Kept/Partially Kept outcome IS the confirmed payment — it reduces the
 * customer's real financial exposure by amountReceived (Product Law: a
 * matured PTP must actually move the numbers, not just relabel itself).
 * A Broken outcome re-evaluates the broken-PTP escalation ladder for this
 * customer: 2 broken PTPs reaches L2, 3+ reaches L3 — never auto L4, which
 * stays a human/RE judgment call.
 *
 * There is exactly one way a PTP's outcome gets decided: the automated
 * verification service (`services/ptpVerificationService.js`), which
 * queries real BUSY receipt data once the PTP matures. An RE has no manual
 * "mark outcome" override — their only lever on an open PTP is the
 * correction flow below (request/approve/reject an amount/date/mode edit),
 * never a direct kept/partiallyKept/broken call. This keeps every PTP
 * outcome — and the task/Record-Outcome unlock that follows it — backed by
 * a real BUSY-verified answer.
 */
/**
 * The shared write core of "a Scheduled/PendingVerification PTP got an
 * outcome". Currently only called by the automated verification service
 * (`services/ptpVerificationService.js`, `moveBalance: false` — BUSY
 * sync/receipts are already the source of truth, so touching customer
 * balances here would double-count). `moveBalance: true` remains supported
 * for any future caller that needs to move the balance itself, but nothing
 * in this codebase currently exercises that branch.
 *
 * Runs entirely on the passed-in transaction `conn`. Never calls the
 * escalation ladder itself — the caller does that after commit, same as
 * before.
 */
async function applyPtpOutcomeTx(
  conn,
  { ptp, customer, outcome, received, brokenReason, moveBalance, actor, source, description, previousState, newState }
) {
  await ptpRepository.update(
    ptp.id,
    { status: outcome, amountReceived: outcome === 'broken' ? null : received, brokenReason: outcome === 'broken' ? (brokenReason || null) : null },
    conn
  );

  let prev = previousState;
  let next = newState;

  if (moveBalance && outcome !== 'broken' && received > 0) {
    const newTotalDue = Math.max(0, customer.totalDue - received);
    const newTotalOutstanding = Math.max(0, customer.totalOutstanding - received);
    await customerRepository.update(ptp.customerId, { totalDue: newTotalDue, totalOutstanding: newTotalOutstanding }, conn);
    prev = prev ?? `₹${customer.totalDue.toFixed(0)} due`;
    next = next ?? `₹${newTotalDue.toFixed(0)} due`;
  }

  await auditRepository.record(
    ptp.customerId,
    { type: OUTCOME_LABELS[outcome].type, description, actor, previousState: prev, newState: next, source },
    conn
  );
}

async function evaluateBrokenPtpEscalation(customerId) {
  const customerPtps = await ptpRepository.findByCustomer(customerId);
  const brokenCount = customerPtps.filter((p) => p.status === 'broken').length;
  if (brokenCount < 2) return;

  const targetLevel = brokenCount >= 3 ? 'L3' : 'L2';
  const customer = await customerRepository.findById(customerId);
  if (LEVEL_SEVERITY[targetLevel] <= LEVEL_SEVERITY[customer.escalationLevel]) return;

  await escalationService.raise(
    customerId,
    { id: 'system', fullName: 'System' },
    {
      level: targetLevel,
      reason: `${brokenCount} confirmed Broken PTP (each reconciled against BUSY with no qualifying receipt found)`,
      plan: BROKEN_PTP_ESCALATION_PLAN[targetLevel],
      ownerId: customer.assignedSalesmanId,
      deadline: new Date(Date.now() + (targetLevel === 'L3' ? 2 : 3) * 86400000),
      moneyAtRisk: customer.totalDue,
    }
  );
}

/**
 * A PTP just resolved (kept / partiallyKept / broken). Drive the single
 * `source='Recovery'` call task to the customer's CURRENT overdue, due
 * 6 PM today, saying exactly what to collect. Always fires while money is
 * still due; closes the task at ₹0 or under RE control.
 *
 * `ctx = { promised, received }` shapes the task wording.
 */
async function reopenRecoveryAfterPtpOutcome(customerId, outcome, ctx = {}) {
  const customer = await customerRepository.findById(customerId);
  const name = (customer && customer.name) || 'the customer';
  const promised = ctx.promised != null ? Number(ctx.promised) : null;
  const received = ctx.received != null ? Number(ctx.received) : null;
  let headline;
  if (outcome === 'broken') {
    headline = `Call ${name} — promise broken, nothing received.`;
  } else if (outcome === 'partiallyKept') {
    headline = `Call ${name} — ${received != null ? rupees(received) : 'part'} received${promised != null ? ` of ${rupees(promised)}` : ''}.`;
  } else {
    headline = `Call ${name} — ${promised != null ? rupees(promised) : 'the promised amount'} received.`;
  }
  await driveRecoveryTask(customerId, {
    headline,
    priority: outcome === 'broken' ? 'High' : 'Normal',
    deadlineHour: 18,
  });
}

module.exports = {
  listForUser,
  requestCorrection,
  approveCorrection,
  rejectCorrection,
  applyPtpOutcomeTx,
  evaluateBrokenPtpEscalation,
  reopenRecoveryAfterPtpOutcome,
};
