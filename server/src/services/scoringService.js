const MATURED_STATUSES = ['kept', 'partiallyKept', 'broken'];

function isTaskOverdue(task) {
  return task.status !== 'completed' && task.status !== 'closed' && new Date(task.deadline) < new Date();
}

function groupBy(items, keyFn) {
  const map = new Map();
  for (const item of items) {
    const key = keyFn(item);
    if (!map.has(key)) map.set(key, []);
    map.get(key).push(item);
  }
  return map;
}

/**
 * Days since the most recent real recovery activity on this customer —
 * their latest audit event or task activity — falling back to their
 * overdue age when nothing has ever been logged. Ported verbatim from the
 * client's former `AppStore.daysSinceLastFollowUp`.
 */
function daysSinceLastFollowUp(customer, customerTasks, customerAuditEvents) {
  let last = null;
  for (const a of customerAuditEvents) {
    // System-authored rows (RECOVERY_TASK_CREATED, the reconcile sweep,
    // BUSY sync bookkeeping, …) aren't the salesperson doing anything —
    // counting them made every account look "touched today" the moment
    // the automatic sweep ran, regardless of whether a human ever acted.
    // Only a real actor's own entry counts as follow-up evidence.
    if (a.actor === 'System') continue;
    const ts = new Date(a.occurredAt);
    if (!last || ts > last) last = ts;
  }
  for (const t of customerTasks) {
    // Only a task's actual COMPLETION is real evidence of contact. Its
    // `deadline` is just a future due date — a task the reconcile sweep
    // auto-created moments ago (untouched, still pending) has a deadline
    // of "today", which previously counted as "touched today" and made
    // every salesperson with zero real activity look 100% recently active.
    if (!t.completedAt) continue;
    const ts = new Date(t.completedAt);
    if (!last || ts > last) last = ts;
  }
  if (!last) {
    // No real activity ever recorded. A customer who owes nothing needs no
    // follow-up, so 0 (fine) is honest. But a customer WITH real overdue
    // exposure and zero genuine contact is the textbook "no follow-up"
    // case — `customer.oldestOverdueDays` was a misleading proxy here: a
    // salesperson who has done nothing at all still read as "recently
    // touched" for every customer that happened to go overdue only a few
    // days ago (including a brand-new salesperson's whole freshly-synced
    // book). A large finite sentinel (not Infinity, which JSON.stringify
    // silently turns into null over the wire) means "never" for both this
    // function's own <= 7 check and reportService's >= threshold check.
    return customer.totalDue > 0 ? 999999 : 0;
  }
  const days = Math.floor((Date.now() - last.getTime()) / 86400000);
  return days < 0 ? 0 : days;
}

/** totalDue cleared, or a genuinely open task/active PTP already exists. */
function hasValidNextAction(customer, customerPtps, customerTasks) {
  if (customer.totalDue <= 0) return true;
  const hasOpenTask = customerTasks.some((t) => t.status !== 'completed' && t.status !== 'closed');
  // 'pendingVerification' = promise date reached, waiting for the 12:10 BUSY
  // check — still an open PTP, not "no next action".
  const hasActivePtp = customerPtps.some((p) => ['scheduled', 'pendingVerification', 'financialSyncPending'].includes(p.status));
  return hasOpenTask || hasActivePtp;
}

/**
 * Stricter than hasValidNextAction, for the Recovery Score's
 * noFollowUpControl only — that one's meant to reward the salesperson's
 * OWN engagement, not just "does this account have a safety net." An open
 * `source: 'Recovery'` task is the automatic sweep's own standing call
 * task, created identically for every overdue customer regardless of
 * whether the salesperson has done anything — it can never itself be
 * evidence of action (once acted on, applyOutcome closes/supersedes it).
 * An active PTP, in contrast, can only exist because the salesperson
 * recorded one — genuine evidence they engaged this customer.
 */
function hasRealFollowUpAction(customer, customerPtps, customerTasks) {
  if (customer.totalDue <= 0) return true;
  const hasRealOpenTask = customerTasks.some(
    (t) => t.status !== 'completed' && t.status !== 'closed' && t.source !== 'Recovery'
  );
  const hasActivePtp = customerPtps.some((p) => p.status === 'scheduled' || p.status === 'financialSyncPending');
  return hasRealOpenTask || hasActivePtp;
}

/**
 * Customer Reliability & Credit Health Score (Master Build Book RMS-06) —
 * ported verbatim from the client's former `AppStore.creditHealthComponents`,
 * but with `exposure`/`recentTrend` since wired up to the real BUSY-synced
 * `creditLimit`/`lastPaymentDate` fields (customerRepository.js) — the
 * "no real source exists" premise this comment used to state was wrong;
 * both are real, synced columns. Each stays neutral only when BUSY itself
 * has nothing on file for that one customer (no limit set / never paid).
 */
function computeCreditHealthComponents(customer, customerPtps) {
  const maturedPtps = customerPtps.filter((p) => MATURED_STATUSES.includes(p.status));
  const hasHistory = customer.totalDue > 0 || customer.oldestOverdueDays > 0 || maturedPtps.length > 0;
  if (!hasHistory) return null;

  let paymentTimeliness;
  if (customer.oldestOverdueDays <= 0) paymentTimeliness = 100;
  else if (customer.oldestOverdueDays <= 30) paymentTimeliness = 80;
  else if (customer.oldestOverdueDays <= 60) paymentTimeliness = 60;
  else if (customer.oldestOverdueDays <= 90) paymentTimeliness = 35;
  else paymentTimeliness = 15;

  const keptCount = maturedPtps.filter((p) => p.status === 'kept').length;
  const ptpReliability = maturedPtps.length === 0 ? 0 : (keptCount / maturedPtps.length) * 100;

  let currentAgeing;
  if (customer.oldestOverdueDays <= 0) currentAgeing = 100;
  else if (customer.oldestOverdueDays <= 30) currentAgeing = 75;
  else if (customer.oldestOverdueDays <= 60) currentAgeing = 50;
  else if (customer.oldestOverdueDays <= 90) currentAgeing = 25;
  else currentAgeing = 10;

  // Real BUSY-synced credit limit (customerRepository.js) — how much of
  // it is currently used. Low utilization = low risk = high score. Stays
  // neutral only when BUSY genuinely has no limit on file for this
  // customer (creditLimit <= 0) — can't compute a real ratio then.
  const exposure =
    customer.creditLimit > 0
      ? Math.max(0, Math.min(100, 100 - (customer.totalOutstanding / customer.creditLimit) * 100))
      : 70;

  // Real BUSY-synced last receipt date — how recently this customer
  // actually paid something, not just how old their oldest overdue
  // invoice is (that's paymentTimeliness/currentAgeing already). Stays
  // neutral only when they've genuinely never made a recorded payment.
  let recentTrend = 50;
  if (customer.lastPaymentDate) {
    const daysSincePayment = Math.floor((Date.now() - new Date(customer.lastPaymentDate).getTime()) / 86400000);
    if (daysSincePayment <= 30) recentTrend = 100;
    else if (daysSincePayment <= 60) recentTrend = 75;
    else if (daysSincePayment <= 90) recentTrend = 50;
    else if (daysSincePayment <= 180) recentTrend = 25;
    else recentTrend = 10;
  }

  let exceptions = 100;
  if (customer.disputedAmount > 0) exceptions -= 30;
  if (customer.escalationLevel !== 'none') exceptions -= 30;
  exceptions = Math.max(0, Math.min(100, exceptions));

  const total = Math.max(
    0,
    Math.min(100, paymentTimeliness * 0.3 + ptpReliability * 0.2 + currentAgeing * 0.2 + exposure * 0.15 + recentTrend * 0.1 + exceptions * 0.05)
  );

  return {
    paymentTimeliness: Math.round(paymentTimeliness),
    ptpReliability: Math.round(ptpReliability),
    currentAgeing: Math.round(currentAgeing),
    outstandingExposure: Math.round(exposure),
    recentPaymentTrend: Math.round(recentTrend),
    behaviouralExceptions: Math.round(exceptions),
    total: Math.round(total),
  };
}

function computeCreditHealthScore(customer, customerPtps) {
  const components = computeCreditHealthComponents(customer, customerPtps);
  return components ? components.total : null;
}

function creditHealthBand(score) {
  if (score == null) return 'Insufficient History';
  if (score >= 85) return 'Low Risk';
  if (score >= 70) return 'Moderate';
  if (score >= 50) return 'High';
  return 'Critical';
}

/**
 * Recovery Score (Master Build Book RMS-05 / SCR-001..005) — ported
 * verbatim from the client's former `AppStore.recoveryScoreComponents`.
 * `ownedCustomers`/`ownedPtps`/`ownedTasks`/`ownedAuditEvents` are already
 * filtered to the one salesperson by the caller.
 */

// Claim / dispute statuses that are still with the RE.
const OPEN_CLAIM_STATUSES = ['Awaiting Verification', 'Sync Pending'];
const OPEN_DISPUTE_STATUSES = ['Pending Approval', 'Approved', 'Need More Information', 'Awaiting Verification', 'In Resolution'];

/** Sets of customer ids with a claim / dispute still with the RE. */
function openClaimAndDisputeIds(claims = [], disputes = []) {
  return {
    openClaimIds: new Set(claims.filter((c) => OPEN_CLAIM_STATUSES.includes(c.status)).map((c) => c.customerId)),
    openDisputeIds: new Set(disputes.filter((d) => OPEN_DISPUTE_STATUSES.includes(d.status)).map((d) => d.customerId)),
  };
}

/**
 * The salesman's recorded outcome is still waiting on its own trigger, so
 * under the Record Outcome rules it deliberately has no task yet — it IS
 * the customer's next step: a claim / dispute with the RE, a Will Confirm
 * time still ahead, or a No Answer inside its 2-hour window. `lastOutcome`
 * is the customer's latest `source = 'Record Outcome'` audit row
 * ({ type, description, occurredAt }).
 */
function waitingOnOutcome(customerId, { lastOutcome, openClaimIds, openDisputeIds } = {}) {
  if ((openClaimIds && openClaimIds.has(customerId)) || (openDisputeIds && openDisputeIds.has(customerId))) return true;
  if (!lastOutcome) return false;
  const rts = require('./recoveryTaskService');
  const now = Date.now();
  if (lastOutcome.type === rts.WILL_CONFIRM_AUDIT_TYPE) {
    const at = rts.parseWillConfirmAt(lastOutcome.description);
    return !!at && at.getTime() > now;
  }
  if (lastOutcome.type === rts.NO_ANSWER_AUDIT_TYPE) {
    return new Date(lastOutcome.occurredAt).getTime() + rts.NO_ANSWER_WINDOW_MS > now;
  }
  return false;
}

/** Latest Record Outcome audit row from a customer's audit list (any order). */
function lastRecordedOutcome(audits = []) {
  let last = null;
  for (const a of audits) {
    if (a.source !== 'Record Outcome') continue;
    if (!last || new Date(a.occurredAt) > new Date(last.occurredAt)) last = a;
  }
  return last;
}

function computeRecoveryScoreComponents({ ownedCustomers, ownedPtps, ownedTasks, auditByCustomer, taskByCustomer, openClaimIds = new Set(), openDisputeIds = new Set() }) {
  // Every component below defaults to its "no problems found" value (100,
  // or 75 for PTP discipline) when its underlying collection is empty —
  // correct for an RMS salesperson who's simply caught up on a real
  // portfolio, but not for someone with zero RMS footprint altogether
  // (e.g. a BUSY-sourced-only salesman account, which has no RMS
  // customers/PTPs/tasks at all — those live in a completely separate
  // system). Mirrors computeCreditHealthComponents' hasHistory guard.
  if (ownedCustomers.length === 0 && ownedPtps.length === 0 && ownedTasks.length === 0) {
    return null;
  }

  // A salesperson CAN have customers assigned yet have done literally
  // nothing — e.g. a brand-new assignment whose small starting portfolio
  // simply has nothing currently owed. Every component's "no problems
  // found" default then stacks up into a misleadingly high score (seen
  // for real: a from-scratch salesperson scored 65% on day one, having
  // never recorded a single outcome). Require at least one genuine sign of
  // the salesperson's own activity — a PTP they ever recorded (any
  // status — even 'scheduled' only exists because they created it), a
  // real event-driven task (not the routine auto-generated Recovery
  // call, which exists identically regardless of effort — same filter
  // `realOwnedTasks` below uses), or a real (non-System-authored) audit
  // entry on one of their customers — before computing a score at all.
  // Until then: 0%, not a formula full of charitable defaults.
  const hasRealActivity =
    ownedPtps.length > 0 ||
    ownedTasks.some((t) => !(t.source === 'Recovery' && t.isRoutine)) ||
    ownedCustomers.some((c) => (auditByCustomer.get(c.id) || []).some((a) => a.actor !== 'System'));
  if (!hasRealActivity) {
    return {
      collectionPerformance: 0,
      followUpDiscipline: 0,
      ptpDiscipline: 0,
      oldOutstandingReduction: 0,
      noFollowUpControl: 0,
      processDiscipline: 0,
      total: 0,
    };
  }

  const maturedPtps = ownedPtps.filter((p) => MATURED_STATUSES.includes(p.status));
  const keptCount = maturedPtps.filter((p) => p.status === 'kept').length;

  const totalOverdue = ownedCustomers.reduce((s, c) => s + c.totalDue, 0);
  // Tier 1 of the company's real recovery-target tiers (25/35/50/70% of
  // overdue — see report_detail_screens.dart's RecoveryTargetVsActualReport)
  // is the single ongoing per-salesman/company target used everywhere else.
  const collectionTarget = totalOverdue * 0.25;
  const collectionAchieved = maturedPtps
    .filter((p) => p.status === 'kept' || p.status === 'partiallyKept')
    .reduce((s, p) => s + (p.amountReceived || 0), 0);
  const collectionPerformance = collectionTarget <= 0 ? 100 : Math.max(0, Math.min(100, (collectionAchieved / collectionTarget) * 100));

  // The routine auto-generated Recovery call (isRoutine, see
  // recoveryTaskService.js) exists identically for every overdue customer
  // regardless of the salesperson's own effort — it's already treated as
  // not a real task in the Tasks tab (AppStore.isRoutineRecoveryCall), so
  // it shouldn't count as one here either. An event-driven Recovery task
  // (isRoutine: false — a rejected claim, a broken PTP, …) still counts:
  // that one genuinely needs the salesperson's action.
  const realOwnedTasks = ownedTasks.filter((t) => !(t.source === 'Recovery' && t.isRoutine));
  const overdueTasks = realOwnedTasks.filter(isTaskOverdue).length;
  const followUpDiscipline = realOwnedTasks.length === 0 ? 0 : ((realOwnedTasks.length - overdueTasks) / realOwnedTasks.length) * 100;

  const ptpDiscipline = maturedPtps.length === 0 ? 0 : (keptCount / maturedPtps.length) * 100;

  const agedCustomers = ownedCustomers.filter((c) => c.oldestOverdueDays > 60);
  const agedCleared = agedCustomers.filter((c) => c.totalDue <= 0).length;
  const oldOutstandingReduction = agedCustomers.length === 0 ? 100 : (agedCleared / agedCustomers.length) * 100;

  const ownedPtpsByCustomer = groupBy(ownedPtps, (p) => p.customerId);
  // A recorded outcome still waiting on its own trigger (Will Confirm,
  // No Answer window, claim / dispute with the RE) counts as a next step.
  const validNextActionCount = ownedCustomers.filter(
    (c) =>
      hasRealFollowUpAction(c, ownedPtpsByCustomer.get(c.id) || [], taskByCustomer.get(c.id) || []) ||
      waitingOnOutcome(c.id, { lastOutcome: lastRecordedOutcome(auditByCustomer.get(c.id) || []), openClaimIds, openDisputeIds })
  ).length;
  const noFollowUpControl = ownedCustomers.length === 0 ? 100 : (validNextActionCount / ownedCustomers.length) * 100;

  // "Process/Evidence Discipline" — did the salesperson actually log real
  // contact recently. A customer who owes nothing needs no evidence at
  // all, so they don't belong in this measure either way: including them
  // (even as an automatic "pass") let a salesperson with real overdue
  // accounts and zero genuine evidence on any of them still read as
  // partly disciplined, just because part of their book happens to owe
  // nothing. Only customers who actually need following up count here.
  const customersNeedingFollowUp = ownedCustomers.filter((c) => c.totalDue > 0);
  const recentlyTouched = customersNeedingFollowUp.filter(
    (c) => daysSinceLastFollowUp(c, taskByCustomer.get(c.id) || [], auditByCustomer.get(c.id) || []) <= 7
  ).length;
  const processDiscipline =
    customersNeedingFollowUp.length === 0 ? 100 : (recentlyTouched / customersNeedingFollowUp.length) * 100;

  const total = Math.max(
    0,
    Math.min(
      100,
      collectionPerformance * 0.4 +
        followUpDiscipline * 0.2 +
        ptpDiscipline * 0.15 +
        oldOutstandingReduction * 0.1 +
        noFollowUpControl * 0.1 +
        processDiscipline * 0.05
    )
  );

  return {
    collectionPerformance: Math.round(collectionPerformance),
    followUpDiscipline: Math.round(followUpDiscipline),
    ptpDiscipline: Math.round(ptpDiscipline),
    oldOutstandingReduction: Math.round(oldOutstandingReduction),
    noFollowUpControl: Math.round(noFollowUpControl),
    processDiscipline: Math.round(processDiscipline),
    total: Math.round(total),
  };
}

const ESCALATION_SEVERITY = { none: 0, L1: 1, L2: 2, L3: 3, L4: 4 };

/**
 * The single canonical "who needs attention most" ordering: escalation
 * severity first, then oldest overdue days, then amount due. Ported
 * verbatim from the client's former `AppStore.compareByRecoveryPriority`.
 */
function compareByRecoveryPriority(a, b) {
  const escCompare = (ESCALATION_SEVERITY[b.escalationLevel] || 0) - (ESCALATION_SEVERITY[a.escalationLevel] || 0);
  if (escCompare !== 0) return escCompare;
  const overdueCompare = b.oldestOverdueDays - a.oldestOverdueDays;
  if (overdueCompare !== 0) return overdueCompare;
  return b.totalDue - a.totalDue;
}

module.exports = {
  waitingOnOutcome,
  lastRecordedOutcome,
  openClaimAndDisputeIds,
  isTaskOverdue,
  groupBy,
  daysSinceLastFollowUp,
  hasValidNextAction,
  computeCreditHealthComponents,
  computeCreditHealthScore,
  creditHealthBand,
  computeRecoveryScoreComponents,
  compareByRecoveryPriority,
  ESCALATION_SEVERITY,
};
