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
    const ts = new Date(a.occurredAt);
    if (!last || ts > last) last = ts;
  }
  for (const t of customerTasks) {
    const ts = new Date(t.completedAt || t.deadline);
    if (!last || ts > last) last = ts;
  }
  if (!last) return customer.oldestOverdueDays;
  const days = Math.floor((Date.now() - last.getTime()) / 86400000);
  return days < 0 ? 0 : days;
}

/** totalDue cleared, or a genuinely open task/active PTP already exists. */
function hasValidNextAction(customer, customerPtps, customerTasks) {
  if (customer.totalDue <= 0) return true;
  const hasOpenTask = customerTasks.some((t) => t.status !== 'completed' && t.status !== 'closed');
  const hasActivePtp = customerPtps.some((p) => p.status === 'scheduled' || p.status === 'financialSyncPending');
  return hasOpenTask || hasActivePtp;
}

/**
 * Customer Reliability & Credit Health Score (Master Build Book RMS-06) —
 * ported verbatim from the client's former `AppStore.creditHealthComponents`.
 * `creditLimit`/`lastPaymentDate` have no real source anywhere in this
 * schema yet, so — exactly like the client did — those two components stay
 * neutral rather than fabricating a number; nothing here is faked, it's
 * just honestly incomplete until those data sources exist.
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
  const ptpReliability = maturedPtps.length === 0 ? 70 : (keptCount / maturedPtps.length) * 100;

  let currentAgeing;
  if (customer.oldestOverdueDays <= 0) currentAgeing = 100;
  else if (customer.oldestOverdueDays <= 30) currentAgeing = 75;
  else if (customer.oldestOverdueDays <= 60) currentAgeing = 50;
  else if (customer.oldestOverdueDays <= 90) currentAgeing = 25;
  else currentAgeing = 10;

  // No credit_limit column exists yet — neutral, not fabricated.
  const exposure = 70;
  // No last-payment-date column exists yet — neutral, not fabricated.
  const recentTrend = 50;

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
function computeRecoveryScoreComponents({ ownedCustomers, ownedPtps, ownedTasks, auditByCustomer, taskByCustomer }) {
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

  const overdueTasks = ownedTasks.filter(isTaskOverdue).length;
  const followUpDiscipline = ownedTasks.length === 0 ? 100 : ((ownedTasks.length - overdueTasks) / ownedTasks.length) * 100;

  const ptpDiscipline = maturedPtps.length === 0 ? 75 : (keptCount / maturedPtps.length) * 100;

  const agedCustomers = ownedCustomers.filter((c) => c.oldestOverdueDays > 60);
  const agedCleared = agedCustomers.filter((c) => c.totalDue <= 0).length;
  const oldOutstandingReduction = agedCustomers.length === 0 ? 100 : (agedCleared / agedCustomers.length) * 100;

  const ownedPtpsByCustomer = groupBy(ownedPtps, (p) => p.customerId);
  const validNextActionCount = ownedCustomers.filter((c) =>
    hasValidNextAction(c, ownedPtpsByCustomer.get(c.id) || [], taskByCustomer.get(c.id) || [])
  ).length;
  const noFollowUpControl = ownedCustomers.length === 0 ? 100 : (validNextActionCount / ownedCustomers.length) * 100;

  const recentlyTouched = ownedCustomers.filter(
    (c) => daysSinceLastFollowUp(c, taskByCustomer.get(c.id) || [], auditByCustomer.get(c.id) || []) <= 7
  ).length;
  const processDiscipline = ownedCustomers.length === 0 ? 100 : (recentlyTouched / ownedCustomers.length) * 100;

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
