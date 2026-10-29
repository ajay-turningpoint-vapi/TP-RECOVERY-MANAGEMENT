const customerRepository = require('../repositories/customerRepository');
const taskRepository = require('../repositories/taskRepository');
const ptpRepository = require('../repositories/ptpRepository');
const paymentClaimRepository = require('../repositories/paymentClaimRepository');
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
// string — the No-Answer 2-hourly cycle (`sweepNoAnswerCycle`) and the
// Customer Refused 2d→3→4→5d reopening cycle (`missedDeadlineService.
// sweepRefusedCycle`). We must NOT adopt these (renaming the source
// silently kills that job's handling of the customer and lets
// `applyOutcome` create a duplicate), and the generic nightly refresh
// must not stack a second `source='Recovery'` task next to one either —
// confirmed live: every customer currently in a Customer Refused state
// had exactly this duplicate before 'Customer Refused' was added here. A
// SPECIFIC event (broken PTP, rejected dispute, failed claim) still opens
// its own recovery task alongside; only the generic nightly refresh defers
// to the owning job. (A "Will Confirm" outcome no longer creates any
// customerCall task at all until followUpQueue's job fires, so there's
// nothing left to job-own under a 'Record Outcome' source.)
const JOB_OWNED_CALL_SOURCES = ['No Answer', 'Customer Refused'];

// Mirrors recoveryReconcileService's OPEN_PTP_STATUSES — a PTP in any of
// these hasn't been checked against BUSY yet (see ptpVerificationService's
// 12:10 IST job).
const OPEN_PTP_STATUSES = ['scheduled', 'pendingVerification', 'financialSyncPending'];

// A "Payment Already Made" claim the RE hasn't decided yet.
const OPEN_CLAIM_STATUSES = ['Awaiting Verification', 'Sync Pending'];

// Mirrors followUpService.FOLLOW_UP_ACTIONS (not imported — followUpService
// requires this module, so importing back would be circular).
const FOLLOW_UP_ACTIONS = new Set(['Follow-up Scheduled', 'Follow-up']);

// The follow-up moment of the salesperson's LATEST recorded outcome, if
// that outcome is a Will Confirm — parsed from its audit description
// ("Customer will confirm — Date: 2026-11-02 Time: 10:00 AM", written by
// customer_360_screen.dart's Will Confirm call site; time may be 12h or
// 24h by device locale). Read from the audit trail rather than
// customer.primaryNextAction because that field can be overwritten (a
// pre-guard sweep on 22 Oct flipped many to 'CALL CUSTOMER'), which made
// the Will Confirm wait invisible and let the sweep keep a task alive.
// IST (+05:30) is the business timezone — see env.businessTimezone.
const WILL_CONFIRM_AUDIT_TYPE = 'Will Confirm — Follow-Up Scheduled';
// Mirrors customerService.outcomeAuditLabel / applyOutcome's 2-hour
// No-Answer callback window (pendingNoAnswerJob.dueAt = +2h).
const NO_ANSWER_AUDIT_TYPE = 'No Answer Logged';
const NO_ANSWER_WINDOW_MS = 2 * 60 * 60 * 1000;

function parseWillConfirmAt(description) {
  const m = /Date:\s*(\d{4}-\d{2}-\d{2})\s+Time:\s*(\d{1,2}):(\d{2})\s*([AaPp][Mm])?/.exec(description || '');
  if (!m) return null;
  let hour = Number(m[2]);
  const ampm = (m[4] || '').toUpperCase();
  if (ampm === 'PM' && hour < 12) hour += 12;
  if (ampm === 'AM' && hour === 12) hour = 0;
  const at = new Date(`${m[1]}T${String(hour).padStart(2, '0')}:${m[3]}:00+05:30`);
  return Number.isNaN(at.getTime()) ? null : at;
}

/**
 * THE single rule check for the 7 Record Outcome rules: is this customer
 * still inside a wait during which NO salesperson call task may exist?
 * Returns { rule, until?, text } or null. Every automatic writer goes
 * through driveRecoveryTask (which applies this), and
 * enforceOutcomeRules() re-checks every open task against it on each
 * sweep, so a task created by any other path is closed too.
 *
 *  1 PTP                  — open until ptpVerificationService's BUSY check
 *  2 Payment Already Made — open until the RE decides the claim
 *  3 Will Confirm         — until the picked date/time (followUpService)
 *  4 No Answer            — until the 2-hour window passes (noAnswerService)
 *  5 Dispute              — NOT a wait: the remainder gets a task at once
 *  6 Unable / Refused     — NOT a wait: its own 2d→3→4→5d cycle
 *  7 Internal Action      — open until the RE approves/rejects it
 *
 * Will Confirm / No Answer are read from the salesperson's LAST recorded
 * outcome in the audit trail (append-only), never only from
 * customer.primaryNextAction — that field can be overwritten (on 22 Oct a
 * pre-guard sweep flipped 45 Will Confirm customers to 'CALL CUSTOMER',
 * which made the wait invisible).
 */
async function outcomeWait(customerId, { customer, tasks, ptps, claims } = {}) {
  customer = customer || (await customerRepository.findById(customerId));
  if (!customer) return null;
  tasks = tasks || (await taskRepository.findByCustomer(customerId));
  ptps = ptps || (await ptpRepository.findByCustomer(customerId));
  claims = claims || (await paymentClaimRepository.findByCustomer(customerId));

  if (ptps.some((p) => p.customerId === customerId && OPEN_PTP_STATUSES.includes(p.status))) {
    return { rule: 'PTP', text: 'a Promise to Pay is open, awaiting the BUSY check on its promised date' };
  }
  if (claims.some((cl) => OPEN_CLAIM_STATUSES.includes(cl.status))) {
    return { rule: 'Payment Already Made', text: 'a "Payment Already Made" claim is awaiting the RE\'s verification' };
  }
  if (tasks.some((t) => t.type === 'financialTeamFollowUp' && OPEN_TASK(t.status))) {
    return { rule: 'Internal Action', text: 'an Internal Action is awaiting the RE\'s decision' };
  }

  const last = await auditRepository.latestOfSource(customerId, 'Record Outcome');
  const now = Date.now();
  if (last && last.type === WILL_CONFIRM_AUDIT_TYPE) {
    const at = parseWillConfirmAt(last.description);
    // Unparseable (older format) → fall back to the parked state itself.
    if ((at && at.getTime() > now) || (!at && FOLLOW_UP_ACTIONS.has(customer.primaryNextAction))) {
      return { rule: 'Will Confirm', until: at, text: `the customer will confirm${at ? ` on ${at.toLocaleString('en-IN', { timeZone: 'Asia/Kolkata' })}` : ''}` };
    }
  }
  if (last && last.type === NO_ANSWER_AUDIT_TYPE) {
    const until = new Date(new Date(last.occurredAt).getTime() + NO_ANSWER_WINDOW_MS);
    const noAnswerTaskOpen = tasks.some((t) => t.source === 'No Answer' && OPEN_TASK(t.status));
    if (until.getTime() > now && !noAnswerTaskOpen) {
      return { rule: 'No Answer', until, text: `the 2-hour No Answer window runs until ${until.toLocaleString('en-IN', { timeZone: 'Asia/Kolkata' })}` };
    }
  }
  return null;
}

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
 * opts: { headline, priority, deadlineHour = 18, deadlineOverride, collectAmount, refreshOnly, resolves }
 * `resolves` names the outcome rule this call is the trigger for (only
 * followUpService passes 'Will Confirm') — see outcomeWait.
 * `collectAmount` overrides the figure to chase; otherwise it's the
 * customer's ACTIONABLE overdue = totalDue − (open PTPs + payment claims
 * with the RE + disputes with the RE), so a fully-promised/claimed
 * account correctly parks. `deadlineOverride` (a Date) beats `deadlineHour`.
 * Every automatically-generated call task is due same-day 6 PM (18:00) —
 * every caller in this codebase passes 18 explicitly; the default here
 * matches for any future caller that omits it.
 */
async function driveRecoveryTask(customerId, opts = {}, conn) {
  const { headline = 'Follow up.', priority = 'Normal', deadlineHour = 18, deadlineOverride, collectAmount, refreshOnly = false, attachmentPath, resolves } = opts;

  const body = async (c) => {
    const customer = await customerRepository.findById(customerId);
    if (!customer) return;

    // Customer has vanished from BUSY's feed (balance cleared / account
    // closed — see customerRepository.upsertFromBusy's deactivation
    // sweep). There's nothing left to chase and no fresh BUSY data will
    // ever update this customer's totalDue again, so close out any open
    // recovery task and stop — never create or retarget one for a
    // customer no one can act on anymore.
    if (customer.busyStillActive === false) {
      const existing = await taskRepository.findByCustomer(customerId, c);
      const openRecoveryTask = existing.find(
        (t) => t.type === 'customerCall' && t.source === RECOVERY_SOURCE && OPEN_TASK(t.status)
      );
      if (openRecoveryTask) {
        // 'completed', not 'closed' — see taskRepository.closeOrphanedTasks'
        // doc comment: the mobile app only recognizes TaskStatus.completed
        // as "done" in almost every screen.
        await taskRepository.update(
          openRecoveryTask.id,
          { status: 'completed', completedAt: new Date(), outcome: 'Auto-closed — customer no longer appears in BUSY.' },
          c
        );
        await auditRepository.record(
          customerId,
          { type: 'RECOVERY_TASK_CLOSED_INACTIVE', description: 'Recovery task closed — customer no longer appears in BUSY.', actor: 'System', source: RECOVERY_SOURCE },
          c
        );
      }
      return;
    }

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
    // An Internal Action is sitting with the RE (financialTeamFollowUp,
    // created by applyOutcome's 'Internal Action'/'Action Required'
    // branch) — like a PTP, it depends entirely on the RE's own decision
    // (internalActionService.approve/reject), not on a timer or the
    // salesperson. No competing call task until that decision happens.
    const openInternalAction = tasks.some((t) => t.type === 'financialTeamFollowUp' && OPEN_TASK(t.status));
    const openJobOwnedCall = openCalls.some((t) => JOB_OWNED_CALL_SOURCES.includes(t.source));
    // A PTP — full OR partial — isn't checked against BUSY until
    // ptpVerificationService's 12:10 IST job runs. Until then, no task
    // (not even for an "uncovered remainder") gets created/retargeted —
    // same reasoning as openPhysicalVisit below: one open promise is the
    // account's active step, not a competing call task.
    const ptps = await ptpRepository.findByCustomer(customerId);
    const openPtp = ptps.some((p) => p.customerId === customerId && OPEN_PTP_STATUSES.includes(p.status));
    const claims = await paymentClaimRepository.findByCustomer(customerId);
    const openClaim = claims.some((cl) => OPEN_CLAIM_STATUSES.includes(cl.status));

    // Never auto-create (or adopt into) the single recovery task for a
    // customer who has never had a first outcome recorded — the
    // salesperson discovers and records their first contact with a new
    // customer themselves (Customer 360 → Record Outcome); the system
    // must not push a task at them before that ever happens.
    // `reasonForAction` stays the empty string it's created with
    // (customerRepository.upsertFromBusy's INSERT default) until the very
    // first real outcome is recorded — customerService.applyOutcome
    // always writes a real, non-empty reason, so an empty one here is a
    // reliable "never touched" signal. Safe to gate every call site: an
    // RE-decision call (dispute resolve, PTP outcome, claim verify) can
    // only ever happen for a customer who already has a dispute/PTP/claim
    // — which itself can only exist because a first outcome was already
    // recorded, so reasonForAction is already non-empty by then.
    if (!openRecovery && !(customer.reasonForAction || '').trim()) {
      return;
    }

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

    // A PTP is open and unverified — the account's active step is waiting
    // on the promised date + the 12:10 IST BUSY check
    // (ptpVerificationService), not another call. This must be checked
    // BEFORE the due<1 branch below: a fully-covering PTP would otherwise
    // park the account as 'Nothing Pending' (implying fully resolved, when
    // it's really just unverified), and a partially-covering one would
    // otherwise retarget the recovery task down to the uncovered
    // remainder — exactly the premature task this guard exists to
    // prevent. Once the PTP resolves (kept/broken/partiallyKept) the next
    // driveRecoveryTask call (from ptpVerificationService itself) re-drives
    // a real task for whatever's still due.
    if (openPtp) {
      if (openRecovery) {
        await close('Paused — a Promise to Pay is open, awaiting the BUSY check on its promised date.');
        await auditRepository.record(
          customerId,
          { type: 'RECOVERY_TASK_PAUSED_PTP', description: 'Recovery call task paused — a Promise to Pay is open and not yet checked against BUSY.', actor: 'System', source: RECOVERY_SOURCE },
          c
        );
      }
      // A customer can end up with an open PTP while still carrying
      // currentRecoveryState: 'Action Required' — e.g. pre-existing stale
      // data from before this guard existed, or any other path that never
      // correctly parked them. The mobile app's "is Record Outcome locked"
      // check (customer_360_screen.dart's `outcomeRecorded`) keys off
      // 'Waiting / Monitoring', so a customer stuck like this wrongly shows
      // Record Outcome as open AND wrongly appears in Today's Recovery
      // Tasks (dashboard_screen.dart's `_todaysRecoveryCustomers` treats
      // anything != 'Waiting / Monitoring' as actionable) despite a real,
      // unresolved PTP sitting right there. Self-heal it here — this
      // function already runs for every 'Action Required' customer on the
      // nightly sweep (recoveryReconcileService.reconcileAll), so this is a
      // standing correction, not a one-time patch.
      if (customer.currentRecoveryState !== 'Waiting / Monitoring') {
        await customerRepository.update(customerId, { currentRecoveryState: 'Waiting / Monitoring' }, c);
        await auditRepository.record(
          customerId,
          { type: 'RECOVERY_STATE_CORRECTED_PTP', description: `Recovery state corrected to Waiting / Monitoring — an open Promise to Pay was found while the account was still marked "${customer.currentRecoveryState}".`, actor: 'System', source: RECOVERY_SOURCE },
          c
        );
      }
      return;
    }

    // An Internal Action is open and sitting with the RE — depends
    // entirely on internalActionService.approve/reject, not a timer, not
    // the salesperson. Same reasoning and same self-healing shape as the
    // openPtp block above: must be checked before due<1 (a fully-covering
    // Internal Action — there's rarely any "covering" here since it's
    // procedural, not a claim on an amount — would otherwise park/retarget
    // prematurely), and corrects a customer stuck in the wrong state the
    // same way.
    if (openInternalAction) {
      if (openRecovery) {
        await close('Paused — an Internal Action is open, awaiting the RE\'s decision.');
        await auditRepository.record(
          customerId,
          { type: 'RECOVERY_TASK_PAUSED_INTERNAL_ACTION', description: 'Recovery call task paused — an Internal Action is open and awaiting the RE\'s decision.', actor: 'System', source: RECOVERY_SOURCE },
          c
        );
      }
      if (customer.currentRecoveryState !== 'Waiting / Monitoring') {
        await customerRepository.update(customerId, { currentRecoveryState: 'Waiting / Monitoring' }, c);
        await auditRepository.record(
          customerId,
          { type: 'RECOVERY_STATE_CORRECTED_INTERNAL_ACTION', description: `Recovery state corrected to Waiting / Monitoring — an open Internal Action was found while the account was still marked "${customer.currentRecoveryState}".`, actor: 'System', source: RECOVERY_SOURCE },
          c
        );
      }
      return;
    }

    // "Payment Already Made" depends entirely on the RE's decision
    // (paymentClaimService.verify/reject flips the claim's status BEFORE it
    // re-drives here, so its own call isn't blocked). Even a partial claim
    // must not spawn a task for the uncovered remainder until then.
    if (openClaim) {
      if (openRecovery) {
        await close('Paused — a payment claim is awaiting the RE\'s verification.');
        await auditRepository.record(
          customerId,
          { type: 'RECOVERY_TASK_PAUSED_CLAIM', description: 'Recovery call task paused — a "Payment Already Made" claim is awaiting the RE\'s verification.', actor: 'System', source: RECOVERY_SOURCE },
          c
        );
      }
      return;
    }

    // Rules 3 + 4 (Will Confirm / No Answer): only the rule's own
    // exact-time job may create the task — followUpService.resolveFollowUp
    // passes `resolves: 'Will Confirm'`; noAnswerService inserts its own.
    // EVERY other caller (the sweep, a bare task completion, an L2/L3
    // missed-deadline nag, an RE decision) is blocked until that time, and
    // any task that already slipped in is closed. See outcomeWait.
    const wait = await outcomeWait(customerId, { customer, tasks, ptps, claims });
    if (wait && (wait.rule === 'Will Confirm' || wait.rule === 'No Answer') && resolves !== wait.rule) {
      if (openRecovery) {
        await close(`Closed — ${wait.text}; the call task is created only then.`);
      }
      // Will Confirm keeps the customer parked so resolveFollowUp (which
      // keys off FOLLOW_UP_ACTIONS) still fires at the promised time.
      const stateWrong =
        wait.rule === 'Will Confirm' &&
        (customer.currentRecoveryState !== 'Waiting / Monitoring' || !FOLLOW_UP_ACTIONS.has(customer.primaryNextAction));
      if (stateWrong) {
        await customerRepository.update(
          customerId,
          { currentRecoveryState: 'Waiting / Monitoring', primaryNextAction: 'Follow-up Scheduled' },
          c
        );
      }
      if (openRecovery || stateWrong) {
        await auditRepository.record(
          customerId,
          {
            type: wait.rule === 'Will Confirm' ? 'RECOVERY_STATE_CORRECTED_WILL_CONFIRM' : 'RECOVERY_TASK_BLOCKED_NO_ANSWER',
            description: `${wait.rule} rule enforced — ${wait.text}${openRecovery ? '; an early call task was closed' : ''}. A call task is created only once that time passes.`,
            actor: 'System',
            source: RECOVERY_SOURCE,
          },
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
      // Only "park" a customer who actually HAD an open recovery task being
      // retired here — never one who simply never had anything actionable
      // in the first place (a brand-new sync, a customer with ₹0 due from
      // day one). Without this guard, a customer nobody has ever touched
      // got silently marked 'Waiting / Monitoring' on every single
      // reconcile/sync pass — with no audit entry — and the mobile app
      // treats that state as "an outcome was recorded" (see
      // customer_360_screen.dart's `outcomeRecorded`), showing a false
      // "Recorded Outcome" card for a customer no salesperson ever acted
      // on. `openRecovery` existing means a task truly was open and is now
      // being resolved — a real state transition worth recording.
      if (
        openRecovery &&
        customer.escalationLevel === 'none' &&
        customer.currentRecoveryState !== 'Waiting / Monitoring' &&
        !tasks.some((t) => ['customerCall', 'physicalVisit'].includes(t.type) && OPEN_TASK(t.status) && t.id !== (openRecovery && openRecovery.id))
      ) {
        // Refresh primaryNextAction/reasonForAction here too — not just
        // currentRecoveryState. Both were last written by whatever outcome
        // originally opened this recovery task (e.g. 'Verification Pending'
        // / 'Payment claimed' from the salesman's "Payment Already Made"),
        // and nothing else ever touches them once that instrument resolves
        // (PTP verified, claim verified/failed, dispute decided, …). Left
        // stale, the customer's "Recorded Outcome" card
        // (customer_360_screen.dart) keeps showing that pre-resolution text
        // forever — e.g. still "Verification Pending" days after the RE
        // actually verified the claim. `headline` is the real resolution
        // message the caller already composed for this exact event (e.g.
        // "Payment of ₹20,000 verified." from paymentClaimService.verify),
        // so reuse it here instead of leaving the stale text behind.
        await customerRepository.update(
          customerId,
          { currentRecoveryState: 'Waiting / Monitoring', primaryNextAction: 'Nothing Pending', reasonForAction: headline },
          c
        );
        await auditRepository.record(
          customerId,
          { type: 'RECOVERY_PARKED_NOTHING_DUE', description: 'Nothing actionable remains — account parked, recovery task retired.', actor: 'System', source: RECOVERY_SOURCE },
          c
        );
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
      // Only reached when !refreshOnly (the refreshOnly+openRecovery bump
      // above already returned) — a genuine event driving this retarget
      // (PTP broken, dispute decided, payment claim decided, …), so the
      // salesperson needs to see it: surface it in their Tasks tab.
      // attachmentPath only included when this specific event carries real
      // evidence — an RE decision with nothing attached shouldn't blank
      // out whatever evidence a previous event already left on this task.
      await taskRepository.update(
        openRecovery.id,
        { reason, priority, deadline, isRoutine: false, ...(attachmentPath ? { attachmentPath } : {}) },
        c
      );
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
          // true only for the routine nightly/reconcile sweep creating a
          // fresh task from scratch with no specific event behind it —
          // false (visible) for every real event creating one.
          isRoutine: refreshOnly,
          // The RE's own evidence (e.g. an Internal Action approve/reject
          // attachment) — carried onto the salesperson's actual task, not
          // just the audit trail, so it shows up in their Task Details.
          attachmentPath: attachmentPath || null,
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

// Salesperson call tasks the enforcer leaves alone: an RE's explicit
// instruction is a human decision, and Customer Refused (rule 6) runs its
// own reopening cycle.
const ENFORCER_EXEMPT_SOURCES = ['RE Instruction', 'Customer Refused'];

/**
 * Safety net for the 7 Record Outcome rules, run after every sweep (daily
 * reconcile + the 2-hourly sweeps): any open salesperson call task on a
 * customer who is still inside a rule's wait (outcomeWait) is closed, with
 * an audit entry and a warning log — whichever code path created it. With
 * driveRecoveryTask enforcing the same rule up front, this should find
 * nothing; a non-zero count in the logs means some writer needs fixing.
 */
async function enforceOutcomeRules() {
  // Customers removed from BUSY keep nothing open — not a task (any type,
  // any owner), not a dispute — even if something was left behind by an
  // older sync or slipped in afterwards.
  const { query } = require('../config/db');
  const leftovers = await query(
    `SELECT c.id FROM customers c WHERE c.busy_still_active = 0 AND (
       EXISTS (SELECT 1 FROM tasks t WHERE t.customer_id = c.id AND t.status NOT IN ('completed', 'closed'))
       OR EXISTS (SELECT 1 FROM disputes d WHERE d.customer_id = c.id AND d.status IN ('Pending Approval', 'Approved', 'Need More Information', 'Awaiting Verification'))
       OR EXISTS (SELECT 1 FROM payment_claims pc WHERE pc.customer_id = c.id AND pc.status IN ('Awaiting Verification', 'Sync Pending')))`
  );
  if (leftovers.length) {
    await customerRepository.closeOutRemovedCustomers(leftovers.map((r) => r.id));
    logger.warn('[outcomeRules] closed leftover tasks/disputes of customers removed from BUSY', { customers: leftovers.length });
  }

  const allTasks = await taskRepository.findAll();
  const candidates = allTasks.filter(
    (t) => t.type === 'customerCall' && OPEN_TASK(t.status) && !ENFORCER_EXEMPT_SOURCES.includes(t.source)
  );
  const byCustomer = new Map();
  for (const t of candidates) {
    if (!byCustomer.has(t.customerId)) byCustomer.set(t.customerId, []);
    byCustomer.get(t.customerId).push(t);
  }
  let closed = 0;
  for (const [customerId, open] of byCustomer) {
    try {
      const customer = await customerRepository.findById(customerId);
      if (!customer) continue;
      const own = open.filter((t) => t.ownerId === customer.assignedSalesmanId);
      if (!own.length) continue;
      const wait = await outcomeWait(customerId, { customer, tasks: allTasks.filter((t) => t.customerId === customerId) });
      if (!wait) continue;
      for (const t of own) {
        await taskRepository.update(t.id, { status: 'completed', completedAt: new Date(), outcome: `Closed — ${wait.text}; no task until then.` });
      }
      await auditRepository.record(customerId, {
        type: 'OUTCOME_RULE_ENFORCED',
        description: `${wait.rule} rule enforced — ${wait.text}. ${own.length} early call task(s) closed.`,
        actor: 'System',
        source: RECOVERY_SOURCE,
      });
      closed += own.length;
      logger.warn('[outcomeRules] closed early task(s) — a writer bypassed the rule', { customerId, rule: wait.rule, sources: own.map((t) => t.source) });
    } catch (err) {
      logger.error('[outcomeRules] enforcement failed for customer', { customerId, message: err.message });
    }
  }
  logger.info(`[outcomeRules] enforcement pass done — ${closed} early task(s) closed, ${leftovers.length} removed customer(s) cleaned up.`);
  return { outcomeRuleTasksClosed: closed, removedCustomersCleaned: leftovers.length };
}

module.exports = { driveRecoveryTask, outcomeWait, enforceOutcomeRules, parseWillConfirmAt, WILL_CONFIRM_AUDIT_TYPE, NO_ANSWER_AUDIT_TYPE, NO_ANSWER_WINDOW_MS, RECOVERY_SOURCE, rupees, atHourLocal };
