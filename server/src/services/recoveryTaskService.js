const customerRepository = require('../repositories/customerRepository');
const taskRepository = require('../repositories/taskRepository');
const auditRepository = require('../repositories/auditRepository');
const logger = require('../config/logger');
const { withTransaction } = require('../config/db');

// Marker text on a recovery task that a ₹0 pass has parked once already —
// the next ₹0 pass closes it. Used instead of a second audit-row write so
// two calls in the same tick can't double-log.
const NOTHING_ACTIONABLE_REASON =
  'Nothing actionable right now — every rupee is under a promise / claim / dispute (or the balance is ₹0). Confirming next pass.';

// The one salesperson recovery task per customer. Only this module
// creates / retargets / closes a `source='Recovery'` task, so it can
// never multiply. Every event that changes the balance or an instrument
// (PTP verified, payment claim decided, …) calls `driveRecoveryTask`.
const RECOVERY_SOURCE = 'Recovery';
const OPEN_TASK = (s) => !['completed', 'closed', 'cancelled'].includes(s);

// Open salesperson call tasks left behind by a RETIRED task-writer — they
// ARE the recovery task under an old name, with no live job managing them.
// When no `source='Recovery'` task exists we adopt one of these (flip its
// source and retarget it) instead of stacking a second call task.
const ADOPTABLE_SOURCES = ['Recovery Reconcile', 'Daily Snapshot', 'Task Completion Guard'];

// Open call tasks that a live lifecycle job owns and keys off their source
// string — currently just the No-Answer 2-hourly cycle (`sweepNoAnswerCycle`).
// We must NOT adopt these (renaming the source silently kills that job's
// handling of the customer and lets `applyOutcome` create a duplicate). A
// SPECIFIC event (broken PTP, rejected dispute, failed claim) still opens
// its own recovery task alongside; only the generic nightly refresh defers
// to the owning job. (A "Will Confirm" outcome no longer creates any
// customerCall task at all until followUpQueue's job fires, so there's
// nothing left to job-own under a 'Record Outcome' source.)
const JOB_OWNED_CALL_SOURCES = ['No Answer'];

function atHourLocal(hour, base = new Date()) {
  const d = new Date(base);
  d.setHours(hour, 0, 0, 0);
  // That hour has already passed today → give the salesperson the rest of
  // the day rather than a deadline in the past.
  if (d.getTime() <= base.getTime()) {
    d.setHours(23, 59, 59, 0);
  }
  return d;
}

function rupees(n) {
  return `₹${Math.round(Number(n) || 0).toLocaleString('en-IN')}`;
}

/**
 * Drive the single `source='Recovery'` call task to the customer's CURRENT
 * real overdue (`customer.totalDue`). `headline` is the "why" line; this
 * appends "Collect ₹{totalDue}, record a new outcome." The task keeps
 * existing (retargeted, never duplicated) at EVERY escalation level —
 * L2 / L3 / RE Control included — until the balance is ₹0; the RE
 * supervising an account never means the salesperson stops calling.
 * Suppressed only while a physical visit is open. `conn` optional.
 *
 * opts: { headline, priority, deadlineHour = 18, deadlineOverride, collectAmount, refreshOnly }
 * `collectAmount` overrides the figure to chase; otherwise it's the
 * customer's ACTIONABLE overdue = totalDue − (open PTPs + payment claims
 * with the RE + disputes with the RE), so a fully-promised/claimed
 * account correctly parks. `deadlineOverride` (a Date) beats `deadlineHour`.
 * Every automatically-generated call task is due same-day 6 PM (18:00) —
 * every caller in this codebase passes 18 explicitly; the default here
 * matches for any future caller that omits it.
 */
async function driveRecoveryTask(customerId, opts = {}, conn) {
  const { headline = 'Follow up.', priority = 'Normal', deadlineHour = 18, deadlineOverride, collectAmount, refreshOnly = false } = opts;

  const body = async (c) => {
    const customer = await customerRepository.findById(customerId);
    if (!customer) return;

    let due;
    if (collectAmount != null) {
      due = Math.max(0, Number(collectAmount) || 0);
    } else {
      // actionable = totalDue − covering instruments (same math as the
      // reconcile service). Inline require avoids a circular import.
      try {
        const { coverageFor } = require('./recoveryReconcileService');
        due = (await coverageFor(customerId)).actionable;
      } catch (err) {
        // Fall back to the raw balance so recovery never stalls — but this
        // over-asks (ignores covering PTPs / claims / disputes), so make
        // sure it's visible rather than silent.
        logger.warn('[recoveryTask] coverageFor failed — using raw totalDue', { customerId, message: err.message });
        due = Number(customer.totalDue) || 0;
      }
    }
    const tasks = await taskRepository.findByCustomer(customerId, c);
    const openCalls = tasks.filter((t) => t.type === 'customerCall' && OPEN_TASK(t.status));
    let openRecovery = openCalls.find((t) => t.source === RECOVERY_SOURCE) || null;
    const openPhysicalVisit = tasks.some((t) => t.type === 'physicalVisit' && OPEN_TASK(t.status));
    const openJobOwnedCall = openCalls.some((t) => JOB_OWNED_CALL_SOURCES.includes(t.source));

    // Exactly one recovery task per customer: if we don't already own one
    // but the salesperson is carrying an equivalent call task (an older
    // parallel writer, a plain follow-up), adopt it rather than add a
    // second. Only when there's real money to chase — a ₹0 pass leaves the
    // No-Answer cycle's own task alone.
    if (!openRecovery && due >= 1 && customer.assignedSalesmanId) {
      const adoptable = openCalls.find(
        (t) =>
          t.ownerId === customer.assignedSalesmanId &&
          (t.source == null || ADOPTABLE_SOURCES.includes(t.source))
      );
      if (adoptable) {
        await taskRepository.update(adoptable.id, { source: RECOVERY_SOURCE }, c);
        openRecovery = { ...adoptable, source: RECOVERY_SOURCE };
      }
    }

    const close = async (text) => {
      if (openRecovery) {
        await taskRepository.update(
          openRecovery.id,
          { status: 'completed', completedAt: new Date(), outcome: text },
          c
        );
      }
    };

    // RE has taken over the whole account — the salesperson holds no
    // recovery task. Close any stray one and stop; L2 / L3 still keep it
    // (the salesperson works under supervision), only full RE Control does not.
    if (customer.currentRecoveryState === 'RE Control') {
      if (openRecovery) {
        await close('Closed — the RE has taken direct control of this account.');
        await auditRepository.record(
          customerId,
          { type: 'RECOVERY_TASK_CLOSED_RE_CONTROL', description: 'Recovery task closed — account is under RE Control.', actor: 'System', source: RECOVERY_SOURCE },
          c
        );
      }
      return;
    }

    if (due < 1) {
      // Nothing actionable — every rupee is under a promise/claim/dispute,
      // or the balance is cleared. Guard against a stale/behind BUSY
      // balance wrongly zeroing it: on the FIRST zero pass drop the task to
      // Low priority and flag it; only CLOSE it once a later pass also sees
      // ₹0 (task already Low). Park the account when nothing else holds it.
      if (openRecovery) {
        // "Already parked once" = Low priority OR the holding reason is
        // already set (covers two calls racing in the same tick — the
        // second sees the first's reason even if the priority write hasn't
        // landed yet, so it closes instead of logging a duplicate audit).
        const alreadyParked =
          openRecovery.priority === 'Low' || openRecovery.reason === NOTHING_ACTIONABLE_REASON;
        if (alreadyParked) {
          await close('Auto-closed — nothing left actionable across two checks.');
        } else {
          await taskRepository.update(
            openRecovery.id,
            { priority: 'Low', reason: NOTHING_ACTIONABLE_REASON },
            c
          );
          await auditRepository.record(
            customerId,
            { type: 'RECOVERY_NOTHING_ACTIONABLE', description: 'No actionable overdue; recovery task held pending the next confirmation.', actor: 'System', source: RECOVERY_SOURCE },
            c
          );
        }
      }
      if (
        customer.escalationLevel === 'none' &&
        customer.currentRecoveryState !== 'Waiting / Monitoring' &&
        !tasks.some((t) => ['customerCall', 'physicalVisit'].includes(t.type) && OPEN_TASK(t.status) && t.id !== (openRecovery && openRecovery.id))
      ) {
        await customerRepository.update(customerId, { currentRecoveryState: 'Waiting / Monitoring' }, c);
      }
      return;
    }

    // A physical visit is the salesperson's own next step — they don't
    // run a competing recovery call alongside it. Close any open recovery
    // task; the normal flow re-drives a fresh one once the visit resolves
    // (bare-completing it re-enters here via completeTask). RE-owned tasks
    // (dispute review, missed-deadline supervision nudge, escalation) go to
    // the RE's queue, not the salesperson's, so they DON'T suppress this —
    // the salesperson keeps chasing while the RE does their part.
    if (openPhysicalVisit) {
      if (openRecovery) {
        await close('Paused — a physical visit is the active step.');
        await auditRepository.record(
          customerId,
          { type: 'RECOVERY_TASK_PAUSED', description: 'Recovery call task paused while a physical visit is the active step.', actor: 'System', source: RECOVERY_SOURCE },
          c
        );
      }
      return;
    }

    // Generic nightly refresh only: if there's no recovery task to
    // retarget but the salesperson already has a No-Answer / Will-Confirm
    // call the owning job manages, don't stack a generic "keep calling"
    // task next to it. A specific event (refreshOnly=false — broken PTP,
    // rejected dispute, failed claim) still opens its own.
    if (refreshOnly && !openRecovery && openJobOwnedCall) return;

    const deadline = deadlineOverride instanceof Date ? deadlineOverride : atHourLocal(deadlineHour);

    // refreshOnly (the daily sweep / 2-hour nudge): keep an existing task's
    // own headline, just re-point the ₹ amount and bump the deadline —
    // never overwrite a specific "PTP broken" / "dispute rejected" reason
    // with a generic one.
    if (refreshOnly && openRecovery) {
      const bumped = /Collect ₹[\d,]+/.test(openRecovery.reason)
        ? openRecovery.reason.replace(/Collect ₹[\d,]+/, `Collect ${rupees(due)}`)
        : `${openRecovery.reason} Collect ${rupees(due)}, record a new outcome.`;
      await taskRepository.update(openRecovery.id, { reason: bumped, deadline }, c);
      return;
    }

    const reason = `${headline} Collect ${rupees(due)}, record a new outcome.`;

    if (openRecovery) {
      await taskRepository.update(openRecovery.id, { reason, priority, deadline }, c);
    } else if (customer.assignedSalesmanId) {
      await taskRepository.insert(
        {
          type: 'customerCall',
          customerId,
          ownerId: customer.assignedSalesmanId,
          deadline,
          priority,
          reason,
          source: RECOVERY_SOURCE,
        },
        c
      );
    } else {
      await auditRepository.record(
        customerId,
        {
          type: 'OWNERLESS_OVERDUE',
          description: `${rupees(due)} overdue needs an owner — no salesperson assigned.`,
          actor: 'System',
          source: RECOVERY_SOURCE,
        },
        c
      );
      return;
    }

    await customerRepository.update(
      customerId,
      { currentRecoveryState: 'Action Required', primaryNextAction: 'CALL CUSTOMER', hasValidNextAction: true },
      c
    );
    await auditRepository.record(
      customerId,
      {
        type: 'RECOVERY_TASK_CREATED',
        description: `Auto call task: Collect ${rupees(due)}, due ${deadline.toLocaleString('en-IN')}.`,
        actor: 'System',
        source: RECOVERY_SOURCE,
      },
      c
    );
  };

  // Called inside a caller's open transaction → let it throw so it rolls
  // back with them. Called on its own (the post-commit hook every RE
  // decision / outcome uses) → run in its own transaction and NEVER throw:
  // a recovery-task failure must not turn a committed decision into an
  // HTTP 500. The nightly reconcile re-drives it on the next pass anyway.
  if (conn) return body(conn);
  try {
    return await withTransaction(body);
  } catch (err) {
    logger.error('[recoveryTask] driveRecoveryTask failed (swallowed — decision already committed)', {
      customerId,
      message: err.message,
    });
    return undefined;
  }
}

module.exports = { driveRecoveryTask, RECOVERY_SOURCE, rupees, atHourLocal };
