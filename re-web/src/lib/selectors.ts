/**
 * Pure ports of the RE getters in lib/v2/stores/app_store.dart and the
 * unified task builder in lib/v3/screens/re_tasks_screen.dart. The web
 * dashboard must show the same numbers as the mobile app, so the rules
 * (and their edge cases) are copied deliberately — see the Dart sources
 * for the reasoning behind each one.
 */
import {
  DISPUTE_NEEDS_RE_ACTION,
  TASK_TYPE_LABEL,
  creditHealthBand,
  isClaimPending,
  isTaskOpen,
  parseCustomer,
  type Customer,
  type DashboardReport,
  type Dispute,
  type Escalation,
  type NotificationItem,
  type PaymentClaim,
  type Ptp,
  type Salesman,
  type Task,
  type TaskType,
} from "./models";
import { plainTask } from "./plain-task";

export const ALL_BRANCHES = "All Branches";
export const NO_FOLLOW_UP_THRESHOLD_DAYS = 4;
export const PTP_KEPT_TARGET = 75;

export type RmsData = {
  customers: Customer[];
  tasks: Task[];
  ptps: Ptp[];
  disputes: Dispute[];
  paymentClaims: PaymentClaim[];
  escalations: Escalation[];
  salesmen: Salesman[];
  notifications: NotificationItem[];
  dashboard: DashboardReport;
};

export const EMPTY_DATA: RmsData = {
  customers: [],
  tasks: [],
  ptps: [],
  disputes: [],
  paymentClaims: [],
  escalations: [],
  salesmen: [],
  notifications: [],
  dashboard: {},
};

const sameDay = (a: Date, b: Date) =>
  a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();

const sum = <T,>(list: T[], f: (x: T) => number) => list.reduce((s, x) => s + f(x), 0);

/** Same 21:00-on-the-day review deadline the mobile RE queue uses for salesman-raised items. */
export const reviewDeadline = (raisedOn: Date) =>
  new Date(raisedOn.getFullYear(), raisedOn.getMonth(), raisedOn.getDate(), 21);

export type NextStep = { task: Task | null; what: string; why: string; amount: string | null; note: string | null };

const SYSTEM_CLOSED_PREFIXES = ["Auto-closed", "Closed —", "Paused —", "Superseded"];
export const isSystemClosed = (outcome: string | null) =>
  SYSTEM_CLOSED_PREFIXES.some((p) => (outcome ?? "").trimStart().startsWith(p));

const SELF_FOLLOW_UP_SOURCES = new Set(["Record Outcome", "Recovery Reconcile", "Recovery", "No Answer", "Customer Refused"]);

// ── Recovery queue (CompanyRecoveryQueueScreen) ─────────────────────

export type QueueRow = { customer: Customer; rank: number; reason: string; openTasks: number; overdueTasks: number };

/** Same rank as CompanyRecoveryQueueScreen._priorityRank (lower = first). */
export const QUEUE_REASON: Record<number, string> = {
  0: "Most serious (L4)",
  1: "Broke a promise",
  2: "No salesman",
  3: "No next step",
  4: "Escalated (L2/L3)",
  5: "Promise follow-up",
  6: "Late 30+ days",
  7: "Total Overdue",
};

// ── Unified RE task queue ─────────────────────────────────────────────

export type TaskKind =
  | "realTask"
  | "visitReview"
  | "overdueTarget"
  | "dispute"
  | "ptpCorrection"
  | "ptpMissed"
  | "paymentClaim";

export type ReTaskItem = {
  id: string;
  kind: TaskKind;
  refId: string;
  priority: "HIGH" | "MEDIUM" | "LOW";
  title: string;
  taskType?: TaskType;
  customerId: string | null;
  customerName: string;
  salesmanId: string;
  date: Date;
  createdAt: Date;
  isDone: boolean;
  autoClosed: boolean;
  ownerId: string;
  amountLabel: string;
  amountValue: number;
  secondAmountLabel?: string;
  secondAmountValue?: number;
  detail?: string;
};

export type RmsView = ReturnType<typeof buildView>;

/**
 * Items that have their own page on the web (disputes → Disputes; promise
 * changes and payment checks → Approvals). The mobile RE Tasks screen mixes
 * these in; the web keeps them out of My Tasks so an item never shows up
 * on two pages.
 */
export const APPROVAL_KINDS = new Set<TaskKind>(["dispute", "ptpCorrection", "paymentClaim"]);

/** Same buckets as reportService.getDashboard (by oldest overdue days, summing totalDue). */
export const AGEING_BUCKETS = ["Not Due", "0 - 30 Days", "31 - 60 Days", "61 - 90 Days", "90+ Days"] as const;

export function ageingOf(dueCustomers: Customer[]) {
  const b: Record<string, number> = Object.fromEntries(AGEING_BUCKETS.map((k) => [k, 0]));
  for (const c of dueCustomers) {
    const d = c.oldestOverdueDays;
    const k = d <= 0 ? "Not Due" : d <= 30 ? "0 - 30 Days" : d <= 60 ? "31 - 60 Days" : d <= 90 ? "61 - 90 Days" : "90+ Days";
    b[k] += c.totalDue;
  }
  return b;
}

export function buildView(data: RmsData, branch: string, currentUserId: string, now = new Date()) {
  const branchActive = branch !== ALL_BRANCHES;
  const customerById = new Map(data.customers.map((c) => [c.id, c]));
  const salesmanById = new Map(data.salesmen.map((s) => [s.id, s]));

  const customerBranchOf = (id: string) => customerById.get(id)?.branch ?? "Turning Point";
  const salesmanBranchOf = (id: string) => salesmanById.get(id)?.branch ?? "Turning Point";
  const taskBranchOf = (t: Task) =>
    customerById.get(t.customerId)?.branch ?? (t.ownerId ? salesmanBranchOf(t.ownerId) : "Turning Point");
  const inBranch = (b: string) => !branchActive || b === branch;

  const customers = branchActive ? data.customers.filter((c) => c.branch === branch) : data.customers;
  const tasks = (branchActive ? data.tasks.filter((t) => inBranch(taskBranchOf(t))) : data.tasks).map((t) =>
    t.customerName === t.customerId ? { ...t, customerName: customerById.get(t.customerId)?.name ?? t.customerId } : t,
  );
  const ptps = branchActive ? data.ptps.filter((p) => inBranch(customerBranchOf(p.customerId))) : data.ptps;
  const disputes = branchActive ? data.disputes.filter((d) => inBranch(customerBranchOf(d.customerId))) : data.disputes;
  const paymentClaims = branchActive
    ? data.paymentClaims.filter((p) => inBranch(customerBranchOf(p.customerId)))
    : data.paymentClaims;
  const escalations = branchActive
    ? data.escalations.filter((e) => inBranch(customerBranchOf(e.customerId)))
    : data.escalations;
  const salesmen = branchActive ? data.salesmen.filter((s) => s.branch === branch) : data.salesmen;
  const d = data.dashboard;

  const salesmanName = (id: string) => {
    if (!id) return "Unmapped";
    return salesmanById.get(id)?.fullName || id;
  };
  const customerName = (id: string) => customerById.get(id)?.name ?? id;

  const branchOptions = [
    ALL_BRANCHES,
    ...[
      ...new Set([
        ...data.salesmen.map((s) => s.branch.trim()).filter(Boolean),
        ...data.customers.map((c) => c.branch.trim()).filter(Boolean),
      ]),
    ].sort(),
  ];

  // Headline figures — server numbers for All Branches, recomputed from
  // the branch-scoped lists otherwise (AppStore does the same).
  const dueCustomers = customers.filter((c) => c.totalDue > 0);
  const totalOutstanding = sum(customers, (c) => c.totalOutstanding);
  const totalOverdueAmount = branchActive ? sum(dueCustomers, (c) => c.totalDue) : (d.totalOverdueAmount ?? 0);
  const totalOverdueCustomerCount = branchActive ? dueCustomers.length : (d.totalOverdueCustomerCount ?? 0);
  const branchDueTodayPtps = ptps.filter(
    (p) => (p.status === "scheduled" || p.status === "pendingVerification") && sameDay(p.promiseDate, now),
  );
  const dueTodayPtpAmount = branchActive ? sum(branchDueTodayPtps, (p) => p.amountPromised) : (d.dueTodayPtpAmount ?? 0);
  const dueTodayPtpCount = branchActive ? branchDueTodayPtps.length : (d.dueTodayPtpCount ?? 0);
  const expectedCollection = sum(
    data.ptps.filter((p) => p.status === "scheduled" || p.status === "pendingVerification"),
    (p) => p.amountPromised,
  );

  const brokenPtps = ptps.filter((p) => p.status === "broken");
  const openEscalations = escalations.filter((e) => e.isOpen);
  const ptpCorrectionRequests = ptps.filter((p) => p.correctionStatus === "Pending");
  const pendingPaymentClaims = paymentClaims.filter(isClaimPending);
  const disputesNeedingAction = disputes.filter((x) => DISPUTE_NEEDS_RE_ACTION.has(x.status));
  const pendingEditTasks = tasks.filter((t) => t.approvalStatus === "Pending");
  const internalActionTasks = tasks.filter(
    (t) => t.type === "financialTeamFollowUp" && isTaskOpen(t) && t.ownerId === currentUserId,
  );

  const physicalVisitsPendingReview = tasks.filter(
    (t) => t.type === "physicalVisit" && t.status === "completed" && !(t.outcome ?? "").trim(),
  );

  const ownerMappingRequired = customers.filter((c) => c.ownerMappingRequired);
  const noValidNextAction = customers.filter((c) => !c.hasValidNextAction && c.totalDue > 0);
  const brokenCustomerIds = new Set(brokenPtps.map((p) => p.customerId));
  const atRiskAccounts = customers.filter((c) => {
    if (c.totalDue <= 0) return false;
    const band = creditHealthBand(c.creditHealthScore);
    return (
      c.escalationLevel !== "none" ||
      brokenCustomerIds.has(c.id) ||
      c.oldestOverdueDays >= 60 ||
      band === "High" ||
      band === "Critical"
    );
  });

  const daysSinceLastFollowUp = (c: Customer) => {
    if (c.serverDaysSinceLastFollowUp != null) return c.serverDaysSinceLastFollowUp;
    let last: Date | null = null;
    for (const a of c.auditHistory) {
      if (a.actor === "System") continue;
      if (!last || a.timestamp > last) last = a.timestamp;
    }
    for (const t of data.tasks) {
      if (t.customerId !== c.id || !t.completedAt) continue;
      if (!last || t.completedAt > last) last = t.completedAt;
    }
    if (!last) return c.totalDue > 0 ? 999999 : 0;
    return Math.max(0, Math.floor((now.getTime() - last.getTime()) / 86_400_000));
  };

  const noFollowUpAccounts: Customer[] = branchActive
    ? customers.filter((c) => c.totalDue > 0 && daysSinceLastFollowUp(c) >= NO_FOLLOW_UP_THRESHOLD_DAYS)
    : (d.noFollowUpAccounts ?? []).map(parseCustomer);

  const topOverdueCustomers: Customer[] = branchActive
    ? [...dueCustomers].sort((a, b) => b.totalDue - a.totalDue).slice(0, 5)
    : (d.topOverdueCustomers ?? []).map(parseCustomer);

  const disputesAwaitingReviewCount = branchActive ? disputesNeedingAction.length : (d.disputesAwaitingReviewCount ?? 0);
  const physicalVisitsPendingReviewCount = branchActive
    ? physicalVisitsPendingReview.length
    : (d.physicalVisitsPendingReviewCount ?? 0);
  const salesmenOverdueTargetsCount = salesmen.filter((s) => s.collectionAchievedPercent < 60).length;

  const escalatedCustomerIds = new Set(openEscalations.map((e) => e.customerId));
  const totalOpenTaskItemsCount =
    tasks.filter((t) => {
      if (t.status === "completed") return false;
      const selfFollowUp =
        t.type === "customerCall" &&
        ["Record Outcome", "Recovery Reconcile", "Recovery", "No Answer"].includes(t.source) &&
        t.ownerId !== currentUserId;
      return !(selfFollowUp && t.deadline >= now);
    }).length +
    physicalVisitsPendingReviewCount +
    salesmenOverdueTargetsCount +
    disputesAwaitingReviewCount +
    ptpCorrectionRequests.length +
    pendingPaymentClaims.length +
    brokenPtps.filter((p) => !escalatedCustomerIds.has(p.customerId)).length;

  // Same definition as AppStore.pendingApprovalsCount (mobile badge)…
  const pendingApprovalsCount = disputesNeedingAction.length + ptpCorrectionRequests.length + pendingPaymentClaims.length;
  // What the web Approvals page lists: promise changes + payment checks.
  // Disputes live only on the Disputes page. Payments read the unfiltered
  // claim list, as the mobile Approvals tab does.
  const approvalInboxCount = ptpCorrectionRequests.length + data.paymentClaims.filter(isClaimPending).length;

  const recoveryTarget = d.recoveryTarget ?? 0;
  const todaysCollectedAmount = d.todaysCollectedAmount ?? 0;

  const buildReTaskItems = (): ReTaskItem[] => {
    const items: ReTaskItem[] = [];
    const salesmanIds = new Set(data.salesmen.map((s) => s.id));

    for (const t of tasks) {
      const visitNoOutcome = t.type === "physicalVisit" && t.status === "completed" && !(t.outcome ?? "").trim();
      if (visitNoOutcome) continue;
      const done = t.status === "completed";
      const selfFollowUp =
        (t.type === "customerCall" || t.type === "physicalVisit") &&
        SELF_FOLLOW_UP_SOURCES.has(t.source) &&
        t.ownerId !== currentUserId &&
        salesmanIds.has(t.ownerId);
      if (!done && selfFollowUp && t.deadline >= now) continue;
      const c = customerById.get(t.customerId);
      const salesmanId = c?.assignedSalesmanId || t.ownerId;
      items.push({
        id: `task_${t.id}`,
        kind: "realTask",
        refId: t.id,
        taskType: t.type,
        priority: t.priority === "Critical" || t.priority === "High" ? "HIGH" : t.priority === "Normal" ? "MEDIUM" : "LOW",
        title: TASK_TYPE_LABEL[t.type] ?? t.type,
        customerId: t.customerId,
        customerName: c?.name ?? t.customerName,
        salesmanId,
        date: t.deadline,
        createdAt: t.createdAt,
        isDone: done,
        autoClosed: done && isSystemClosed(t.outcome),
        ownerId: t.ownerId,
        amountLabel: "Outstanding",
        amountValue: c?.totalDue ?? 0,
        detail: t.reason,
      });
    }

    for (const t of physicalVisitsPendingReview) {
      const c = customerById.get(t.customerId);
      const dispute = disputes.find((x) => x.customerId === t.customerId);
      items.push({
        id: `visit_${t.id}`,
        kind: "visitReview",
        refId: t.id,
        taskType: t.type,
        priority: "MEDIUM",
        title: "Visit done, but no result written",
        customerId: t.customerId,
        customerName: c?.name ?? t.customerName,
        salesmanId: c?.assignedSalesmanId || t.ownerId,
        date: t.completedAt ?? t.deadline,
        createdAt: t.completedAt ?? t.createdAt,
        isDone: false,
        autoClosed: false,
        ownerId: "",
        amountLabel: dispute ? "Amount in Dispute" : "Outstanding",
        amountValue: dispute ? dispute.amount : (c?.totalDue ?? 0),
      });
    }

    if (now.getDate() === 1) {
      for (const s of salesmen) {
        if (s.collectionAchievedPercent >= 60 || s.underperformanceDismissedThisMonth) continue;
        const owned = data.customers
          .filter((c) => c.assignedSalesmanId === s.id && c.totalDue > 0)
          .sort((a, b) => b.totalDue - a.totalDue);
        const worst = owned[0];
        if (!worst) continue;
        items.push({
          id: `target_${worst.id}`,
          kind: "overdueTarget",
          refId: worst.id,
          priority: "MEDIUM",
          title: "Salesman is behind target",
          customerId: worst.id,
          customerName: worst.name,
          salesmanId: s.id,
          date: new Date(now.getFullYear(), now.getMonth(), now.getDate(), 21),
          createdAt: new Date(now.getFullYear(), now.getMonth(), now.getDate()),
          isDone: false,
          autoClosed: false,
          ownerId: "",
          amountLabel: "Overdue Amount",
          amountValue: worst.totalDue,
          secondAmountLabel: "PTP Due Today",
          secondAmountValue: s.dueTodayPtps,
          detail: `${s.fullName} at ${s.collectionAchievedPercent}% of collection target`,
        });
      }
    }

    for (const x of disputesNeedingAction) {
      const awaitingVerification = x.status === "Awaiting Verification";
      items.push({
        id: `dispute_${x.id}`,
        kind: "dispute",
        refId: x.id,
        priority: x.priority === "High" ? "HIGH" : "MEDIUM",
        title: awaitingVerification ? "Dispute fixed — please check" : "Bill dispute — please decide",
        customerId: x.customerId,
        customerName: customerName(x.customerId),
        salesmanId: customerById.get(x.customerId)?.assignedSalesmanId ?? "",
        date: reviewDeadline(x.raisedDate),
        createdAt: awaitingVerification ? x.lastUpdated : x.raisedDate,
        isDone: false,
        autoClosed: false,
        ownerId: "",
        amountLabel: "Dispute Amount",
        amountValue: x.amount,
        detail: x.invoiceNumber ? `Invoice ${x.invoiceNumber} · ${x.reason}` : x.reason,
      });
    }

    for (const p of ptpCorrectionRequests) {
      const c = customerById.get(p.customerId);
      const raised = p.correctionRequestedDate ?? p.promiseDate;
      items.push({
        id: `ptpc_${p.id}`,
        kind: "ptpCorrection",
        refId: p.id,
        priority: "MEDIUM",
        title: "Change to a payment promise",
        customerId: p.customerId,
        customerName: c?.name ?? p.customerId,
        salesmanId: c?.assignedSalesmanId ?? "",
        date: reviewDeadline(raised),
        createdAt: raised,
        isDone: false,
        autoClosed: false,
        ownerId: "",
        amountLabel: "Requested Amount",
        amountValue: p.correctionRequestedAmount ?? p.amountPromised,
        detail: p.correctionReason ?? undefined,
      });
    }

    for (const p of pendingPaymentClaims) {
      const c = customerById.get(p.customerId);
      items.push({
        id: `pc_${p.id}`,
        kind: "paymentClaim",
        refId: p.id,
        priority: "HIGH",
        title: "Customer says they already paid",
        customerId: p.customerId,
        customerName: c?.name ?? p.customerId,
        salesmanId: c?.assignedSalesmanId ?? "",
        date: reviewDeadline(p.claimDate),
        createdAt: p.claimDate,
        isDone: false,
        autoClosed: false,
        ownerId: "",
        amountLabel: "Claimed Amount",
        amountValue: p.amount,
        detail: p.reference ? `Ref ${p.reference}` : undefined,
      });
    }

    const openTaskCustomerIds = new Set(tasks.filter(isTaskOpen).map((t) => t.customerId));
    for (const p of brokenPtps) {
      if (escalatedCustomerIds.has(p.customerId) || openTaskCustomerIds.has(p.customerId)) continue;
      const c = customerById.get(p.customerId);
      items.push({
        id: `ptpm_${p.id}`,
        kind: "ptpMissed",
        refId: p.id,
        priority: "HIGH",
        title: "Payment promise broken",
        customerId: p.customerId,
        customerName: c?.name ?? p.customerId,
        salesmanId: c?.assignedSalesmanId ?? "",
        date: p.promiseDate,
        createdAt: p.promiseDate,
        isDone: false,
        autoClosed: false,
        ownerId: "",
        amountLabel: "PTP Amount",
        amountValue: p.amountPromised,
        detail: p.brokenReason ?? undefined,
      });
    }

    return items;
  };

  /** My Tasks on the web: the RE task list without the yes/no approval items. */
  const buildWorkItems = () => buildReTaskItems().filter((i) => !APPROVAL_KINDS.has(i.kind));
  const workOpenCount = buildWorkItems().filter((i) => !i.isDone).length;

  /**
   * Company Recovery Queue — CompanyRecoveryQueueScreen: customers with
   * overdue (or outstanding, from the Total Outstanding card), ranked by
   * the mobile _priorityRank; ties keep server order.
   */
  const recoveryQueue = (mode: "overdue" | "outstanding" = "overdue"): QueueRow[] => {
    const openTasksByCustomer = new Map<string, Task[]>();
    for (const t of tasks) {
      if (!isTaskOpen(t)) continue;
      const list = openTasksByCustomer.get(t.customerId) ?? [];
      list.push(t);
      openTasksByCustomer.set(t.customerId, list);
    }
    const rankOf = (c: Customer) => {
      if (c.escalationLevel === "L4") return 0;
      if (brokenCustomerIds.has(c.id)) return 1;
      if (c.ownerMappingRequired) return 2;
      if (!c.hasValidNextAction) return 3;
      if (c.escalationLevel === "L3" || c.escalationLevel === "L2") return 4;
      if (c.primaryNextAction.toLowerCase().includes("ptp")) return 5;
      if (c.oldestOverdueDays > 30) return 6;
      return 7;
    };
    return customers
      .filter((c) => (mode === "outstanding" ? c.totalOutstanding > 0 : c.totalDue > 0))
      .map((c) => {
        const open = openTasksByCustomer.get(c.id) ?? [];
        const rank = rankOf(c);
        return { customer: c, rank, reason: QUEUE_REASON[rank], openTasks: open.length, overdueTasks: open.filter((t) => t.deadline < now).length };
      })
      .sort((a, b) => a.rank - b.rank);
  };

  // Control Dashboard stat cards — ControlDashboardScreen._buildStatCards.
  const startOfToday = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  const startOfTomorrow = new Date(startOfToday.getTime() + 86_400_000);
  const scheduledPtps = ptps.filter((p) => p.status === "scheduled");
  const overduePtps = scheduledPtps.filter((p) => p.promiseDate < startOfToday);
  const dueTodayPtps = ptps.filter(
    (p) => (p.status === "scheduled" || p.status === "pendingVerification") && p.promiseDate >= startOfToday && p.promiseDate < startOfTomorrow,
  );

  /** 5 PM Control snapshot — same rules as AppStore.runFivePmControl, computed on demand. */
  const fivePmControl = () => {
    const overdueTasks = tasks.filter((t) => isTaskOpen(t) && t.deadline < now);
    const mandatoryNotDone = data.tasks.filter((t) => t.priority === "Critical" && t.status !== "completed");
    const brokenNoNext = brokenPtps.filter((p) => customerById.get(p.customerId)?.hasValidNextAction === false);
    const l3NoPlan = escalations.filter((e) => e.isOpen && e.level === "L3" && !e.plan.trim());
    return {
      timestamp: now,
      overdueTasks,
      mandatoryNotDone,
      brokenNoNext,
      ownerlessExposure: sum(ownerMappingRequired, (c) => c.totalDue),
      ownerlessCustomers: ownerMappingRequired,
      l3NoPlan,
    };
  };

  // ── Next step (one rule for every page) ─────────────────────────
  // The customer's own open task is the source of truth. The stored
  // primaryNextAction / reasonForAction can be left over from an older
  // step (the server sets "CALL CUSTOMER" on a new recovery task without
  // rewriting reasonForAction), so it is only a fallback when no task is open.
  const openTasksByCustomer = new Map<string, Task>();
  for (const t of data.tasks) {
    if (!isTaskOpen(t)) continue;
    const cur = openTasksByCustomer.get(t.customerId);
    if (!cur || t.deadline < cur.deadline) openTasksByCustomer.set(t.customerId, t);
  }
  const nextStepFor = (c: Customer): NextStep => {
    const task = openTasksByCustomer.get(c.id) ?? null;
    if (task) {
      const p = plainTask(task.reason, c.name);
      return { task, what: p.what, why: p.why, amount: p.amount, note: p.note };
    }
    return { task: null, what: c.primaryNextAction, why: c.reasonForAction, amount: null, note: null };
  };

  return {
    branch,
    branchActive,
    branchOptions,
    customers,
    tasks,
    ptps,
    disputes,
    paymentClaims,
    escalations,
    salesmen,
    notifications: data.notifications,
    allCustomers: data.customers,
    allPtps: data.ptps,
    allTasks: data.tasks,
    nextStepFor,
    allPaymentClaims: data.paymentClaims,
    allSalesmen: data.salesmen,
    allDisputes: data.disputes,
    customerById,
    salesmanById,
    salesmanName,
    customerName,
    // headline
    totalOutstanding,
    totalOverdueAmount,
    totalOverdueCustomerCount,
    dueTodayPtpAmount,
    dueTodayPtpCount,
    expectedCollection,
    recoveryTarget,
    todaysCollectedAmount,
    todaysCollectedCustomerCount: d.todaysCollectedCustomerCount ?? 0,
    ptpKeptMtdPercent: d.ptpKeptMtdPercent ?? 0,
    outstandingAgeingBuckets: branchActive ? ageingOf(dueCustomers) : (d.outstandingAgeingBuckets ?? {}),
    disputeOverviewByStatus: d.disputeOverviewByStatus ?? {},
    ptpOverviewStats: d.ptpOverviewStats ?? {},
    topOverdueCustomers,
    noFollowUpAccounts,
    daysSinceLastFollowUp,
    // exceptions
    brokenPtps,
    openEscalations,
    l3l4Cases: openEscalations.filter((e) => e.level === "L3" || e.level === "L4"),
    ownerMappingRequired,
    ownerlessExposure: sum(ownerMappingRequired, (c) => c.totalDue),
    noValidNextAction,
    atRiskAccounts,
    moneyAtRisk: sum(atRiskAccounts, (c) => c.totalDue),
    criticalTasks: tasks.filter((t) => isTaskOpen(t) && (t.priority === "Critical" || t.priority === "High") && t.deadline < now),
    physicalVisitsPendingReview,
    // approvals
    ptpCorrectionRequests,
    pendingPaymentClaims,
    disputesNeedingAction,
    pendingEditTasks,
    internalActionTasks,
    pendingApprovalsCount,
    approvalInboxCount,
    disputesAwaitingReviewCount,
    totalOpenTaskItemsCount,
    unreadNotificationCount: data.notifications.filter((n) => !n.read).length,
    buildReTaskItems,
    buildWorkItems,
    workOpenCount,
    recoveryQueue,
    scheduledPtps,
    scheduledPtpAmount: sum(scheduledPtps, (p) => p.amountPromised),
    overduePtps,
    overduePtpAmount: sum(overduePtps, (p) => p.amountPromised),
    dueTodayPtps,
    brokenPtpAmount: sum(brokenPtps, (p) => p.amountPromised),
    /** Salesmen carrying overdue exposure, server order — dashboard "Salesmen Performance" and the salesmen list. */
    salesmenWithOverdue: salesmen.filter((s) => s.totalOverdue > 0),
    /** Approvals tab "Payments" reads the unfiltered claim list on mobile (ReApprovalsTab). */
    approvalsPaymentClaims: data.paymentClaims.filter(isClaimPending),
    fivePmControl,
  };
}
