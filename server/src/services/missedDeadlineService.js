const taskRepository = require('../repositories/taskRepository');
const customerRepository = require('../repositories/customerRepository');
const userRepository = require('../repositories/userRepository');
const auditRepository = require('../repositories/auditRepository');
const escalationRepository = require('../repositories/escalationRepository');
const paymentClaimRepository = require('../repositories/paymentClaimRepository');
const notificationRepository = require('../repositories/notificationRepository');
const escalationService = require('./escalationService');
const { driveRecoveryTask, atHourLocal } = require('./recoveryTaskService');
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
function plusDays(d) {
  return new Date(Date.now() + d * 24 * 60 * 60 * 1000);
}

// Customer Refused's growing reopen cadence. The task's OWN initial
// deadline (set in customerService.js) is already +2 days — this is for
// each subsequent auto-reopen with nothing recorded: 1st reopen +3 days,
// 2nd +4, 3rd +5. The INTERVAL stops growing past +5 (never +6, +7, ...),
// but reopening itself never stops — from the 3rd reopen on it just keeps
// firing every 5 days, indefinitely, until a new outcome is recorded or
// the escalation is resolved. `reopenCount` is how many times it's
// already been auto-reopened (0 the first time this fires).
const REFUSED_REOPEN_DAYS = [3, 4, 5];
function refusedReopenDelay(reopenCount) {
  return REFUSED_REOPEN_DAYS[Math.min(reopenCount, REFUSED_REOPEN_DAYS.length - 1)];
}

// The salesperson task types that carry a real "do this by <deadline>"
// commitment — a scheduled call-back or a physical visit.
const SALESMAN_TASK_TYPES = ['customerCall', 'physicalVisit'];
const OPEN = (s) => !['completed', 'closed', 'cancelled'].includes(s);

// Source tag on the RE follow-up this sweep creates — also its own dedupe key.
const SOURCE = 'Missed Deadline';

/**
 * Any open salesperson task (scheduled call / physical visit) whose
 * deadline has passed with nothing recorded means the salesperson let it
 * lapse — recording an outcome supersedes the task, so a still-open,
 * past-deadline one IS "salesman did nothing". For each such account this
 * creates ONE same-day, due-8-PM, High-priority follow-up task owned by
 * the Recovery Executive — "call that salesman" — so it lands in their
 * "Due Today" queue with a 2-hour window (auto-generated call tasks are
 * now due 6 PM, see recoveryTaskService.atHourLocal) to reach them before
 * it goes overdue too. Idempotent: skips an account that already has an
 * open Missed-Deadline task.
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
    // chasing, same-day 6 PM like every other auto-generated call task —
    // don't also flood the RE's Due Today with a missed-deadline nudge for
    // a task the RE is already watching. Just re-drive the single recovery
    // task.
    if (
      ['L2', 'L3'].includes(customer.escalationLevel) &&
      ['Recovery', 'Recovery Reconcile', 'No Answer', 'Record Outcome'].includes(t.source)
    ) {
      await driveRecoveryTask(t.customerId, {
        headline: `Keep calling ${customer.name || 'the customer'} — still nothing recorded.`,
        priority: 'Normal',
        deadlineOverride: atHourLocal(18),
      });
      continue;
    }

    const label = t.type === 'physicalVisit' ? 'physical visit' : 'call';
    const dueAt = new Date(t.deadline).toLocaleString('en-IN');
    // userRepository.findAll() returns raw DB rows (snake_case), not the
    // mapped camelCase shape — full_name, not fullName.
    const salesman = users.find((u) => u.id === t.ownerId);
    const salesmanName = salesman ? salesman.full_name : t.ownerId;

    await taskRepository.insert({
      type: 'customerCall',
      customerId: t.customerId,
      ownerId: re.id,
      deadline: atHourLocal(20),
      priority: 'High',
      reason: `${salesmanName} missed the scheduled ${label} (due ${dueAt}) with nothing recorded — call them, then follow up, reassign, or escalate today.`,
      source: SOURCE,
    });
    await auditRepository.record(t.customerId, {
      type: 'SALESMAN_MISSED_DEADLINE',
      description: `${salesmanName}'s scheduled ${label} due ${dueAt} passed with no recorded outcome. A follow-up task (due 8 PM) was auto-created for the Recovery Executive to call them.`,
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

// "Will Confirm / Follow-up Scheduled" no longer relies on this polling
// sweep — customerService.recordOutcome schedules a one-off, exact-time
// job (see src/queues/followUpQueue.js, src/workers/followUpWorker.js)
// the moment the outcome is recorded, instead of creating a task
// immediately and waiting for a 2-hourly scan to notice it lapsed.

const VISIT_REASON = 'Non-response threshold reached';

/**
 * Runs on the 2-hourly sweep. Keeps the single `source='No Answer'` call
 * task open, re-due 2 hours out each pass, while the salesperson hasn't
 * recorded anything. If the task has been open since before today (a
 * whole day, nothing recorded), swap it for a Physical Visit (due 6 PM)
 * and remove the call tasks. Two visit cycles → auto-escalate to L2.
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
      // Still today — keep exactly one, nag it forward 2h (No Answer's own
      // faster cadence, not the same-day-6PM default).
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

/**
 * Customer Refused's growing reopen cadence. Finds open `source='Customer
 * Refused'` call tasks whose deadline has passed, and — only while the
 * customer's still genuinely mid-refusal (reasonForAction is still
 * 'Customer Refused' — a newer outcome would have superseded this task
 * already, so this is a real belt-and-braces guard) AND the L2 escalation
 * it raised is still open (escalationService.resolve already closes this
 * task itself on resolve, but this guard covers any other way the case
 * could have closed) — bumps the SAME task forward per
 * `refusedReopenDelay`, increments the counter. Never inserts a second
 * task for the salesperson.
 *
 * Once the cadence has settled at its steady 5-day interval
 * (`reopenCount >= 2`), two things additionally happen on every such
 * expiry, WITHOUT touching the salesperson's own cycle (it keeps running
 * exactly as before, forever): the reopened task is due exactly 6 PM that
 * day (matching every other auto-generated task) instead of an arbitrary
 * time, and a real "a 5-day cycle just passed with nothing done" task is
 * raised for the RE (see `ensureRefusedCycleReAlert`) — Call
 * Salesman / Mark Done, same as the Missed-Deadline RE task.
 */
async function sweepRefusedCycle() {
  const allTasks = await taskRepository.findAll();
  const now = Date.now();

  const expired = allTasks.filter(
    (t) => OPEN(t.status) && t.type === 'customerCall' && t.source === 'Customer Refused' && new Date(t.deadline).getTime() < now
  );

  let reopened = 0;
  let reAlerted = 0;
  for (const t of expired) {
    const customer = await customerRepository.findById(t.customerId);
    if (!customer || customer.reasonForAction !== 'Customer Refused') continue;
    const stillEscalated = await escalationRepository.findOpenByCustomer(t.customerId);
    if (stillEscalated.length === 0) continue;

    const reopenCount = customer.refusedReopenCount || 0;
    const delayDays = refusedReopenDelay(reopenCount);
    const steadyState = reopenCount >= 2;
    const newDeadline = steadyState ? atHourLocal(18, plusDays(delayDays)) : plusDays(delayDays);
    await taskRepository.update(t.id, { deadline: newDeadline });
    await customerRepository.update(t.customerId, { refusedReopenCount: reopenCount + 1 });
    await auditRepository.record(t.customerId, {
      type: 'CUSTOMER_REFUSED_TASK_REOPENED',
      description: `Customer Refused call task re-opened (reopen #${reopenCount + 1}) — next due in ${delayDays} day(s). Still under L2 supervision with nothing new recorded.`,
      actor: 'System',
      source: 'Customer Refused',
    });
    reopened += 1;

    if (steadyState && (await ensureRefusedCycleReAlert(t.customerId, customer))) {
      reAlerted += 1;
    }
  }

  if (reopened > 0) emitChange(['tasks', 'customers'], { reason: 'refused.cycle.sweep' });
  logger.info(`[refusedCycle] sweep done — ${expired.length} lapsed Customer Refused task(s) scanned, ${reopened} re-opened, ${reAlerted} RE alert(s) raised.`);
  return { refusedReopened: reopened };
}

/**
 * A full 5-day (steady-state) non-response cycle just passed on a
 * Customer Refused case with nothing recorded — raise a real task for the
 * RE: call the salesperson and find out what's going on. Idempotent
 * (skips if one's already open for this customer) so it never stacks,
 * same dedupe pattern as sweepMissedDeadlines.
 */
async function ensureRefusedCycleReAlert(customerId, customer) {
  const [users, existingTasks] = await Promise.all([userRepository.findAll(), taskRepository.findByCustomer(customerId)]);
  if (existingTasks.some((t) => t.source === 'Refused Cycle' && OPEN(t.status))) return false;

  const re = users.find((u) => u.role === 'RECOVERY_EXECUTIVE');
  if (!re) {
    logger.warn('[refusedCycle] no Recovery Executive user — RE alert skipped.', { customerId });
    return false;
  }
  const salesman = users.find((u) => u.id === customer.assignedSalesmanId);
  const salesmanName = salesman ? salesman.full_name : customer.assignedSalesmanId;

  await taskRepository.insert({
    type: 'customerCall',
    customerId,
    ownerId: re.id,
    deadline: atHourLocal(18),
    priority: 'High',
    reason: `${salesmanName} — a 5-day non-response cycle passed on this Customer Refused case with nothing recorded. Call them.`,
    source: 'Refused Cycle',
  });
  await auditRepository.record(customerId, {
    type: 'REFUSED_CYCLE_RE_ALERT',
    description: `A 5-day non-response cycle passed with nothing recorded — a follow-up task was auto-created for the Recovery Executive to call ${salesmanName}. The salesperson's own reopening call task continues unaffected.`,
    actor: 'System',
    source: 'Refused Cycle',
  });
  return true;
}

module.exports = { sweepMissedDeadlines, sweepNoAnswerCycle, sweepRESlaBreaches, sweepRefusedCycle, SOURCE };
