const paymentClaimRepository = require('../repositories/paymentClaimRepository');
const customerRepository = require('../repositories/customerRepository');
const auditRepository = require('../repositories/auditRepository');
const taskService = require('./taskService');
const { notifyDecision, salesmanForCustomer } = require('./decisionNotify');
const { withTransaction } = require('../config/db');
const { NotFoundError } = require('../errors/AppError');

async function listForUser(user) {
  if (user.role === 'SALESPERSON') {
    const customers = await customerRepository.findBySalesman(user.id);
    const ids = new Set(customers.map((c) => c.id));
    const all = await paymentClaimRepository.findAll();
    return all.filter((c) => ids.has(c.customerId));
  }
  return paymentClaimRepository.findAll();
}

/**
 * Only a BUSY-confirmed payment can ever reduce a customer's financial
 * exposure — this is the one place that happens. A verified claim reduces
 * totalDue/totalOutstanding by the confirmed amount (clamped at zero); a
 * failed claim returns the customer to active recovery for that amount.
 */
async function verify(claimId, user, success) {
  const claim = await paymentClaimRepository.findById(claimId);
  if (!claim) throw new NotFoundError('Payment claim');

  await withTransaction(async (conn) => {
    await paymentClaimRepository.updateStatus(claimId, success ? 'Verified' : 'Failed', conn);

    if (success) {
      const customer = await customerRepository.findById(claim.customerId);
      const newTotalDue = Math.max(0, customer.totalDue - claim.amount);
      const newTotalOutstanding = Math.max(0, customer.totalOutstanding - claim.amount);
      await customerRepository.update(claim.customerId, { totalDue: newTotalDue, totalOutstanding: newTotalOutstanding }, conn);
      await auditRepository.record(
        claim.customerId,
        {
          type: 'PAYMENT_CLAIM_VERIFIED',
          description: `${user.fullName} verified against BUSY that the claimed ₹${claim.amount.toFixed(0)} payment (ref: ${claim.reference}) was actually received — financial exposure reduced by ₹${claim.amount.toFixed(0)}.`,
          actor: user.fullName,
          previousState: `₹${customer.totalDue.toFixed(0)} due`,
          newState: `₹${newTotalDue.toFixed(0)} due`,
          source: 'BUSY Reconciliation',
        },
        conn
      );
    } else {
      await auditRepository.record(
        claim.customerId,
        {
          type: 'PAYMENT_CLAIM_FAILED',
          description: `${user.fullName} reconciled against BUSY and found NO matching receipt for the claimed ₹${claim.amount.toFixed(0)} payment (ref: ${claim.reference}). The claim is marked Failed and the customer returns to active recovery for this amount.`,
          actor: user.fullName,
          source: 'BUSY Reconciliation',
        },
        conn
      );
    }
  });

  await notifyDecision(await salesmanForCustomer(claim.customerId), {
    approved: success,
    title: success ? 'Payment claim verified' : 'Payment claim failed',
    body: success
      ? `${user.fullName} verified the ₹${claim.amount.toFixed(0)} payment you logged (ref: ${claim.reference}) against BUSY — exposure reduced.`
      : `${user.fullName} found no matching receipt for the ₹${claim.amount.toFixed(0)} payment you logged (ref: ${claim.reference}). The customer returns to active recovery for this amount.`,
    customerId: claim.customerId,
  });

  // Whichever way this was decided, the customer needs to be told —
  // never let this go silent. Post-commit, best-effort, same pattern as
  // ptpService.reopenRecoveryAfterPtpOutcome. requireDueBalance: false —
  // this is about informing the customer of the decision, not chasing a
  // balance, so it fires regardless of what's still due.
  await withTransaction(async (conn) => {
    const created = await taskService.ensureFollowUpIfNeeded(
      claim.customerId,
      null,
      {
        reason: success ? 'Payment claim verified' : 'Payment claim rejected — no matching BUSY deposit found',
        auditType: success ? 'PAYMENT_CLAIM_VERIFIED_FOLLOWUP' : 'PAYMENT_CLAIM_REJECTED_FOLLOWUP',
        source: 'Payment Claim Review',
        priority: success ? 'Normal' : 'High',
        note: `${user.fullName} ${success ? 'verified' : 'rejected'} the ₹${claim.amount.toFixed(0)} payment claim (ref: ${claim.reference}).`,
        attachmentPath: claim.attachmentPath,
        requireDueBalance: false,
      },
      conn
    );
    if (created) {
      await customerRepository.update(claim.customerId, { currentRecoveryState: 'Action Required', primaryNextAction: 'CALL CUSTOMER' }, conn);
    }
  });

  return paymentClaimRepository.findById(claimId);
}

module.exports = { listForUser, verify };
