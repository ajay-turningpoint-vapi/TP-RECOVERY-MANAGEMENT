const customerRepository = require('../repositories/customerRepository');
const ptpRepository = require('../repositories/ptpRepository');
const taskRepository = require('../repositories/taskRepository');
const disputeRepository = require('../repositories/disputeRepository');
const escalationRepository = require('../repositories/escalationRepository');
const auditRepository = require('../repositories/auditRepository');
const outcomeCorrectionRepository = require('../repositories/outcomeCorrectionRepository');
const salesmanService = require('./salesmanService');
const scoringService = require('./scoringService');
const metricsRepository = require('../repositories/metricsRepository');

const MATURED_STATUSES = ['kept', 'partiallyKept', 'broken'];
const DISPUTE_BUCKETS = {
  'Awaiting Review': ['Pending Approval'],
  'In Progress': ['In Resolution', 'Awaiting Verification', 'Approved', 'Need More Information'],
  Resolved: ['Resolved'],
  Rejected: ['Rejected', 'Returned to Recovery'],
};

function isToday(date) {
  const d = new Date(date);
  const now = new Date();
  return d.getFullYear() === now.getFullYear() && d.getMonth() === now.getMonth() && d.getDate() === now.getDate();
}

/**
 * Every dashboard aggregate the client used to compute itself from raw
 * arrays — real, derived on read from customers/ptps/tasks/disputes/
 * escalations, role-scoped the same way every other list endpoint already
 * is (salesperson gets their own portfolio, RE/Management get the whole
 * book).
 */
async function getDashboard(user) {
  const [rawCustomers, allPtps, allTasks, allDisputes, openEscalations, roster, allAudit, allOutcomeCorrections] = await Promise.all([
    user.role === 'SALESPERSON' ? customerRepository.findBySalesman(user.id) : customerRepository.findAll(),
    ptpRepository.findAll(),
    user.role === 'SALESPERSON' ? taskRepository.findByOwner(user.id) : taskRepository.findAll(),
    user.role === 'SALESPERSON' ? [] : disputeRepository.findAll(),
    escalationRepository.findOpen(),
    user.role === 'SALESPERSON' ? [] : salesmanService.listRoster(),
    auditRepository.listAll(),
    user.role === 'SALESPERSON' ? [] : outcomeCorrectionRepository.findAll(),
  ]);

  const ptpsByCustomer = scoringService.groupBy(allPtps, (p) => p.customerId);
  const customerIds = new Set(rawCustomers.map((c) => c.id));
  const ptps = user.role === 'SALESPERSON' ? allPtps.filter((p) => customerIds.has(p.customerId)) : allPtps;

  const customers = rawCustomers.map((c) => {
    const cPtps = ptpsByCustomer.get(c.id) || [];
    const creditHealthScore = scoringService.computeCreditHealthScore(c, cPtps);
    return { ...c, creditHealthScore, creditHealthBand: scoringService.creditHealthBand(creditHealthScore) };
  });

  const dueCustomers = customers.filter((c) => c.totalDue > 0);
  const totalOverdueAmount = dueCustomers.reduce((s, c) => s + c.totalDue, 0);
  const overdue = dueCustomers.filter((c) => c.oldestOverdueDays > 0);
  const dueTodayPtps = ptps.filter((p) => p.status === 'scheduled' && isToday(p.promiseDate));
  const maturedPtps = ptps.filter((p) => MATURED_STATUSES.includes(p.status));
  const keptPtps = ptps.filter((p) => p.status === 'kept');
  const brokenPtps = ptps.filter((p) => p.status === 'broken');
  const brokenCustomerIds = new Set(brokenPtps.map((p) => p.customerId));

  const ageingBuckets = { 'Not Due': 0, '0 - 30 Days': 0, '31 - 60 Days': 0, '61 - 90 Days': 0, '90+ Days': 0 };
  for (const c of dueCustomers) {
    if (c.oldestOverdueDays <= 0) ageingBuckets['Not Due'] += c.totalDue;
    else if (c.oldestOverdueDays <= 30) ageingBuckets['0 - 30 Days'] += c.totalDue;
    else if (c.oldestOverdueDays <= 60) ageingBuckets['31 - 60 Days'] += c.totalDue;
    else if (c.oldestOverdueDays <= 90) ageingBuckets['61 - 90 Days'] += c.totalDue;
    else ageingBuckets['90+ Days'] += c.totalDue;
  }

  const disputeOverviewByStatus = {};
  for (const [bucket, statuses] of Object.entries(DISPUTE_BUCKETS)) {
    const matching = allDisputes.filter((d) => statuses.includes(d.status));
    disputeOverviewByStatus[bucket] = { count: matching.length, amount: matching.reduce((s, d) => s + d.amount, 0) };
  }

  const highRiskAccounts = dueCustomers.filter((c) => c.creditHealthScore != null && c.creditHealthScore < 70);
  const atRiskAccounts = dueCustomers.filter(
    (c) => c.escalationLevel !== 'none' || brokenCustomerIds.has(c.id) || c.oldestOverdueDays >= 60 || c.creditHealthBand === 'High' || c.creditHealthBand === 'Critical'
  );
  const noFollowUpThresholdDays = 4;
  const tasksByCustomer = scoringService.groupBy(allTasks, (t) => t.customerId);
  const auditByCustomer = scoringService.groupBy(allAudit, (a) => a.customerId);
  const noFollowUpAccounts = dueCustomers.filter(
    (c) => scoringService.daysSinceLastFollowUp(c, tasksByCustomer.get(c.id) || [], auditByCustomer.get(c.id) || []) >= noFollowUpThresholdDays
  );

  const l4Cases = openEscalations.filter((e) => e.level === 'L4' && (user.role !== 'SALESPERSON' || customerIds.has(e.customerId)));
  const scopedOpenEscalations = user.role === 'SALESPERSON' ? openEscalations.filter((e) => customerIds.has(e.customerId)) : openEscalations;

  const physicalVisitsPendingReview = allTasks.filter((t) => t.type === 'physicalVisit' && t.status === 'completed' && !t.reviewedByRE);
  const disputesAwaitingReviewCount = allDisputes.filter((d) => DISPUTE_BUCKETS['Awaiting Review'].includes(d.status)).length;
  const pendingTaskExtensionCount = allTasks.filter((t) => t.approvalStatus === 'Pending').length;
  const ptpCorrectionRequestsCount = ptps.filter((p) => p.correctionStatus === 'Pending').length;
  const pendingOutcomeCorrectionCount = allOutcomeCorrections.filter((r) => r.status === 'Pending').length;
  const salesmenOverdueTargetsCount = roster.filter((s) => s.collectionAchievedPercent < 60).length;

  const needsAttentionBadgeCount =
    salesmenOverdueTargetsCount +
    physicalVisitsPendingReview.length +
    disputesAwaitingReviewCount +
    ptpCorrectionRequestsCount +
    pendingTaskExtensionCount +
    pendingOutcomeCorrectionCount;

  const todaysCollected = ptps.filter((p) => (p.status === 'kept' || p.status === 'partiallyKept') && isToday(p.promiseDate));
  const todaysCollectedAmount = todaysCollected.reduce((s, p) => s + (p.amountReceived || 0), 0);
  const companyCollectionTargetToday = roster.reduce((s, sm) => s + sm.collectionTarget, 0);

  const topOverdueCustomers = [...dueCustomers].sort((a, b) => b.totalDue - a.totalDue).slice(0, 5);

  // A salesperson's own explainable Recovery Score breakdown (RMS-05) — the
  // "drill from score to human-readable contributing factors" requirement.
  // Not meaningful for RE/Management (no owned portfolio), so omitted then.
  const myRecoveryScoreComponents =
    user.role === 'SALESPERSON'
      ? scoringService.computeRecoveryScoreComponents({
        ownedCustomers: customers,
        ownedPtps: ptps,
        ownedTasks: allTasks,
        auditByCustomer,
        taskByCustomer: tasksByCustomer,
      })
      : null;

  // The Home dashboard's "Today's Recovery Tasks" X/Y card's Y — real,
  // computed from the actual audit trail (every recordOutcome call writes
  // one with source: 'Record Outcome' — see customerService.applyOutcome),
  // not an in-memory per-session counter. That in-memory counter used to
  // reset on every app restart/relaunch, showing a different count each
  // time you reopened the app on the same day; this is stable across
  // restarts and rolls over naturally at midnight since it's a genuine
  // "today" query, not a client-side flag that has to remember to reset.
  //
  // The customer *ids* (not just the count) are exposed too — Today's
  // Recovery Tasks' own row-level "done today" greying used to fall back
  // to customer.updatedAt, which turned out to be a false signal: the
  // daily BUSY sync (customerAgeingSync/customerInvoiceSync) rewrites
  // every synced customer's updated_at once a day regardless of whether
  // the salesperson touched them, so right after that sync ran nearly the
  // whole "Waiting / Monitoring" portfolio would falsely show as "done
  // today". This set is grounded in the same real audit trail as the
  // count above, so it can't be fooled by an unrelated write.
  const myRecoveryDoneTodayCustomerIds =
    user.role === 'SALESPERSON'
      ? [...new Set(allAudit.filter((a) => a.source === 'Record Outcome' && customerIds.has(a.customerId) && isToday(a.occurredAt)).map((a) => a.customerId))]
      : [];
  const myRecoveryDoneTodayCount = myRecoveryDoneTodayCustomerIds.length;

  return {
    myRecoveryScoreComponents,
    myRecoveryDoneTodayCount,
    myRecoveryDoneTodayCustomerIds,
    totalOverdueAmount,
    totalOverdueCustomerCount: dueCustomers.length,
    dueTodayPtpAmount: dueTodayPtps.reduce((s, p) => s + p.amountPromised, 0),
    dueTodayPtpCount: dueTodayPtps.length,
    overdueCustomersCount: overdue.length,
    overdueCustomersAmount: overdue.reduce((s, c) => s + c.totalDue, 0),
    ptpKeptMtdPercent: maturedPtps.length === 0 ? 0 : Math.round((keptPtps.length / maturedPtps.length) * 100),
    recoveryTarget: totalOverdueAmount * 0.12,
    outstandingAgeingBuckets: ageingBuckets,
    topOverdueCustomers,
    customers30PlusOverdueCount: dueCustomers.filter((c) => c.oldestOverdueDays >= 30).length,
    disputeOverviewByStatus,
    totalDisputesCount: allDisputes.length,
    totalDisputesAmount: allDisputes.reduce((s, d) => s + d.amount, 0),
    ptpOverviewStats: {
      givenCount: ptps.length,
      givenAmount: ptps.reduce((s, p) => s + p.amountPromised, 0),
      keptCount: keptPtps.length,
      keptAmount: keptPtps.reduce((s, p) => s + (p.amountReceived || 0), 0),
      brokenCount: brokenPtps.length,
      brokenAmount: brokenPtps.reduce((s, p) => s + p.amountPromised, 0),
      dueTodayCount: dueTodayPtps.length,
      dueTodayAmount: dueTodayPtps.reduce((s, p) => s + p.amountPromised, 0),
      successRatePercent: maturedPtps.length === 0 ? 0 : Math.round((keptPtps.length / maturedPtps.length) * 100),
      breakageRatePercent: maturedPtps.length === 0 ? 0 : Math.round((brokenPtps.length / maturedPtps.length) * 100),
    },
    highRiskAccounts,
    atRiskAccounts,
    moneyAtRisk: atRiskAccounts.reduce((s, c) => s + c.totalDue, 0),
    noFollowUpAccounts,
    l4Cases,
    openEscalationCases: scopedOpenEscalations,
    physicalVisitsPendingReviewCount: physicalVisitsPendingReview.length,
    disputesAwaitingReviewCount,
    pendingTaskExtensionCount,
    ptpCorrectionRequestsCount,
    pendingOutcomeCorrectionCount,
    needsAttentionBadgeCount,
    totalReceivedAllTime: ptps.filter((p) => p.status === 'kept' || p.status === 'partiallyKept').reduce((s, p) => s + (p.amountReceived || 0), 0),
    todaysCollectedAmount,
    todaysCollectedCustomerCount: new Set(todaysCollected.map((p) => p.customerId)).size,
    companyCollectionTargetToday,
    companyCollectionAchievedTodayPercent: companyCollectionTargetToday <= 0 ? 0 : Math.round((todaysCollectedAmount / companyCollectionTargetToday) * 100),
  };
}

/** Real accumulated daily history — whatever the snapshot job has genuinely recorded so far. No fabricated backfill. */
async function getTrends() {
  return metricsRepository.listRecent(90);
}

module.exports = { getDashboard, getTrends };
