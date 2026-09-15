const customerRepository = require('../repositories/customerRepository');
const ptpRepository = require('../repositories/ptpRepository');
const paymentClaimRepository = require('../repositories/paymentClaimRepository');
const disputeRepository = require('../repositories/disputeRepository');
const taskRepository = require('../repositories/taskRepository');
const auditRepository = require('../repositories/auditRepository');
const { emitChange } = require('../realtime/eventBus');
const logger = require('../config/logger');

// The one task this service owns. It is the salesperson's "recover the
// part of the overdue that is NOT currently under an instrument" task —
// created, retargeted and closed only from here, so it can never multiply.
const RECOVERY_SOURCE = 'Recovery Reconcile';
const TOLERANCE = 1; // rupees — anything below this is treated as zero

// Instrument statuses that still "cover" money — i.e. the RE has not yet
// handed the slice back to the salesperson.
const OPEN_PTP_STATUSES = ['scheduled', 'pendingVerification', 'financialSyncPending'];
const COVERING_CLAIM_STATUSES = ['Awaiting Verification', 'Sync Pending'];
const COVERING_DISPUTE_STATUSES = ['Pending Approval', 'Approved', 'In Resolution', 'Need More Information'];


/**
 * covered  = Σ open PTP promised + Σ payment claims awaiting verification
 *          + Σ disputes still with the RE.
 * actionable = max(0, total_due − covered)   (sub-₹1 rounded to 0)
 */
function computeCoverage(customer, { ptps, claims, disputes }) {
  const id = customer.id;
  const ptpCovered = ptps
    .filter((p) => p.customerId === id && OPEN_PTP_STATUSES.includes(p.status))
    .reduce((s, p) => s + (Number(p.amountPromised) || 0), 0);
  const claimCovered = claims
    .filter((c) => c.customerId === id && COVERING_CLAIM_STATUSES.includes(c.status))
    .reduce((s, c) => s + (Number(c.amount) || 0), 0);
  const disputeCovered = disputes
    .filter((d) => d.customerId === id && COVERING_DISPUTE_STATUSES.includes(d.status))
    .reduce((s, d) => s + (Number(d.amount) || 0), 0);

  const covered = ptpCovered + claimCovered + disputeCovered;
  const totalDue = Number(customer.totalDue) || 0;
  let actionable = Math.max(0, totalDue - covered);
  if (actionable < TOLERANCE) actionable = 0;
  return { totalDue, covered, actionable, ptpCovered, claimCovered, disputeCovered };
}

/** covered/actionable for a customer id — used by getDetail to expose the split. */
async function coverageFor(customerId) {
  const customer = await customerRepository.findById(customerId);
  if (!customer) return { totalDue: 0, covered: 0, actionable: 0 };
  const [ptps, claims, disputes] = await Promise.all([
    ptpRepository.findByCustomer(customerId),
    paymentClaimRepository.findByCustomer(customerId),
    disputeRepository.findAll(),
  ]);
  return computeCoverage(customer, { ptps, claims, disputes });
}

/**
 * State-only pass — safe to call after every record-outcome / RE decision.
 * Flips currentRecoveryState between Action Required and Waiting/Monitoring
 * based on whether any overdue is still uncovered, and never touches tasks
 * (so it can't collide with the specific follow-ups the RE flows create).
 * The full task reconcile is the nightly job's concern.
 */
async function reconcileState(customerId, { trigger = 'state' } = {}) {
  const customer = await customerRepository.findById(customerId);
  if (!customer) return null;
  if (['RE Control'].includes(customer.currentRecoveryState)) return null;
  if (customer.escalationLevel !== 'none') return null;

  const { totalDue, covered, actionable } = await coverageFor(customerId);

  if (actionable > 0 && customer.currentRecoveryState === 'Waiting / Monitoring') {
    await customerRepository.update(customerId, {
      currentRecoveryState: 'Action Required',
      primaryNextAction: 'CALL CUSTOMER',
      hasValidNextAction: true,
    });
    await auditRepository.record(customerId, {
      type: 'RECOVERY_STATE_REOPENED',
      description: `Recovery reopened (${trigger}): ₹${covered.toFixed(0)} of ₹${totalDue.toFixed(0)} overdue is under a PTP / dispute / payment claim, ₹${actionable.toFixed(0)} is still the salesperson's to recover.`,
      actor: 'System',
      source: RECOVERY_SOURCE,
    });
    emitChange(['customers', 'tasks'], { customerId, reason: 'recovery.state' });
  }
  // Note: parking (Action Required -> Waiting/Monitoring) stays with
  // applyOutcome, which already parks on every resolving outcome. This
  // pass only *un-parks* a customer whose covered slices no longer add up
  // to the whole overdue.
  return { totalDue, covered, actionable };
}

/**
 * Nightly backstop — reconcile every customer that is parked or already
 * carries a recovery task, so a stuck park (RE never acted, instrument
 * quietly closed, balance moved) always finds its way back to the
 * salesperson. Runs right after the BUSY sync + PTP verification pass.
 */
async function reconcileAll() {
  const { driveRecoveryTask } = require('./recoveryTaskService');
  const [customers, allTasks] = await Promise.all([
    customerRepository.findAll(),
    taskRepository.findAll(),
  ]);
  const openRecoveryByCustomer = new Set(
    allTasks
      .filter((t) => t.source === 'Recovery' && !['completed', 'closed', 'cancelled'].includes(t.status))
      .map((t) => t.customerId)
  );
  // Accounts already in the recovery flow, or already carrying the one
  // `source='Recovery'` task. NOT every overdue customer — a never-worked
  // account gets its task the moment the salesperson first records an
  // outcome (customerService.recordOutcome → driveRecoveryTask). Ownerless
  // accounts are skipped entirely (nothing to work, no repeated
  // OWNERLESS_OVERDUE audit spam); RE Control is the RE's, not the sweep's.
  const targets = customers.filter(
    (c) =>
      c.assignedSalesmanId &&
      c.currentRecoveryState !== 'RE Control' &&
      (c.currentRecoveryState === 'Waiting / Monitoring' ||
        c.currentRecoveryState === 'Action Required' ||
        openRecoveryByCustomer.has(c.id))
  );
  let changed = 0;
  for (const c of targets) {
    try {
      // ONE writer of the recovery task — no more reconcileRecoveryTask
      // here (it created a second `source='Recovery Reconcile'` task
      // alongside this one). driveRecoveryTask retargets the single task to
      // today's actionable balance, closes it after two ₹0 passes, and
      // re-opens it if a salesperson bare-completed it while money's owed.
      await driveRecoveryTask(c.id, {
        headline: 'Overdue still open — keep calling the customer.',
        priority: 'Normal',
        deadlineHour: 21,
        refreshOnly: true,
      });
      changed += 1;
    } catch (err) {
      logger.error('[recoveryReconcile] sweep failed for customer', { customerId: c.id, message: err.message });
    }
  }
  logger.info(`[recoveryReconcile] daily sweep reconciled ${changed}/${targets.length} customer(s).`);
  emitChange(['customers', 'tasks'], { reason: 'recovery.reconcile.sweep' });
  return { reconciled: changed };
}

module.exports = { reconcileState, reconcileAll, computeCoverage, coverageFor, RECOVERY_SOURCE };
