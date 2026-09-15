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
const { driveRecoveryTask } = require('./recoveryTaskService');
const { NotFoundError, ForbiddenError, ValidationError } = require('../errors/AppError');

// Kept in sync with lib/v2/stores/app_store.dart's `noAnswerThreshold`.
// The 3rd consecutive unanswered attempt auto-creates a Physical Visit
// and resets the counter; any non-No-Answer outcome in between resets it
// too (the salesman broke the missed-call streak).
const NO_ANSWER_THRESHOLD = 3;

async function assertVisible(customer, user) {
  if (!customer) throw new NotFoundError('Customer');
  if (user.role === 'SALESPERSON' && customer.assignedSalesmanId !== user.id) {
    throw new ForbiddenError('This customer is not in your portfolio');
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
  const [allPtps, allTasks] = await Promise.all([ptpRepository.findAll(), taskRepository.findAll()]);
  const ptpsByCustomer = scoringService.groupBy(allPtps, (p) => p.customerId);
  const tasksByCustomer = scoringService.groupBy(allTasks, (t) => t.customerId);
  return customerList.map((c) => {
    const cPtps = ptpsByCustomer.get(c.id) || [];
    const cTasks = tasksByCustomer.get(c.id) || [];
    const creditHealthComponents = scoringService.computeCreditHealthComponents(c, cPtps);
    const creditHealthScore = creditHealthComponents ? creditHealthComponents.total : null;
    return {
      ...c,
      hasValidNextAction: scoringService.hasValidNextAction(c, cPtps, cTasks),
      creditHealthScore,
      creditHealthBand: scoringService.creditHealthBand(creditHealthScore),
      creditHealthComponents,
    };
  });
}

/**
 * A SALESPERSON sees only their own portfolio (real BUSY-sourced
 * customers now that the daily sync upserts straight into `customers`
 * — see customerRepository.upsertFromBusy). RECOVERY_EXECUTIVE/MANAGEMENT
 * see the whole company.
 */
async function listForUser(user) {
  const raw = user.role === 'SALESPERSON' ? await customerRepository.findBySalesman(user.id) : await customerRepository.findAll();
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
  const [invoices, history, [enriched], coverage] = await Promise.all([
    customerRepository.findInvoices(id),
    auditRepository.listForCustomer(id),
    enrichCustomers([customer]),
    recoveryReconcileService.coverageFor(id),
  ]);
  // coveredAmount = overdue currently under a PTP / dispute / payment claim.
  // actionableAmount = what the salesperson should actually be chasing now.
  return {
    ...enriched,
    coveredAmount: coverage.covered,
    actionableAmount: coverage.actionable,
    invoices,
    auditHistory: history,
  };
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
 * recordOutcome so requestOutcome edit's "NoAnswerReplacement" kind can
 * apply the exact same logic once an RE approves it (see
 * outcomeEditService.js). `user` is whoever the outcome is being recorded
 * for (the acting salesperson normally; still the original salesperson,
 * not the approving RE, when called from an approved edit request — every
 * task this creates must stay owned by them).
 */
async function applyOutcome(conn, customer, user, { nextAction, reason, details, followUpAt, ptpAmountValue, ptpDate, ptpMode, attachmentPath, replacingNoAnswer }) {
  const customerId = customer.id;

  // `replacingNoAnswer` is now only used by the RE-approved stale-edit
  // path (outcomeEditService) — the salesman client records a plain new
  // outcome instead. Guard it against being hit once the customer has
  // moved on to a different recorded outcome (a stale client, a replay).
  if (replacingNoAnswer && !(customer.primaryNextAction === 'Call Customer' && customer.reasonForAction === 'No Answer')) {
    throw new ValidationError('No recorded No Answer outcome to replace for this customer');
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

  // A No Answer is a non-contact and "Will Confirm / Follow-up" is a
  // pending touch — neither resolves the account, so it stays actionable
  // (the customer stays in Today's Recovery) and the salesman records the
  // real outcome once the customer calls back via "New Record Outcome".
  // Every resolving outcome still parks the account.
  const isNoAnswerOutcome = nextAction === 'Call Customer' && reason === 'No Answer';

  const nonResolving =
    isNoAnswerOutcome ||
    nextAction === 'Follow-up' ||
    nextAction === 'Follow-up Scheduled';

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
      },
      conn
    );
  } else if (nextAction === 'Internal Action' || nextAction === 'Action Required') {
    const reOwner = await resolveDefaultREOwner();
    await taskRepository.insert(
      { type: 'financialTeamFollowUp', customerId, ownerId: reOwner.id, deadline: addHours(new Date(), 4), priority: 'High', reason: details, source: 'Record Outcome', attachmentPath },
      conn
    );
  } else if (nextAction === 'Follow-up' || nextAction === 'Follow-up Scheduled') {
    await taskRepository.insert(
      { type: 'customerCall', customerId, ownerId: user.id, deadline: followUpAt || addDays(new Date(), 1), priority: 'Normal', reason: details, source: 'Record Outcome' },
      conn
    );
  } else if (reason === 'Customer Refused') {
    // No bespoke task here — recordOutcome drives the single
    // `source='Recovery'` call task on a 2-day cadence that self-renews
    // (via the missed-deadline sweep) until the balance is cleared.
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
    await paymentClaimRepository.insert({ customerId, amount, claimDate: new Date(), reference: `Claimed by ${user.fullName} — no reference given`, status: 'Awaiting Verification', attachmentPath }, conn);
  } else if (nextAction === 'Call Customer' && reason === 'No Answer') {
    // A No Answer keeps ONE recurring call task (bumped every 2h by the
    // `no-answer-cycle` job). If the whole day passes with nothing
    // recorded, that job swaps it for a Physical Visit (6 PM) and removes
    // the call task; two visit cycles → auto L2.
    await customerRepository.update(customerId, { noAnswerAttempts: baselineNoAnswerAttempts + 1 }, conn);
    const open = (await taskRepository.findByCustomer(customerId, conn)).filter(
      (t) => t.source === 'No Answer' && !['completed', 'closed', 'cancelled'].includes(t.status)
    );
    const deadline = addHours(new Date(), 2);
    const noAnswerReason = `Call ${customer.name || 'the customer'} — no answer on the last attempt. Try again, or record what happened.`;
    if (open.length > 0) {
      await taskRepository.update(open[0].id, { deadline, reason: noAnswerReason }, conn);
      for (const dup of open.slice(1)) {
        await taskRepository.update(dup.id, { status: 'completed', completedAt: new Date(), outcome: 'Superseded — single No Answer task kept.' }, conn);
      }
    } else {
      await taskRepository.insert(
        { type: 'customerCall', customerId, ownerId: user.id, deadline, priority: 'Normal', reason: noAnswerReason, source: 'No Answer' },
        conn
      );
    }
  }
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
  });
}

/**
 * Non-contact loop floor. Every time the customer hits NO_ANSWER_THRESHOLD
 * unanswered attempts, a "Non-response threshold reached" physical-visit
 * task is raised and the counter resets — without this the salesman could
 * loop No Answer → visit → No Answer forever. Once TWO such cycles have
 * happened the customer is genuinely unreachable: escalate to L2 so the RE
 * takes over, with the real attempt history as the reason. Post-commit and
 * best-effort — same pattern as maybeEscalateCustomerRefused.
 */
async function maybeEscalateNonContact(customerId, user, { nextAction, reason }) {
  if (!(nextAction === 'Call Customer' && reason === 'No Answer')) return;
  const customer = await customerRepository.findById(customerId);
  if (!customer) return;
  // Only raise the floor once — never downgrade a customer already at L2+.
  if (!['none', 'L1'].includes(customer.escalationLevel)) return;

  const tasks = await taskRepository.findByCustomer(customerId);
  const nonContactCycles = tasks.filter(
    (t) => t.type === 'physicalVisit' && t.reason === 'Non-response threshold reached'
  ).length;
  if (nonContactCycles < 2) return;

  const alreadyOpen = await escalationRepository.findOpenByCustomer(customerId);
  if (alreadyOpen.length > 0) return;

  await escalationService.raise(customerId, user, {
    level: 'L2',
    reason:
      `Customer unreachable — ${nonContactCycles} full non-response cycles ` +
      `(${nonContactCycles * NO_ANSWER_THRESHOLD}+ unanswered call attempts, ` +
      `${nonContactCycles} physical-visit escalations already raised with no contact made).`,
    plan:
      'Salesperson continues field follow-up under RE supervision. RE to review the ' +
      'contact numbers on file and pursue alternate channels (GST address, references, site visit).',
    ownerId: customer.assignedSalesmanId,
    deadline: addDays(new Date(), 3),
    moneyAtRisk: customer.totalDue,
  });
}

async function recordOutcome(customerId, user, body) {
  await withTransaction(async (conn) => {
    const customer = await customerRepository.findById(customerId);
    await assertVisible(customer, user);
    await applyOutcome(conn, customer, user, body);
  });

  await maybeEscalateCustomerRefused(customerId, user, body);
  await maybeEscalateNonContact(customerId, user, body);

  // Retarget the salesperson's single recovery task to whatever slice of
  // the overdue is NOT under a PTP / dispute / payment claim. A partial
  // PTP no longer parks the whole customer — the salesperson keeps a task
  // for the remainder; when every rupee is covered the task closes and
  // the customer parks. Never creates a second task (see
  // recoveryReconcileService).
  await recoveryReconcileService.reconcileState(customerId, { trigger: 'record.outcome' });

  // Immediately (re)point the single `source='Recovery'` call task at the
  // still-actionable slice of the overdue — the part NOT under the PTP /
  // dispute / payment claim this outcome just created. Without this a
  // partial PTP (or any covering outcome) leaves the salesperson with no
  // task until the next nightly reconcile (~24h). No Answer and Follow-up
  // own their own recurring task, so they're skipped here.
  {
    const { nextAction, reason, details } = body;
    if (reason === 'Customer Refused') {
      await driveRecoveryTask(customerId, {
        headline: `Customer refused to commit — call again. ${details || ''}`.trim(),
        priority: 'Normal',
        deadlineOverride: addDays(new Date(), 2),
      });
    } else if (reason === 'Dispute Raised') {
      await driveRecoveryTask(customerId, {
        headline: 'Dispute raised — the RE is reviewing it. Keep working the uncovered balance.',
        priority: 'Normal',
        deadlineHour: 21,
      });
    } else if (['PTP Scheduled', 'Verification Pending', 'Internal Action', 'Action Required'].includes(nextAction)) {
      const headline = {
        'PTP Scheduled': 'PTP recorded — keep working the part of the balance it does not cover.',
        'Verification Pending': 'Payment claim submitted — the RE is verifying it. Keep working the uncovered balance.',
        'Internal Action': 'Internal action logged — the RE is reviewing it. Keep working the uncovered balance.',
        'Action Required': 'Keep working the balance.',
      }[nextAction];
      await driveRecoveryTask(customerId, { headline, priority: 'Normal', deadlineHour: 21 });
    }
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
