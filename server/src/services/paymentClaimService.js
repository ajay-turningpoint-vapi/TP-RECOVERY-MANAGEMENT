const paymentClaimRepository = require('../repositories/paymentClaimRepository');
const customerRepository = require('../repositories/customerRepository');
const auditRepository = require('../repositories/auditRepository');
const { notifyDecision, salesmanForCustomer } = require('./decisionNotify');
const { driveRecoveryTask, rupees } = require('./recoveryTaskService');
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

  // Drive the ONE recovery task to what the customer still owes now:
  //   Approve → payment posted, totalDue already dropped → "collect the rest"
  //   Reject  → nothing posted → "collect the full outstanding"
  // Both close any RE / prior task and open a fresh salesperson call task
  // due 9 PM today (the RE-decision default deadline). While that task is
  // open the app re-enables Record Outcome for this customer.
  const headline = success
    ? `Payment of ${rupees(claim.amount)} verified.`
    : `Payment of ${rupees(claim.amount)} could NOT be verified — no matching BUSY receipt.`;
  await driveRecoveryTask(claim.customerId, {
    headline,
    priority: success ? 'Normal' : 'High',
    deadlineHour: 21,
  });

  return paymentClaimRepository.findById(claimId);
}

module.exports = { listForUser, verify };
