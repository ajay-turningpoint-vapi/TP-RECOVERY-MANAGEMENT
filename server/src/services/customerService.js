const { withTransaction } = require('../config/db');
const customerRepository = require('../repositories/customerRepository');
const taskRepository = require('../repositories/taskRepository');
const ptpRepository = require('../repositories/ptpRepository');
const disputeRepository = require('../repositories/disputeRepository');
const paymentClaimRepository = require('../repositories/paymentClaimRepository');
const auditRepository = require('../repositories/auditRepository');
const escalationRepository = require('../repositories/escalationRepository');
const userRepository = require('../repositories/userRepository');
const scoringService = require('./scoringService');
const escalationService = require('./escalationService');
const recoveryReconcileService = require('./recoveryReconcileService');
const { driveRecoveryTask, rupees, atHourLocal, outcomeWait } = require('./recoveryTaskService');
const { scheduleFollowUpDue } = require('../queues/followUpQueue');
const { scheduleNoAnswerDue } = require('../queues/noAnswerQueue');
const { NotFoundError, ForbiddenError, ValidationError } = require('../errors/AppError');
const logger = require('../config/logger');

// Kept in sync with lib/v2/stores/app_store.dart's `noAnswerThreshold`.
// The 3rd consecutive unanswered attempt auto-creates a Physical Visit
// and resets the counter; any non-No-Answer outcome in between resets it
// too (the salesman broke the missed-call streak).
const NO_ANSWER_THRESHOLD = 3;

// Also matches missedDeadlineService.js's VISIT_REASON — same string, two
// files, so any physical-visit task raised for hitting the non-contact
// threshold is counted consistently regardless of which path created it.
const NON_CONTACT_VISIT_REASON = 'Non-response threshold reached';

async function assertVisible(customer, user) {
  // Removed from BUSY = removed from RMS: no detail, history or actions.
  if (!customer || customer.busyStillActive === false) throw new NotFoundError('Customer');
  if (user.role === 'SALESPERSON' && customer.assignedSalesmanId !== user.id) {
    // Not their own portfolio customer — but they may still be a dispute
    // resolution owner for this customer (the RE can assign that to any
    // salesperson), in which case they legitimately need to see/act on
    // this customer from their resolution task.
    const isResolutionOwner = await disputeRepository.isResolutionOwner(customer.id, user.id);
    if (!isResolutionOwner) {
      throw new ForbiddenError('This customer is not in your portfolio');
    }
  }
  return customer;
}

/**
 * Enriches customer rows with the fields that used to be computed
 * client-side (hasValidNextAction, creditHealthScore/Band) — real, derived
 * from actual PTPs/tasks, never a stored/driftable value. Small enough
 * dataset at this scale to fetch the whole ptps/tasks tables per call
 * rather than N+1 per-customer queries.
 */
async function enrichCustomers(customerList) {
  const { query } = require('../config/db');
  const [allPtps, allTasks, allClaims, allDisputes, lastOutcomes] = await Promise.all([
    ptpRepository.findAll(),
    taskRepository.findAll(),
    paymentClaimRepository.findAll(),
    disputeRepository.findAll(),
    // Each customer's latest Record Outcome — one query for the whole list.
    query(
      `SELECT a.customer_id, a.type, a.description, a.occurred_at FROM audit_events a
       JOIN (SELECT customer_id, MAX(occurred_at) m FROM audit_events WHERE source = 'Record Outcome' GROUP BY customer_id) x
         ON x.customer_id = a.customer_id AND x.m = a.occurred_at
       WHERE a.source = 'Record Outcome'`
    ),
  ]);
  const ptpsByCustomer = scoringService.groupBy(allPtps, (p) => p.customerId);
  const tasksByCustomer = scoringService.groupBy(allTasks, (t) => t.customerId);
  const { openClaimIds, openDisputeIds } = scoringService.openClaimAndDisputeIds(allClaims, allDisputes);
  const lastOutcomeBy = new Map(lastOutcomes.map((r) => [r.customer_id, { type: r.type, description: r.description, occurredAt: r.occurred_at }]));
  // A recorded outcome still waiting on its own trigger IS the next action
  // (shared rule: scoringService.waitingOnOutcome).
  const waitingOnOutcome = (id) => scoringService.waitingOnOutcome(id, { lastOutcome: lastOutcomeBy.get(id), openClaimIds, openDisputeIds });
  return customerList.map((c) => {
    const cPtps = ptpsByCustomer.get(c.id) || [];
    const cTasks = tasksByCustomer.get(c.id) || [];
    const creditHealthComponents = scoringService.computeCreditHealthComponents(c, cPtps);
    const creditHealthScore = creditHealthComponents ? creditHealthComponents.total : null;
    return {
      ...c,
      hasValidNextAction: scoringService.hasValidNextAction(c, cPtps, cTasks) || waitingOnOutcome(c.id),
      creditHealthScore,
      creditHealthBand: scoringService.creditHealthBand(creditHealthScore),
      creditHealthComponents,
    };
  });
}

/**
 * A SALESPERSON sees their own portfolio (real BUSY-sourced customers now
 * that the daily sync upserts straight into `customers` — see
 * customerRepository.upsertFromBusy), plus any customer whose dispute they
 * were assigned as resolution owner — the RE can assign that to any
 * salesperson, not just the customer's own, and that salesperson still
 * needs to see the customer's real name (not just the id) from their task.
 * RECOVERY_EXECUTIVE/MANAGEMENT see the whole company.
 */
async function listForUser(user) {
  let raw;
  if (user.role === 'SALESPERSON') {
    const [own, resolutionOwnerCustomerIds] = await Promise.all([
      customerRepository.findBySalesman(user.id),
      disputeRepository.findCustomerIdsByResolutionOwner(user.id),
    ]);
    const ownIds = new Set(own.map((c) => c.id));
    const extraIds = resolutionOwnerCustomerIds.filter((id) => !ownIds.has(id));
    const extra = extraIds.length ? await customerRepository.findByIds(extraIds) : [];
    raw = [...own, ...extra];
  } else {
    raw = await customerRepository.findAll();
  }
  const enriched = await enrichCustomers(raw);
  return enriched.sort(scoringService.compareByRecoveryPriority);
}

/** The one customer this user should work on next — same ordering as `listForUser`, first actionable row. */
async function getNext(user) {
  const list = await listForUser(user);
  const actionable = list.filter((c) => c.currentRecoveryState !== 'Waiting / Monitoring');
  return actionable[0] || null;
}

async function getDetail(id, user) {
  const customer = await customerRepository.findById(id);
  await assertVisible(customer, user);
  const [invoices, history, [enriched], coverage, block] = await Promise.all([
    customerRepository.findInvoices(id),
    auditRepository.listForCustomer(id),
    enrichCustomers([customer]),
    recoveryReconcileService.coverageFor(id),
    reTaskBlock(id),
  ]);
  // coveredAmount = overdue currently under a PTP / dispute / payment claim.
  // actionableAmount = what the salesperson should actually be chasing now.
  return {
    ...enriched,
    coveredAmount: coverage.covered,
    actionableAmount: coverage.actionable,
    invoices,
    auditHistory: history,
    // The Record Outcome rule currently holding this customer (open PTP,
    // Will Confirm time, No Answer window, claim / Internal Action with
    // the RE) — the app disables the RE's CREATE TASK while it's set.
    outcomeWait: block,
  };
}

/**
 * Why the RE can't add a task to this customer right now, or null: a
 * Record Outcome rule still waiting (outcomeWait), or a dispute waiting
 * for the RE's own decision — that decision is what creates the
 * salesman's next task (UNIQUE ARTS, 24 Oct: ₹30,058 dispute pending
 * approval for 7 days, Create Task still offered).
 */
const RE_DECISION_DISPUTE_STATUSES = ['Pending Approval', 'Need More Information', 'Awaiting Verification'];
async function reTaskBlock(customerId) {
  const wait = await outcomeWait(customerId);
  if (wait) return { rule: wait.rule, text: reTaskBlockedMessage(wait) };
  const disputes = (await disputeRepository.findOpenByCustomerIds([customerId])).filter((d) => RE_DECISION_DISPUTE_STATUSES.includes(d.status));
  if (disputes.length) {
    const d = disputes[0];
    return {
      rule: 'Dispute',
      text: `Dispute: ${rupees(d.amount)} dispute is waiting for your decision (${d.status}). Decide it first — the system then creates the salesman's task.`,
    };
  }
  return null;
}

// Rules whose own trigger creates the salesman's task automatically.
const AUTO_TASK_RULES = new Set(['PTP', 'Will Confirm', 'No Answer']);

/** Plain sentence for why the RE can't add a task right now. */
function reTaskBlockedMessage(wait) {
  return AUTO_TASK_RULES.has(wait.rule)
    ? `${wait.rule}: ${wait.text}. The system creates the salesman's task automatically at that time.`
    : `${wait.rule}: ${wait.text}. Decide it first — the system then creates the salesman's task.`;
}

const AUDIT_PAGE_DEFAULT_LIMIT = 20;
const AUDIT_PAGE_MAX_LIMIT = 100;

/**
 * Server-side keyset pagination for a customer's audit history — a
 * long-tenured customer can accumulate hundreds of events (every outcome,
 * RE decision, and system-generated task writes one), and `getDetail`'s
 * `auditHistory` stays the full unbounded list (other consumers — activity
 * counts, task detail screens — depend on that), so this is a separate,
 * dedicated endpoint the customer 360 screen's history tab pages through
 * instead of downloading everything up front.
 *
 * `cursor` is the opaque `"<epochMillis>_<id>"` of the last row the caller
 * already has (from a previous page's `nextCursor`); omit it for page one.
 */
async function getAuditHistoryPage(id, user, { cursor, limit, view } = {}) {
  const customer = await customerRepository.findById(id);
  await assertVisible(customer, user);

  const pageSize = Math.min(Math.max(Number(limit) || AUDIT_PAGE_DEFAULT_LIMIT, 1), AUDIT_PAGE_MAX_LIMIT);
  let after = null;
  if (cursor) {
    const [rawTime, rawId] = String(cursor).split('_');
    const occurredAt = new Date(Number(rawTime));
    if (!rawId || Number.isNaN(occurredAt.getTime())) {
      throw new ValidationError('Invalid cursor');
    }
    after = { occurredAt, id: rawId };
  }

  // Simple history by default; ?view=all returns every event.
  const rows = await auditRepository.listForCustomerPage(id, { after, limit: pageSize, simple: view !== 'all' });
  const hasMore = rows.length > pageSize;
  const items = hasMore ? rows.slice(0, pageSize) : rows;
  const last = items[items.length - 1];
  const nextCursor = hasMore && last ? `${new Date(last.occurredAt).getTime()}_${last.id}` : null;

  return { items, nextCursor };
}

/**
 * Record what happened on a call/visit — the single most important write
 * path in the app. Always: closes out every other open task for this
 * customer first (one outcome record per customer, mirrors the same rule
 * used for RE/Manager intervention), moves the customer to
 * "Waiting / Monitoring", logs the audit entry, then branches on the
 * outcome to create whatever real follow-up artifact it implies (a task,
 * a PTP, a dispute, or a payment claim) — nothing is ever just a status
 * label with no real consequence.
 */
/**
 * The actual write side of recording an outcome — factored out of
 * recordOutcome so the same-day self-service "replace a recorded No
 * Answer" path (`replacingNoAnswer: true` on the normal record-outcome
 * call — see app_store.dart's `recordOutcome`) can apply the exact same
 * logic as a fresh outcome. `user` is whoever the outcome is being
 * recorded for — always the acting salesperson.
 */
async function applyOutcome(conn, customer, user, { nextAction, reason, details, ptpAmountValue, advanceAmountValue, ptpDate, ptpMode, attachmentPath, replacingNoAnswer, followUpAt }) {
  const customerId = customer.id;

  // Guard against being hit once the customer has moved on to a different
  // recorded outcome (a stale client, a replay).
  if (replacingNoAnswer && !(customer.primaryNextAction === 'Call Customer' && customer.reasonForAction === 'No Answer')) {
    throw new ValidationError('No recorded No Answer outcome to replace for this customer');
  }

  // A Physical Visit is a real in-person visit — while one is open, Record
  // Outcome is locked for this customer, full stop, no exceptions (not
  // even another No Answer): the salesperson must go close the visit out
  // WITH a photo (taskService.completeTask) before anything else can be
  // recorded here. Checked before the supersede below so a missing photo
  // blocks the whole write. The one exception is 'Physical Visit Requested'
  // itself — that outcome IS the salesperson declining to do the visit
  // personally and handing it to the RE instead (see the branch below), so
  // no photo is expected from them for it.
  if (user.role === 'SALESPERSON' && !attachmentPath && nextAction !== 'Physical Visit Requested') {
    const openVisit = (await taskRepository.findByCustomer(customerId, conn)).find(
      (t) => t.type === 'physicalVisit' && t.ownerId === user.id && !['completed', 'closed', 'cancelled'].includes(t.status)
    );
    if (openVisit) {
      throw new ValidationError('A photo from the Physical Visit is required before you can record any other outcome for this customer.');
    }
  }

  await taskRepository.supersedeOpenTasks(customerId, `Resolved via outcome: ${nextAction}`, conn);

  if (replacingNoAnswer) {
    // The salesman is correcting a misrecorded No Answer, not adding a
    // second outcome on top of it — erase the old "No Answer Logged"
    // audit row so History shows only the real outcome in its place.
    await auditRepository.deleteLatestOfType(customerId, 'No Answer Logged', conn);
  }
  // The attempt the replaced No Answer counted didn't really happen —
  // roll the counter back one before the branch below (possibly)
  // re-increments it, so replacing No Answer with another genuine No
  // Answer still counts correctly toward NO_ANSWER_THRESHOLD.
  const baselineNoAnswerAttempts = replacingNoAnswer ? Math.max(0, customer.noAnswerAttempts - 1) : customer.noAnswerAttempts;

  // A No Answer is a non-contact — it stays actionable (the customer stays
  // in Today's Recovery) and the salesman records the real outcome once
  // the customer calls back via "New Record Outcome". Every resolving
  // outcome still parks the account. "Will Confirm / Follow-up" now parks
  // too (see below) — it's genuinely quiet, not actionable, until the
  // promised confirm time actually passes (followUpQueue.scheduleFollowUpDue).
  const isNoAnswerOutcome = nextAction === 'Call Customer' && reason === 'No Answer';

  const nonResolving = isNoAnswerOutcome;

  await customerRepository.update(
    customerId,
    {
      primaryNextAction: nextAction,
      reasonForAction: reason,
      currentRecoveryState: nonResolving ? 'Action Required' : 'Waiting / Monitoring',
      hasValidNextAction: true,
      // A No Answer keeps its running attempt count (the No Answer branch
      // below writes the final value). ANY other outcome means the
      // salesman actually reached the customer or moved the account on —
      // the missed-call streak is broken, so the counter resets to zero.
      ...(isNoAnswerOutcome ? {} : { noAnswerAttempts: 0 }),
    },
    conn
  );

  await auditRepository.record(
    customerId,
    { type: outcomeAuditLabel(nextAction, reason), description: `${reason} — ${details}`, actor: user.fullName, source: 'Record Outcome', attachmentPath },
    conn
  );

  if (nextAction === 'PTP Scheduled' && ptpAmountValue && ptpDate && ptpMode) {
    // Snapshot the customer's outstanding position now, so the automated
    // PTP maturity job can later diff it against the (daily-BUSY-synced)
    // balance to decide kept vs broken. Same pattern as the dispute branch
    // below capturing customer.totalDue.
    await ptpRepository.insert(
      {
        customerId,
        amountPromised: ptpAmountValue,
        promiseDate: ptpDate,
        paymentMode: ptpMode,
        status: 'scheduled',
        totalDueAtPromise: customer.totalDue,
        totalOutstandingAtPromise: customer.totalOutstanding,
        advanceAmount: advanceAmountValue || null,
      },
      conn
    );
  } else if (nextAction === 'Internal Action' || nextAction === 'Action Required') {
    const reOwner = await resolveDefaultREOwner();
    await taskRepository.insert(
      { type: 'financialTeamFollowUp', customerId, ownerId: reOwner.id, deadline: addHours(new Date(), 4), priority: 'High', reason: details, source: 'Record Outcome', attachmentPath },
      conn
    );
  } else if (nextAction === 'Physical Visit Requested') {
    // Two salesman-side triggers share this one branch: the Internal
    // Action form's "Physical Visit" dependency (outcome_forms.dart's
    // InternalActionForm), and the 3rd-No-Answer physicalVisit task's own
    // "Request Physical Visit" notes sheet (task_details_screen_v3.dart) —
    // the salesman declining to do the visit personally and handing it to
    // the RE instead. Either way this routes to a real `physicalVisit`
    // task so it inherits taskService.completeTask's photo-required
    // closure (extended there to also require notes when an RE, not the
    // owning salesperson, is the one completing it).
    const reOwner = await resolveDefaultREOwner();
    await taskRepository.insert(
      { type: 'physicalVisit', customerId, ownerId: reOwner.id, deadline: addHours(new Date(), 4), priority: 'High', reason: details, source: 'Record Outcome' },
      conn
    );
  } else if (nextAction === 'Follow-up' || nextAction === 'Follow-up Scheduled') {
    // No task here, deliberately — a "Will Confirm" is a promise about a
    // future TIME, not something an RE/BUSY needs to verify, but it still
    // must stay fully quiet (no task, Record Outcome locked) until that
    // time genuinely passes. recordOutcome schedules a one-off delayed job
    // (followUpQueue.scheduleFollowUpDue) for exactly `followUpAt` after
    // this transaction commits — that job is the only thing that creates
    // the call task and re-opens Record Outcome.
  } else if (reason === 'Customer Refused') {
    // A refusal gets ONE recurring call task on a growing cadence — 2 days,
    // then 3, then 4, then every 5 days forever after — via
    // missedDeadlineService.sweepRefusedCycle, not the same-day-6PM
    // default every other auto-generated task uses. Reopening never stops
    // on its own; it only stops when the salesperson records something
    // new here (supersedeOpenTasks above already closed the prior one) or
    // when the RE resolves the L2 escalation this always raises
    // (maybeEscalateCustomerRefused, below) — escalationService.resolve
    // closes this task and hands back a single ordinary Recovery task
    // instead.
    const refusedDeadline = followUpAt ? new Date(followUpAt) : addDays(new Date(), 2);
    await taskRepository.insert(
      {
        type: 'customerCall',
        customerId,
        ownerId: user.id,
        deadline: refusedDeadline,
        priority: 'Normal',
        reason: `Customer refused to commit — call again. ${details || ''}`.trim(),
        source: 'Customer Refused',
      },
      conn
    );
    // A deliberate re-record of Customer Refused (not an automatic sweep
    // reopen) is a fresh refusal — reset the growing cadence to stage 1.
    await customerRepository.update(customerId, { refusedReopenCount: 0 }, conn);
  } else if (reason === 'Dispute Raised') {
    const amountMatch = /Amt:\s*₹?\s*([\d,.]+)/.exec(details);
    const reasonMatch = /Reason:\s*(.*?),\s*Amt:/.exec(details);
    const amount = amountMatch ? Number(amountMatch[1].replace(/,/g, '')) : 0;
    await disputeRepository.insert(
      { customerId, amount, totalDueAtRaise: customer.totalDue, reason: reasonMatch ? reasonMatch[1].trim() : details, status: 'Pending Approval', priority: amount >= 100000 ? 'High' : amount >= 30000 ? 'Medium' : 'Low', attachmentPath },
      conn
    );
  } else if (nextAction === 'Verification Pending') {
    const amountMatch = /₹?\s*([\d,.]+)/.exec(details);
    const amount = amountMatch ? Number(amountMatch[1].replace(/,/g, '')) : 0;
    // The salesperson's own reference/UPI/UTR note, when they gave one —
    // sent from the client as "Amount: ₹X Ref: <note>". No canned filler
    // when they left it blank — null just means the RE screen shows
    // nothing beyond the amount and the salesman (already recorded
    // separately as the claim's raiser), instead of a fabricated line.
    const refMatch = /Ref:\s*(.+)$/s.exec(details);
    const reference = refMatch ? refMatch[1].trim() : null;
    // One payment is claimed once. A claim for the same amount in the last
    // 7 days that is still waiting or already verified is that same payment
    // (JYOTSNA DHANSUKH VORA, 30 Oct: ₹8,00,000 claimed on 29 and 30 Oct,
    // both verified, so Total Collected counted it twice).
    const sameClaim = (await paymentClaimRepository.findByCustomer(customerId, conn)).find(
      (c) =>
        ['Awaiting Verification', 'Sync Pending', 'Verified'].includes(c.status) &&
        Math.abs(c.amount - amount) < 1 &&
        Date.now() - new Date(c.createdAt || c.claimDate).getTime() < 7 * 24 * 60 * 60 * 1000
    );
    if (sameClaim) {
      const on = new Date(sameClaim.createdAt || sameClaim.claimDate).toLocaleDateString('en-IN', { day: '2-digit', month: 'short', timeZone: 'Asia/Kolkata' });
      const state = sameClaim.status === 'Verified' ? 'and the RE has already verified it' : 'and it is waiting for the RE';
      throw new ValidationError(`This ₹${Math.round(amount).toLocaleString('en-IN')} payment was already claimed on ${on} ${state}. Don't claim the same payment twice.`);
    }
    await paymentClaimRepository.insert({ customerId, amount, claimDate: new Date(), reference, status: 'Awaiting Verification', attachmentPath }, conn);
  } else if (nextAction === 'Call Customer' && reason === 'No Answer') {
    // A No Answer's next callback must not exist as a task until the
    // 2-hour window genuinely passes — same "nothing until the trigger"
    // rule as PTP/Payment-Already-Made/Will-Confirm/Internal-Action.
    // Deliberately its own faster cadence (2h, not the same-day-6PM
    // default every other auto-generated call task uses) — handled by
    // noAnswerQueue.scheduleNoAnswerDue, scheduled post-commit by
    // recordOutcome (see the `pendingNoAnswerJob` returned below; BullMQ
    // scheduling must happen after the transaction commits, same as
    // Follow-up's scheduleFollowUpDue). On the NO_ANSWER_THRESHOLD (3rd)
    // unanswered attempt, stop nagging by phone: raise a real Physical
    // Visit instead, due tomorrow 6 PM, immediately (not deferred — this
    // is the escalation OUTCOME itself, not a routine callback, and must
    // be visible right away so the salesperson knows a visit is now
    // required) — Record Outcome for this customer is then locked (see
    // assertVisible's sibling check in applyOutcome above) until that
    // visit is completed WITH a photo. The counter resets so a fresh
    // cycle starts once the visit is done. If this is the SECOND such
    // cycle for this customer (a visit was already raised once before),
    // don't raise a second one — instead escalate straight to L2 (see the
    // returned `nonContactEscalate` flag, handled by recordOutcome
    // post-commit) and let the salesperson keep working the same
    // 2-hourly No Answer cycle under RE supervision — but still only via
    // the deferred callback, not an immediate task.
    const attempts = baselineNoAnswerAttempts + 1;
    const open = (await taskRepository.findByCustomer(customerId, conn)).filter(
      (t) => t.source === 'No Answer' && !['completed', 'closed', 'cancelled'].includes(t.status)
    );
    // Always close out whatever No-Answer task was open — nothing stays
    // visible during the silent wait; the deferred job (scheduled
    // post-commit) creates a fresh one once the window genuinely passes.
    for (const t of open) {
      await taskRepository.update(
        t.id,
        { status: 'completed', completedAt: new Date(), outcome: 'Superseded — next No Answer callback scheduled.' },
        conn
      );
    }

    if (attempts >= NO_ANSWER_THRESHOLD) {
      const priorVisitCycles = (await taskRepository.findByCustomer(customerId, conn)).filter(
        (t) => t.type === 'physicalVisit' && t.reason === NON_CONTACT_VISIT_REASON
      ).length;

      await customerRepository.update(customerId, { noAnswerAttempts: 0 }, conn);

      if (priorVisitCycles === 0) {
        await taskRepository.insert(
          {
            type: 'physicalVisit',
            customerId,
            ownerId: user.id,
            deadline: atHourLocal(18, addDays(new Date(), 1)),
            priority: 'High',
            reason: NON_CONTACT_VISIT_REASON,
            source: 'No Answer',
          },
          conn
        );
        await auditRepository.record(
          customerId,
          {
            type: 'NO_ANSWER_PHYSICAL_VISIT',
            description: `${NO_ANSWER_THRESHOLD} unanswered attempts in a row — a Physical Visit task was auto-created (due tomorrow 6 PM). Record Outcome is locked until it's completed with a photo.`,
            actor: 'System',
            source: 'No Answer',
          },
          conn
        );
      } else {
        // Second cycle: no second visit — straight to L2, salesperson
        // keeps calling on the normal 2-hourly cycle, still deferred.
        return { nonContactEscalate: true, pendingNoAnswerJob: { attemptNumber: 0, dueAt: addHours(new Date(), 2) } };
      }
    } else {
      await customerRepository.update(customerId, { noAnswerAttempts: attempts }, conn);
      return { nonContactEscalate: false, pendingNoAnswerJob: { attemptNumber: attempts, dueAt: addHours(new Date(), 2) } };
    }
  }
  return { nonContactEscalate: false };
}

/**
 * "Unable / Refused" doesn't hand the customer off to the RE — the
 * salesperson keeps their own follow-up (recordOutcome drives the single
 * recovery call task on a self-renewing 2-day cadence) — but it does
 * escalate straight to L2 (RE Supervision) so the
 * RE has real visibility and can step in if refusals continue. Same
 * system-raised pattern as ptpService.evaluateBrokenPtpEscalation —
 * called after the outcome's own transaction has committed, not nested
 * inside it (escalationService.raise runs its own transaction). Guarded
 * on "no open case yet" (not a severity/count check like the broken-PTP
 * one) since a salesperson may record this outcome many times while
 * still working the account under supervision — that must not pile up a
 * fresh L2 case on every retry.
 */
async function maybeEscalateCustomerRefused(customerId, user, { reason, details }) {
  if (reason !== 'Customer Refused') return;
  const alreadyOpen = await escalationRepository.findOpenByCustomer(customerId);
  if (alreadyOpen.length > 0) return;
  const customer = await customerRepository.findById(customerId);
  if (!customer) return;
  await escalationService.raise(customerId, user, {
    level: 'L2',
    reason: `Customer refused to commit: ${details}`,
    plan: 'Salesperson continues follow-up under RE supervision.',
    ownerId: customer.assignedSalesmanId,
    deadline: addDays(new Date(), 3),
    moneyAtRisk: customer.totalDue,
    cause: 'CustomerRefused',
  });
}

/**
 * Non-contact loop floor. The FIRST time the customer hits
 * NO_ANSWER_THRESHOLD unanswered attempts, applyOutcome raises a real
 * Physical Visit task and resets the counter. The SECOND time it happens
 * (a visit was already raised once, and 3 more unanswered attempts pass
 * with the account back on the phone-call cycle), the customer is
 * genuinely unreachable — applyOutcome doesn't raise a second visit; it
 * signals here (`nonContactEscalate`, set precisely on that 2nd threshold
 * hit, never on the 1st or on ordinary later No Answer calls) so this
 * escalates straight to L2 instead, with the real attempt history as the
 * reason. The salesperson keeps working the same 2-hourly No Answer cycle
 * under RE supervision until a real outcome is recorded. Post-commit and
 * best-effort — same pattern as maybeEscalateCustomerRefused.
 */
async function maybeEscalateNonContact(customerId, user, nonContactEscalate) {
  if (!nonContactEscalate) return;
  const customer = await customerRepository.findById(customerId);
  if (!customer) return;
  // Only raise the floor once — never downgrade a customer already at L2+.
  if (!['none', 'L1'].includes(customer.escalationLevel)) return;

  const alreadyOpen = await escalationRepository.findOpenByCustomer(customerId);
  if (alreadyOpen.length > 0) return;

  await escalationService.raise(customerId, user, {
    level: 'L2',
    reason:
      `Customer unreachable — a second full non-response cycle ` +
      `(${NO_ANSWER_THRESHOLD}+ unanswered call attempts, a Physical Visit already raised once with no contact made, ` +
      `then ${NO_ANSWER_THRESHOLD}+ more unanswered attempts since).`,
    plan:
      'Salesperson continues field follow-up under RE supervision. RE to review the ' +
      'contact numbers on file and pursue alternate channels (GST address, references, site visit).',
    ownerId: customer.assignedSalesmanId,
    deadline: addDays(new Date(), 3),
    moneyAtRisk: customer.totalDue,
    cause: 'NonContact',
  });
}

async function recordOutcome(customerId, user, body) {
  let outcomeResult;
  await withTransaction(async (conn) => {
    const customer = await customerRepository.findById(customerId);
    await assertVisible(customer, user);
    outcomeResult = await applyOutcome(conn, customer, user, body);
  });

  await maybeEscalateCustomerRefused(customerId, user, body);
  await maybeEscalateNonContact(customerId, user, outcomeResult && outcomeResult.nonContactEscalate);

  // Retarget the salesperson's single recovery task to whatever slice of
  // the overdue is NOT under a dispute. These outcomes are deliberately
  // excluded — a fresh PTP, a fresh "Payment Already Made" claim, a fresh
  // "Will Confirm", a fresh Physical Visit request, and a fresh Internal
  // Action — and must NOT immediately un-park the customer or reopen a
  // task for the uncovered remainder. All of them stay fully quiet
  // (task-wise AND Record Outcome stays locked) until a real
  // decision/trigger resolves them: ptpVerificationService.finalizeDuePtps
  // for a PTP (kept/partiallyKept/broken against BUSY), paymentClaimService
  // .verify for a claim (RE confirms or rejects it), followUpQueue's
  // scheduled job for a Will Confirm (the promised callback TIME actually
  // passing), taskService.completeTask/rejectVisit for a Physical Visit
  // (the RE actually closes it out), internalActionService.approve/reject
  // for an Internal Action (the RE actually decides it — see
  // recoveryTaskService.driveRecoveryTask's matching `openInternalAction`
  // pause, which is what actually keeps the task away; this exclusion is
  // about the customer's own STATE not flipping back and wrongly
  // re-unlocking Record Outcome). reconcileState would otherwise un-park
  // the uncovered slice right away since it only checks whether
  // `actionable > 0` — none of these task types are counted as "covering"
  // the balance in recoveryReconcileService.computeCoverage, unlike a
  // PTP/dispute/claim — regardless of any of these being resolved yet, so
  // skip it specifically for these outcomes. Every other outcome (dispute,
  // refusal, ...) keeps this call exactly as before.
  if (!['PTP Scheduled', 'Verification Pending', 'Follow-up', 'Follow-up Scheduled', 'Physical Visit Requested', 'Internal Action', 'Action Required'].includes(body.nextAction)) {
    await recoveryReconcileService.reconcileState(customerId, { trigger: 'record.outcome' });
  }

  // Only re-point the salesperson's task immediately when the outcome is
  // something the salesperson still owns outright (a straight refusal —
  // no PTP, no RE dependency). Anything that now depends on verification
  // (a fresh PTP) or on the RE (a dispute, a payment claim, an internal
  // action) must NOT get a new/reopened task here — the task stays quiet
  // until the system verifies the PTP (ptpVerificationService.
  // finalizeDuePtps) or the RE actually decides (paymentClaimService /
  // disputeService / internalActionService), each of which already
  // re-drives the recovery task on its own decision path.
  {
    // Customer Refused's task (honoring followUpAt if the salesperson
    // picked one) is created in applyOutcome, in-transaction, not here.
    const { nextAction, reason, details, followUpAt } = body;
    if (reason === 'Dispute Raised') {
      // Raising a dispute is itself an instrument that covers its amount
      // (recoveryReconcileService.coverageFor already counts 'Pending
      // Approval' disputes) — retarget the ONE recovery task down to the
      // remainder right now instead of waiting for the nightly sweep, so a
      // salesperson who raises a second dispute (or gets a refusal) on the
      // rest of the balance is always working the correct number. No
      // `collectAmount` override — driveRecoveryTask pulls the fresh
      // actionable figure itself, so it's correct however many other
      // disputes/PTPs/claims are already open on this customer.
      const amountMatch = /Amt:\s*₹?\s*([\d,.]+)/.exec(details || '');
      const amount = amountMatch ? Number(amountMatch[1].replace(/,/g, '')) : 0;
      await driveRecoveryTask(customerId, {
        headline: `Dispute of ${rupees(amount)} raised — RE reviewing.`,
        priority: 'Normal',
        deadlineHour: 18,
      });
    } else if (nextAction === 'Follow-up' || nextAction === 'Follow-up Scheduled') {
      // Schedule the one-off job that fires at exactly the promised confirm
      // time — it (not this call) creates the call task and re-opens
      // Record Outcome. No task/retarget happens here; see the applyOutcome
      // branch and reconcileState skip above.
      // followUpAt is the salesperson's own picked confirm time — honor it.
      // The fallback (no date picked) is the system default: same-day 6PM.
      // The salesman's optional note ("remind after 2 days for ₹20,000")
      // is the last "Notes:" segment of details (customer_360_screen.dart's
      // Will Confirm call site) — carried into the task created at that time.
      const noteMatch = /Notes:\s*([\s\S]+)$/.exec(details || '');
      await scheduleFollowUpDue({
        customerId,
        ownerId: user.id,
        dueAt: followUpAt || atHourLocal(18),
        note: noteMatch ? noteMatch[1].trim() : null,
      });
    } else if (nextAction === 'Call Customer' && reason === 'No Answer' && outcomeResult && outcomeResult.pendingNoAnswerJob) {
      // Same reasoning as Follow-up above — schedule the one-off job that
      // fires once the 2-hour (or post-escalation) callback window
      // genuinely passes; it (not this call) creates the No-Answer call
      // task. See applyOutcome's No Answer branch, which closes any prior
      // open task but never creates the next one inline.
      await scheduleNoAnswerDue({
        customerId,
        ownerId: user.id,
        attemptNumber: outcomeResult.pendingNoAnswerJob.attemptNumber,
        dueAt: outcomeResult.pendingNoAnswerJob.dueAt,
      });
    }
  }

  // The salesman just acted — the RE's "missed the deadline, call them"
  // follow-up for this customer is no longer needed. Lazy require: the
  // missed-deadline service imports services that import this one.
  try {
    await require('./missedDeadlineService').closeStaleMissedDeadlineTasks({ customerId });
  } catch (err) {
    logger.warn('[recordOutcome] RE follow-up cleanup failed', { customerId, message: err.message });
  }

  // Read back after commit — reading inside the transaction via the pool's
  // own connection could see stale (pre-commit) data under the default
  // isolation level.
  return getDetail(customerId, user);
}

async function takeControl(customerId, user) {
  const customer = await customerRepository.findById(customerId);
  if (!customer) throw new NotFoundError('Customer');

  await withTransaction(async (conn) => {
    await taskRepository.supersedeOpenTasks(customerId, 'Superseded — RE took direct control of this account', conn);
    await customerRepository.update(customerId, { currentRecoveryState: 'RE Control', primaryNextAction: 'RE INTERVENTION' }, conn);
    await auditRepository.record(
      customerId,
      {
        type: 'RE_TAKEN_CONTROL',
        description: `${user.fullName} has taken direct RE Supervision control of this account — the salesperson's primary next action is superseded and the RE now owns the recovery approach until control is released.`,
        actor: user.fullName,
        previousState: customer.currentRecoveryState,
        newState: 'RE Control',
        source: 'Customer 360',
      },
      conn
    );
  });
  return getDetail(customerId, user);
}

async function releaseControl(customerId, user) {
  const customer = await customerRepository.findById(customerId);
  if (!customer) throw new NotFoundError('Customer');

  await customerRepository.update(customerId, { currentRecoveryState: 'Action Required', primaryNextAction: 'CALL CUSTOMER' });
  await auditRepository.record(customerId, {
    type: 'RE_RELEASED_CONTROL',
    description: `${user.fullName} has released RE Supervision control — recovery ownership returns to the assigned salesperson (${customer.assignedSalesmanId}), who must now determine the next action.`,
    actor: user.fullName,
    previousState: 'RE Control',
    newState: 'Action Required',
    source: 'Customer 360',
  });
  return getDetail(customerId, user);
}

async function reassignCustomer(customerId, user, { toSalesmanId, reason }) {
  const customer = await customerRepository.findById(customerId);
  if (!customer) throw new NotFoundError('Customer');
  const fromSalesmanId = customer.assignedSalesmanId;

  await customerRepository.update(customerId, { assignedSalesmanId: toSalesmanId });
  await auditRepository.record(customerId, {
    type: 'RE_CHANGED_OWNER',
    description: `${user.fullName} reassigned ownership of this account from ${fromSalesmanId} to ${toSalesmanId}. Reason given: "${reason}". Audit history is never rewritten — ${toSalesmanId} now sees this customer's complete company history, not just activity from today.`,
    actor: user.fullName,
    previousState: fromSalesmanId,
    newState: toSalesmanId,
    source: 'Customer 360',
  });
  return getDetail(customerId, user);
}

async function assignManagementInstruction(customerId, user, { salesmanId, desc, deadline, priority = 'Critical', taskType = 'managementInstruction', note = null, attachmentPath = null }) {
  const customer = await customerRepository.findById(customerId);
  if (!customer) throw new NotFoundError('Customer');

  // The salesman's recorded outcome is still waiting on its own trigger
  // (Record Outcome rules) — the system creates the next task then; the RE
  // must not add one in between. Managers' instructions are not blocked.
  if (user.role === 'RECOVERY_EXECUTIVE') {
    const block = await reTaskBlock(customerId);
    if (block) throw new ValidationError(`Can't create a task now — ${block.text}`);
    // Same rule as the app's "TASK ALREADY EXISTS": one open task per
    // customer is enough — the RE works that one instead of stacking more.
    const openTask = (await taskRepository.findByCustomer(customerId)).find((t) => !['completed', 'closed', 'cancelled'].includes(t.status));
    if (openTask) throw new ValidationError('Can\'t create a task now — a task is already open for this customer. Work that one first.');
  }

  // A plain 'customerCall'/'physicalVisit' task is routine follow-up work,
  // not a directive overriding the salesperson's judgment — only the real
  // Management Instruction supersedes whatever else is open on the account.
  const isInstruction = taskType === 'managementInstruction';
  const taskLabel = taskType === 'customerCall' ? 'Call Customer' : taskType === 'physicalVisit' ? 'Physical Visit' : 'Management Instruction';

  await withTransaction(async (conn) => {
    if (isInstruction) {
      await taskRepository.supersedeOpenTasks(customerId, 'Superseded — replaced by RE/Manager Management Instruction', conn);
    }
    await taskRepository.insert({ type: taskType, customerId, ownerId: salesmanId, deadline, priority, reason: desc, source: 'RE Instruction', note, attachmentPath }, conn);
    await auditRepository.record(
      customerId,
      {
        type: isInstruction ? 'RE_CREATED_INSTRUCTION' : 'RE_CREATED_TASK',
        description: isInstruction
          ? `${user.fullName} issued a ${priority}-priority Management Instruction directly to ${salesmanId} on this account, due ${new Date(deadline).toISOString()}: "${desc}". This instruction overrides the salesperson's own judgment on next action for this customer.`
          : `${user.fullName} assigned a ${priority}-priority ${taskLabel} task to ${salesmanId} on this account, due ${new Date(deadline).toISOString()}: "${desc}".`,
        actor: user.fullName,
        source: 'RE Instruction',
        attachmentPath: isInstruction ? undefined : attachmentPath,
      },
      conn
    );
  });
  return getDetail(customerId, user);
}

async function resolveDefaultREOwner() {
  const users = await userRepository.findAll();
  const re = users.find((u) => u.role === 'RECOVERY_EXECUTIVE');
  if (!re) throw new ValidationError('No Recovery Executive user exists to own this task');
  return re;
}

/**
 * A real, specific history label per outcome — never the generic
 * "OUTCOME_RECORDED" placeholder — so the customer's activity trail
 * actually says what happened at a glance. Mirrors
 * lib/v2/stores/app_store.dart's `_outcomeAuditLabel` exactly, so the
 * history reads identically whether an outcome was recorded through the
 * API or (still, for now) through the in-memory demo path.
 */
function outcomeAuditLabel(nextAction, reason) {
  if (nextAction === 'PTP Scheduled') return 'Promise To Pay Recorded';
  if (nextAction === 'Follow-up Scheduled') return 'Will Confirm — Follow-Up Scheduled';
  if (nextAction === 'Verification Pending') return 'Payment Claim Submitted';
  if (nextAction === 'Call Customer' && reason === 'No Answer') return 'No Answer Logged';
  if (reason === 'Dispute Raised') return 'Dispute Raised';
  if (reason === 'Customer Refused') return 'Unable To Commit';
  if (reason === 'Internal Task') return 'Internal Action Required';
  return nextAction;
}

function addDays(date, days) {
  const d = new Date(date);
  d.setDate(d.getDate() + days);
  return d;
}

function addHours(date, hours) {
  const d = new Date(date);
  d.setHours(d.getHours() + hours);
  return d;
}

// A fixed wall-clock hour (local server time) — today if that time hasn't
// passed yet, else tomorrow. Used for the auto-created physical-visit
// deadline (6 PM).
function todayOrNextAt(hour) {
  const d = new Date();
  d.setHours(hour, 0, 0, 0);
  if (d.getTime() <= Date.now()) d.setDate(d.getDate() + 1);
  return d;
}

module.exports = {
  listForUser,
  getNext,
  getDetail,
  getAuditHistoryPage,
  recordOutcome,
  applyOutcome,
  maybeEscalateCustomerRefused,
  takeControl,
  releaseControl,
  reassignCustomer,
  assignManagementInstruction,
  assertVisible,
  resolveDefaultREOwner,
  addDays,
  addHours,
};
