const customerRepository = require('../repositories/customerRepository');
const ptpRepository = require('../repositories/ptpRepository');
const taskRepository = require('../repositories/taskRepository');
const disputeRepository = require('../repositories/disputeRepository');
const paymentClaimRepository = require('../repositories/paymentClaimRepository');
const escalationRepository = require('../repositories/escalationRepository');
const auditRepository = require('../repositories/auditRepository');
const outcomeCorrectionRepository = require('../repositories/outcomeCorrectionRepository');
const userRepository = require('../repositories/userRepository');
const salesmanService = require('./salesmanService');
const scoringService = require('./scoringService');
const metricsRepository = require('../repositories/metricsRepository');

const MATURED_STATUSES = ['kept', 'partiallyKept', 'broken'];
// Every dispute status where an RE/Management action is genuinely needed
// right now — a fresh claim to approve/reject, or a resolution owner's
// claim to verify. Distinct from DISPUTE_BUCKETS below (a 4-way status
// overview for the manager's report screen, where 'Awaiting Verification'
// is correctly grouped under "In Progress" instead) — this one drives the
// actionable "needs your attention" badges, which must not drop a dispute
// the moment it moves from Pending Approval to Awaiting Verification.
const DISPUTES_NEEDING_RE_ACTION = ['Pending Approval', 'Awaiting Verification'];
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
  // The client can't recompute this itself: GET /api/customers (what backs
  // every report's customer list) never carries auditHistory, only this
  // detail-fetch path does — a client-side re-derivation would silently
  // ignore real audit activity and overstate staleness. So the real
  // day-count this filter already computed is attached to each row instead
  // of being thrown away.
  const noFollowUpAccounts = dueCustomers
    .map((c) => ({ c, days: scoringService.daysSinceLastFollowUp(c, tasksByCustomer.get(c.id) || [], auditByCustomer.get(c.id) || []) }))
    .filter(({ days }) => days >= noFollowUpThresholdDays)
    .map(({ c, days }) => ({ ...c, daysSinceLastFollowUp: days }));

  const l4Cases = openEscalations.filter((e) => e.level === 'L4' && (user.role !== 'SALESPERSON' || customerIds.has(e.customerId)));
  const scopedOpenEscalations = user.role === 'SALESPERSON' ? openEscalations.filter((e) => customerIds.has(e.customerId)) : openEscalations;

  const physicalVisitsPendingReview = allTasks.filter((t) => t.type === 'physicalVisit' && t.status === 'completed' && !t.reviewedByRE);
  const disputesAwaitingReviewCount = allDisputes.filter((d) => DISPUTES_NEEDING_RE_ACTION.includes(d.status)).length;
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
    // Tier 1 of the real recovery-target tiers (25/35/50/70% of overdue —
    // see report_detail_screens.dart's RecoveryTargetVsActualReport).
    recoveryTarget: totalOverdueAmount * 0.25,
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

const DAY_MS = 86400000;
const daysBetween = (a, b) => Math.max(0, Math.round((new Date(b).getTime() - new Date(a).getTime()) / DAY_MS));
const ageDays = (from) => daysBetween(from, Date.now());

function queueStat(ages) {
  if (ages.length === 0) return { count: 0, oldestDays: 0, avgAgeDays: 0 };
  return {
    count: ages.length,
    oldestDays: Math.max(...ages),
    avgAgeDays: Math.round(ages.reduce((s, a) => s + a, 0) / ages.length),
  };
}

/**
 * RE performance scorecard for the Manager — "how much is waiting on the
 * RE, for how long, how fast do they turn decisions around, and how are
 * they doing on the escalations they own". Aggregated across the RE team
 * for the shared queues (disputes / claims / corrections have no
 * per-RE owner), and broken out per RE for escalation ownership.
 */
async function getRePerformance() {
  const [disputes, claims, allPtps, allTasks, escalations, users] = await Promise.all([
    disputeRepository.findAll(),
    paymentClaimRepository.findAll(),
    ptpRepository.findAll(),
    taskRepository.findAll(),
    escalationRepository.findAll(),
    userRepository.findAll(),
  ]);

  const now = Date.now();
  const since30 = now - 30 * DAY_MS;
  const res = users.filter((u) => u.role === 'RECOVERY_EXECUTIVE');

  // ---- Pending queue (waiting on the RE right now) ----
  const disputesPending = disputes.filter((d) => DISPUTES_NEEDING_RE_ACTION.includes(d.status));
  const claimsPending = claims.filter((c) => ['Awaiting Verification', 'Sync Pending'].includes(c.status));
  const ptpCorrectionsPending = allPtps.filter((p) => p.correctionStatus === 'Pending');
  const internalActionsPending = allTasks.filter(
    (t) => t.type === 'financialTeamFollowUp' && t.source === 'Record Outcome' && !['completed', 'closed'].includes(t.status)
  );

  const queue = {
    disputes: queueStat(disputesPending.map((d) => ageDays(d.raisedDate))),
    paymentClaims: queueStat(claimsPending.map((c) => ageDays(c.claimDate))),
    ptpCorrections: { count: ptpCorrectionsPending.length, oldestDays: 0, avgAgeDays: 0 },
    internalActions: queueStat(internalActionsPending.map((t) => ageDays(t.createdAt))),
  };
  queue.totalPending =
    queue.disputes.count + queue.paymentClaims.count + queue.ptpCorrections.count + queue.internalActions.count;
  queue.oldestPendingDays = Math.max(
    queue.disputes.oldestDays,
    queue.paymentClaims.oldestDays,
    queue.internalActions.oldestDays
  );

  // ---- Turnaround (disputes carry both raised + last_updated) ----
  const disputesDecided = disputes.filter(
    (d) => ['Approved', 'Rejected', 'Resolved', 'Returned to Recovery'].includes(d.status) &&
      new Date(d.lastUpdated).getTime() >= since30
  );
  const turnaroundDays = disputesDecided.map((d) => daysBetween(d.raisedDate, d.lastUpdated));
  const approvedCount = disputesDecided.filter((d) => ['Approved', 'Resolved'].includes(d.status)).length;
  const turnaround = {
    disputesDecided30d: disputesDecided.length,
    avgDecisionDays: turnaroundDays.length
      ? Math.round((turnaroundDays.reduce((s, a) => s + a, 0) / turnaroundDays.length) * 10) / 10
      : 0,
    approvedPct: disputesDecided.length ? Math.round((approvedCount / disputesDecided.length) * 100) : 0,
  };

  // ---- Escalations owned, per RE ----
  const byRe = res.map((re) => {
    const owned = escalations.filter((e) => e.ownerId === re.id);
    const open = owned.filter((e) => e.isOpen);
    const overdue = open.filter((e) => e.deadline && new Date(e.deadline).getTime() < now);
    const resolved30 = owned.filter((e) => !e.isOpen && new Date(e.updatedAt).getTime() >= since30);
    const resolveDays = resolved30.map((e) => daysBetween(e.createdAt, e.updatedAt));
    return {
      reId: re.id,
      reName: re.full_name || re.username,
      openEscalations: open.length,
      overdueEscalations: overdue.length,
      resolvedEscalations30d: resolved30.length,
      avgResolveDays: resolveDays.length
        ? Math.round((resolveDays.reduce((s, a) => s + a, 0) / resolveDays.length) * 10) / 10
        : 0,
    };
  });

  return { generatedAt: new Date().toISOString(), queue, turnaround, escalationsByRe: byRe };
}

module.exports = { getDashboard, getTrends, getRePerformance };
