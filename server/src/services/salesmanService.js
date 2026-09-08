const salesmanRepository = require('../repositories/salesmanRepository');
const customerRepository = require('../repositories/customerRepository');
const ptpRepository = require('../repositories/ptpRepository');
const taskRepository = require('../repositories/taskRepository');
const auditRepository = require('../repositories/auditRepository');
const scoringService = require('./scoringService');

const MATURED_STATUSES = ['kept', 'partiallyKept', 'broken'];

function isToday(date) {
  const d = new Date(date);
  const now = new Date();
  return d.getFullYear() === now.getFullYear() && d.getMonth() === now.getMonth() && d.getDate() === now.getDate();
}

/**
 * The full company salesmen roster, with every performance figure
 * genuinely computed from real customers/ptps/tasks — no stored,
 * driftable counters, and no fabricated "calls done today" figure (there
 * is no real call-log table anywhere in this schema, so that feature was
 * removed rather than simulated — see the client-side removal in the same
 * change).
 */
async function listRoster() {
  // BUSY-sourced salesman accounts now own real customers/history in this
  // same table (the daily sync upserts straight into `customers` — see
  // customerRepository.upsertFromBusy), so they're genuinely evaluable by
  // this roster now — no longer excluded (that guard only made sense
  // under the earlier "read-only overlay" design, where they had zero RMS
  // footprint and every rate would've fallen back to a fabricated 100%).
  const [salespersons, allCustomers, allPtps, allTasks, allAudit] = await Promise.all([
    salesmanRepository.findAllSalespersons(),
    customerRepository.findAll(),
    ptpRepository.findAll(),
    taskRepository.findAll(),
    auditRepository.listAll(),
  ]);

  const ptpsByCustomer = scoringService.groupBy(allPtps, (p) => p.customerId);
  const tasksByCustomer = scoringService.groupBy(allTasks, (t) => t.customerId);
  const auditByCustomer = scoringService.groupBy(allAudit, (a) => a.customerId);

  return salespersons.map((sp) => {
    const owned = allCustomers.filter((c) => c.assignedSalesmanId === sp.id);
    const ownedIds = new Set(owned.map((c) => c.id));
    const ownedPtps = allPtps.filter((p) => ownedIds.has(p.customerId));
    const ownedTasks = allTasks.filter((t) => t.ownerId === sp.id);
    const maturedPtps = ownedPtps.filter((p) => MATURED_STATUSES.includes(p.status));
    const keptCount = maturedPtps.filter((p) => p.status === 'kept').length;
    const brokenPtps = ownedPtps.filter((p) => p.status === 'broken').length;
    const overdueTasks = ownedTasks.filter(scoringService.isTaskOverdue).length;

    const totalOverdue = owned.reduce((s, c) => s + c.totalDue, 0);
    const collectionTarget = totalOverdue * 0.12;
    const collectionAchieved = maturedPtps
      .filter((p) => p.status === 'kept' || p.status === 'partiallyKept')
      .reduce((s, p) => s + (p.amountReceived || 0), 0);
    const collectionAchievedPercent = collectionTarget <= 0 ? 100 : Math.round((collectionAchieved / collectionTarget) * 100);

    const taskCompletionRate = ownedTasks.length === 0 ? 100 : Math.round(((ownedTasks.length - overdueTasks) / ownedTasks.length) * 100);
    const validNextActionCount = owned.filter((c) =>
      scoringService.hasValidNextAction(c, ptpsByCustomer.get(c.id) || [], tasksByCustomer.get(c.id) || [])
    ).length;
    const validNextActionRate = owned.length === 0 ? 100 : Math.round((validNextActionCount / owned.length) * 100);

    const escalatedCustomers = owned.filter((c) => c.escalationLevel !== 'none').length;
    const highRiskCustomers = owned.filter((c) => {
      const band = scoringService.creditHealthBand(scoringService.computeCreditHealthScore(c, ptpsByCustomer.get(c.id) || []));
      return band === 'High' || band === 'Critical';
    }).length;

    const dueTodayPtps = ownedPtps.filter((p) => p.status === 'scheduled' && isToday(p.promiseDate)).reduce((s, p) => s + p.amountPromised, 0);
    const expectedCollection = ownedPtps.filter((p) => p.status === 'scheduled').reduce((s, p) => s + p.amountPromised, 0);

    // Every consumer of this roster (report_detail_screens.dart and ~30
    // other screens) treats recoveryScore as always-present — BUSY-only
    // accounts are already excluded above, so this null branch shouldn't
    // fire for any account actually reaching this point, but a safe zero
    // fallback here is cheap insurance against ever handing those screens
    // a null they don't expect.
    const recoveryScoreComponents = scoringService.computeRecoveryScoreComponents({
      ownedCustomers: owned,
      ownedPtps,
      ownedTasks,
      auditByCustomer,
      taskByCustomer: tasksByCustomer,
    }) ?? {
      collectionPerformance: 0,
      followUpDiscipline: 0,
      ptpDiscipline: 0,
      oldOutstandingReduction: 0,
      noFollowUpControl: 0,
      processDiscipline: 0,
      total: 0,
    };

    return {
      id: sp.id,
      // Every screen matches roster entries against Customer.assignedSalesmanId
      // / Task.ownerId by this 'name' key, which has always actually held the
      // real user id (e.g. 'rahul'), not a display name — keeping it named
      // 'name' avoids a sweeping rename across ~20 screens for no behavior
      // change. Real display name is 'fullName' below.
      name: sp.id,
      // No separate employee-code concept exists — the real user id is what's
      // shown/searched as empId, same as before.
      empId: sp.id,
      username: sp.username,
      fullName: sp.fullName,
      branch: sp.branch,
      phone: sp.phone,
      recoveryScore: recoveryScoreComponents.total,
      recoveryScoreComponents,
      customers: owned.length,
      totalOverdue,
      brokenPtps,
      overdueTasks,
      expectedCollection,
      dueTodayPtps,
      ptpKeptPercent: maturedPtps.length === 0 ? 0 : Math.round((keptCount / maturedPtps.length) * 100),
      collectionTarget,
      collectionAchieved,
      collectionAchievedPercent,
      taskCompletionRate,
      validNextActionRate,
      escalatedCustomers,
      highRiskCustomers,
    };
  });
}

module.exports = { listRoster };
