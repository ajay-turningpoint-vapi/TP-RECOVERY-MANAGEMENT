const taskRepository = require('../repositories/taskRepository');
const customerRepository = require('../repositories/customerRepository');
const userRepository = require('../repositories/userRepository');
const auditRepository = require('../repositories/auditRepository');
const escalationRepository = require('../repositories/escalationRepository');
const paymentClaimRepository = require('../repositories/paymentClaimRepository');
const notificationRepository = require('../repositories/notificationRepository');
const escalationService = require('./escalationService');
const { driveRecoveryTask } = require('./recoveryTaskService');
const { emitChange } = require('../realtime/eventBus');
const logger = require('../config/logger');

function startOfTodayLocal() {
  const d = new Date();
  d.setHours(0, 0, 0, 0);
  return d;
}
function sixPmOrNext() {
  const d = new Date();
  d.setHours(18, 0, 0, 0);
  if (d.getTime() <= Date.now()) d.setDate(d.getDate() + 1);
  return d;
}
function plusHours(h) {
  return new Date(Date.now() + h * 60 * 60 * 1000);
}

// The salesperson task types that carry a real "do this by <deadline>"
// commitment — a scheduled call-back or a physical visit.
const SALESMAN_TASK_TYPES = ['customerCall', 'physicalVisit'];
const OPEN = (s) => !['completed', 'closed', 'cancelled'].includes(s);

// Source tag on the RE follow-up this sweep creates — also its own dedupe key.
const SOURCE = 'Missed Deadline';

function endOfToday() {
  const d = new Date();
  d.setHours(23, 59, 59, 0);
  return d;
}

/**
 * Any open salesperson task (scheduled call / physical visit) whose
 * deadline has passed with nothing recorded means the salesperson let it
 * lapse — recording an outcome supersedes the task, so a still-open,
 * past-deadline one IS "salesman did nothing". For each such account this
 * creates ONE same-day (deadline = 23:59 today) High-priority follow-up
 * task owned by the Recovery Executive, so it lands in their "Due Today"
 * queue and they can chase / reassign / escalate. Idempotent: skips an
 * account that already has an open Missed-Deadline task.
 */
async function sweepMissedDeadlines() {
  const [allTasks, users] = await Promise.all([
    taskRepository.findAll(),
    userRepository.findAll(),
  ]);

  const re = users.find((u) => u.role === 'RECOVERY_EXECUTIVE');
  if (!re) {
    logger.warn('[missedDeadline] no Recovery Executive user — sweep skipped.');
    return { created: 0, scanned: 0 };
  }
  const salesmanIds = new Set(
    users.filter((u) => u.role === 'SALESPERSON').map((u) => u.id)
  );
  const now = Date.now();

  // Accounts that already carry an open RE Missed-Deadline follow-up — one
  // is enough, don't stack a fresh one every sweep.
  const alreadyFlagged = new Set(
    allTasks
      .filter((t) => t.source === SOURCE && OPEN(t.status))
      .map((t) => t.customerId)
  );

  const missed = allTasks.filter(
    (t) =>
      OPEN(t.status) &&
      SALESMAN_TASK_TYPES.includes(t.type) &&
      salesmanIds.has(t.ownerId) &&
      t.source !== SOURCE &&
      new Date(t.deadline).getTime() < now
  );

  let created = 0;
  for (const t of missed) {
    if (alreadyFlagged.has(t.customerId)) continue;
    alreadyFlagged.add(t.customerId);

    const customer = await customerRepository.findById(t.customerId);
    if (!customer || Number(customer.totalDue) <= 0) continue;

    // Accounts already under RE supervision (L2 / L3) keep the salesperson
    // chasing on a 2-day cadence — don't also flood the RE's Due Today with
    // a missed-deadline nudge for a task the RE is already watching. Just
    // re-drive the single recovery task 48h out.
    if (
      ['L2', 'L3'].includes(customer.escalationLevel) &&
      ['Recovery', 'Recovery Reconcile', 'No Answer', 'Record Outcome'].includes(t.source)
    ) {
      await driveRecoveryTask(t.customerId, {
        headline: `Keep calling ${customer.name || 'the customer'} — still nothing recorded.`,
        priority: 'Normal',
        deadlineOverride: plusHours(48),
      });
      continue;
    }

    const label = t.type === 'physicalVisit' ? 'physical visit' : 'call';
    const dueAt = new Date(t.deadline).toLocaleString('en-IN');

    await taskRepository.insert({
      type: 'customerCall',
      customerId: t.customerId,
      ownerId: re.id,
      deadline: endOfToday(),
      priority: 'High',
      reason: `Salesman missed the scheduled ${label} (due ${dueAt}) with nothing recorded — follow up, reassign, or escalate today.`,
      source: SOURCE,
    });
    await auditRepository.record(t.customerId, {
      type: 'SALESMAN_MISSED_DEADLINE',
      description: `Scheduled ${label} due ${dueAt} passed with no recorded outcome. A same-day follow-up task was auto-created for the Recovery Executive.`,
      actor: 'System',
      source: SOURCE,
    });
    created += 1;
  }

  if (created > 0) emitChange(['tasks', 'customers'], { reason: 'missed.deadline.sweep' });
  logger.info(
    `[missedDeadline] sweep done — ${missed.length} lapsed task(s) scanned, ${created} RE follow-up(s) created.`
  );
  return { created, scanned: missed.length };
}

// Customer states that mean "the salesperson recorded a Will Confirm /
// Follow-up and is waiting for the customer to call back".
const FOLLOW_UP_ACTIONS = new Set(['Follow-up Scheduled', 'Follow-up']);

/**
 * A "Will Confirm / Follow-up Scheduled" outcome puts a call-back task on
 * the salesperson for the promised date+time. When that time passes with
 * nothing recorded, close the stale task and open a fresh
 * `source='Recovery'` call task for the current balance (which also
 * re-enables Record Outcome on the customer in the app). Run BEFORE
 * sweepMissedDeadlines so the fresh task — not the stale one — is what
 * that sweep sees.
 */
async function sweepExpiredFollowUps() {
  const allTasks = await taskRepository.findAll();
  const now = Date.now();

  const expired = allTasks.filter(
    (t) =>
      OPEN(t.status) &&
      t.type === 'customerCall' &&
      t.source === 'Record Outcome' &&
      new Date(t.deadline).getTime() < now
  );

  let rolled = 0;
  const handledCustomers = new Set();
  for (const t of expired) {
    if (handledCustomers.has(t.customerId)) continue;
    const customer = await customerRepository.findById(t.customerId);
    if (!customer) continue;
    // Only the Will Confirm / Follow-up case — a Customer Refused call-back
    // (also source 'Record Outcome') is handled by its L2 escalation, not here.
    if (!FOLLOW_UP_ACTIONS.has(customer.primaryNextAction)) continue;
    handledCustomers.add(t.customerId);

    await taskRepository.update(t.id, {
      status: 'completed',
      completedAt: new Date(),
      outcome: 'Confirm time passed — no outcome recorded. Rolled into a fresh call task.',
    });
    await auditRepository.record(t.customerId, {
      type: 'FOLLOWUP_TIME_PASSED',
      description: `The "Will Confirm" time (${new Date(t.deadline).toLocaleString('en-IN')}) passed with nothing recorded — a fresh call task was created.`,
      actor: 'System',
      source: 'Recovery',
    });

    await driveRecoveryTask(t.customerId, {
      headline: `Call ${customer.name || 'the customer'} — the confirm time has passed with nothing recorded.`,
      priority: 'Normal',
      deadlineHour: 18,
    });
    rolled += 1;
  }

  if (rolled > 0) emitChange(['tasks', 'customers'], { reason: 'followup.expired.sweep' });
  logger.info(`[missedDeadline] expired-follow-up sweep — ${rolled} Will-Confirm task(s) rolled into a fresh call task.`);
  return { rolled, scanned: expired.length };
}

const VISIT_REASON = 'Non-response threshold reached';

/**
 * Every 2 hours. Keeps the single `source='No Answer'` call task nagging
 * (deadline bumped +2h) while the salesperson hasn't recorded anything. If
 * the task has been open since before today (a whole day, nothing
 * recorded), swap it for a Physical Visit (due 6 PM) and remove the call
 * tasks. Two visit cycles → auto-escalate to L2.
 */
async function sweepNoAnswerCycle() {
  const allTasks = await taskRepository.findAll();
  const open = allTasks.filter(
    (t) => t.type === 'customerCall' && t.source === 'No Answer' && OPEN(t.status)
  );
  const byCustomer = new Map();
  for (const t of open) {
    if (!byCustomer.has(t.customerId)) byCustomer.set(t.customerId, []);
    byCustomer.get(t.customerId).push(t);
  }

  const dayStart = startOfTodayLocal().getTime();
  let bumped = 0;
  let toVisit = 0;
  let escalated = 0;

  for (const [customerId, tasks] of byCustomer) {
    tasks.sort((a, b) => new Date(a.createdAt || a.deadline) - new Date(b.createdAt || b.deadline));
    const oldest = tasks[0];
    const openedBeforeToday = new Date(oldest.createdAt || oldest.deadline).getTime() < dayStart;
    const customer = await customerRepository.findById(customerId);
    if (!customer) continue;

    if (openedBeforeToday) {
      // A full day with no outcome → Physical Visit, remove the call tasks.
      for (const t of tasks) {
        await taskRepository.update(t.id, {
          status: 'completed',
          completedAt: new Date(),
          outcome: 'No answer all day — replaced by a Physical Visit.',
        });
      }
      await taskRepository.insert({
        type: 'physicalVisit',
        customerId,
        ownerId: customer.assignedSalesmanId || oldest.ownerId,
        deadline: sixPmOrNext(),
        priority: 'High',
        reason: VISIT_REASON,
        source: 'No Answer',
      });
      await auditRepository.record(customerId, {
        type: 'NO_ANSWER_PHYSICAL_VISIT',
        description: 'No answer all day with nothing recorded — a Physical Visit task was created (due 6 PM) and the call tasks removed.',
        actor: 'System',
        source: 'No Answer',
      });
      toVisit += 1;

      // Two full non-response cycles → L2.
      const visitCycles = allTasks.filter(
        (t) => t.customerId === customerId && t.type === 'physicalVisit' && t.reason === VISIT_REASON
      ).length + 1; // +1 for the one we just inserted
      if (
        visitCycles >= 2 &&
        ['none', 'L1'].includes(customer.escalationLevel) &&
        (await escalationRepository.findOpenByCustomer(customerId)).length === 0
      ) {
        await escalationService.raise(customerId, { id: 'system', fullName: 'System' }, {
          level: 'L2',
          reason: `Customer unreachable — ${visitCycles} full non-response cycles (repeated unanswered calls + ${visitCycles} physical-visit escalations, no contact made).`,
          plan: 'Salesperson continues field follow-up under RE supervision. RE to check the contact numbers on file and pursue alternate channels.',
          ownerId: customer.assignedSalesmanId,
          deadline: plusHours(72),
          moneyAtRisk: customer.totalDue,
        });
        escalated += 1;
      }
    } else {
      // Still today — keep exactly one, nag it forward 2h.
      await taskRepository.update(oldest.id, { deadline: plusHours(2) });
      for (const dup of tasks.slice(1)) {
        await taskRepository.update(dup.id, {
          status: 'completed',
          completedAt: new Date(),
          outcome: 'Superseded — single No Answer task kept.',
        });
      }
      bumped += 1;
    }
  }

  if (bumped + toVisit > 0) emitChange(['tasks', 'customers', 'escalations'], { reason: 'no.answer.cycle' });
  logger.info(`[noAnswerCycle] ${bumped} bumped, ${toVisit} → physical visit, ${escalated} → L2.`);
  return { bumped, toVisit, escalated };
}

/**
 * RE decision SLAs. Payment Already Made claims are a MANUAL RE check
 * (nothing to do with BUSY) with a 9 PM deadline; Internal Action gives
 * the RE a 4-hour task. When either is breached, raise a warning
 * notification (deduped by an audit marker) so the RE — and their manager
 * — sees it. Run alongside the other sweeps.
 */
async function sweepRESlaBreaches() {
  const now = Date.now();
  const nineTonight = (() => { const d = new Date(); d.setHours(21, 0, 0, 0); return d.getTime(); })();
  let flagged = 0;

  // 1) Payment claims awaiting the RE's manual verification past 9 PM (or
  //    from a previous day).
  const [claims, allTasks, allAudit] = await Promise.all([
    paymentClaimRepository.findAll(),
    taskRepository.findAll(),
    auditRepository.listAll(),
  ]);
  const flaggedClaimIds = new Set(
    allAudit.filter((a) => a.type === 'RE_SLA_BREACH_CLAIM').map((a) => a.description.match(/claim ([\w-]+)/)?.[1]).filter(Boolean)
  );
  for (const claim of claims) {
    if (!['Awaiting Verification', 'Sync Pending'].includes(claim.status)) continue;
    const claimedAt = new Date(claim.claimDate).getTime();
    const overdue = now > nineTonight ? claimedAt < now - 60 * 1000 : claimedAt < startOfTodayLocal().getTime();
    if (!overdue || flaggedClaimIds.has(claim.id)) continue;
    const customer = await customerRepository.findById(claim.customerId);
    await notificationRepository.insert({
      severity: 'warning',
      title: 'Payment claim past its 9 PM verification SLA',
      body: `The ₹${Math.round(claim.amount)} "Payment Already Made" claim for ${customer ? customer.name : claim.customerId} has not been verified by the RE. Verify it manually against BUSY / the operator.`,
      customerId: claim.customerId,
    });
    await auditRepository.record(claim.customerId, {
      type: 'RE_SLA_BREACH_CLAIM',
      description: `Payment claim ${claim.id} breached its 9 PM verification SLA — RE notified.`,
      actor: 'System',
      source: 'RE SLA',
    });
    flagged += 1;
  }

  // 2) Internal Action RE tasks past their (4-hour) deadline.
  const flaggedTaskIds = new Set(
    allAudit.filter((a) => a.type === 'RE_SLA_BREACH_INTERNAL').map((a) => a.description.match(/task ([\w-]+)/)?.[1]).filter(Boolean)
  );
  for (const t of allTasks) {
    if (t.type !== 'financialTeamFollowUp' || !OPEN(t.status)) continue;
    if (new Date(t.deadline).getTime() >= now || flaggedTaskIds.has(t.id)) continue;
    const customer = await customerRepository.findById(t.customerId);
    await notificationRepository.insert({
      severity: 'warning',
      title: 'Internal Action past its 4-hour SLA',
      body: `An Internal Action for ${customer ? customer.name : t.customerId} has been open past its deadline with no RE decision.`,
      customerId: t.customerId,
    });
    await auditRepository.record(t.customerId, {
      type: 'RE_SLA_BREACH_INTERNAL',
      description: `Internal Action task ${t.id} breached its 4-hour SLA — RE notified.`,
      actor: 'System',
      source: 'RE SLA',
    });
    flagged += 1;
  }

  if (flagged > 0) logger.info(`[reSla] ${flagged} RE SLA breach(es) flagged.`);
  return { reSlaFlagged: flagged };
}

module.exports = { sweepMissedDeadlines, sweepExpiredFollowUps, sweepNoAnswerCycle, sweepRESlaBreaches, SOURCE };
