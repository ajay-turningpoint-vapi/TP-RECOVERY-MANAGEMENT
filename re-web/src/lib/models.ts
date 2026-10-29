/**
 * TypeScript ports of the Flutter models (lib/v2/models/*.dart), parsed
 * from the TP-RMS API's JSON. Field names and defaults follow the Dart
 * `fromJson` factories so selectors compute the same numbers as mobile.
 */

type Json = Record<string, unknown>;

const str = (v: unknown, d = "") => (typeof v === "string" ? v : v == null ? d : String(v));
const optStr = (v: unknown) => (typeof v === "string" && v.length > 0 ? v : null);
const numv = (v: unknown, d = 0) => (v == null || v === "" ? d : Number(v));
const optNum = (v: unknown) => (v == null || v === "" ? null : Number(v));
const date = (v: unknown) => (v ? new Date(v as string) : null);

// ── Customer ───────────────────────────────────────────────────────────

export type AuditEvent = {
  id?: string;
  timestamp: Date;
  description: string;
  type: string;
  actor: string;
  previousState: string | null;
  newState: string | null;
  source: string;
  attachmentPath: string | null;
};

export function parseAuditEvent(j: Json): AuditEvent {
  return {
    id: optStr(j.id) ?? undefined,
    timestamp: new Date(j.occurredAt as string),
    description: str(j.description),
    type: str(j.type),
    actor: str(j.actor, "System") || "System",
    previousState: optStr(j.previousState),
    newState: optStr(j.newState),
    source: str(j.source, "App") || "App",
    attachmentPath: optStr(j.attachmentPath),
  };
}

export type Invoice = {
  id: string;
  number: string;
  date: Date | null;
  dueDate: Date | null;
  totalAmount: number;
  pendingAmount: number;
  dueDays: number | null;
  message: string | null;
  status: string;
};

export function parseInvoice(j: Json): Invoice {
  return {
    id: str(j.id),
    number: str(j.No),
    date: date(j.Date),
    dueDate: date(j.DueDate),
    totalAmount: numv(j.TotalAmount),
    pendingAmount: numv(j.PendingAmount),
    dueDays: optNum(j.DueDays),
    message: optStr(j.Message),
    status: str(j.status),
  };
}

export type EscalationLevel = "none" | "L1" | "L2" | "L3" | "L4";

export type Customer = {
  id: string;
  name: string;
  totalOutstanding: number;
  totalDue: number;
  coveredAmount: number;
  actionableAmount: number;
  outcomeWaitText: string | null;
  oldestOverdueDays: number;
  currentRecoveryState: string;
  primaryNextAction: string;
  reasonForAction: string;
  assignedSalesmanId: string;
  contactNumber: string;
  alternateContactNumber: string;
  auditHistory: AuditEvent[];
  serverDaysSinceLastFollowUp: number | null;
  invoices: Invoice[];
  lastPaymentAmount: number | null;
  lastPaymentDate: Date | null;
  creditLimit: number;
  availableLimit: number;
  creditDays: number;
  address: string | null;
  gstNo: string | null;
  futureDue: number;
  ageing: { age0_30: number; age31_60: number; age61_90: number; age90Plus: number };
  escalationLevel: EscalationLevel;
  ownerMappingRequired: boolean;
  hasValidNextAction: boolean;
  creditHealthScore: number | null;
  creditHealthComponents: Record<string, number> | null;
  disputedAmount: number;
  branch: string;
  noAnswerAttempts: number;
  updatedAt: Date | null;
  financialFreshness: Date | null;
};

export function parseCustomer(j: Json): Customer {
  const ageing = (j.ageingBuckets ?? {}) as Json;
  return {
    id: str(j.id),
    name: str(j.name),
    totalOutstanding: numv(j.totalOutstanding),
    totalDue: numv(j.totalDue ?? j.overdueAmount),
    coveredAmount: numv(j.coveredAmount),
    actionableAmount: numv(j.actionableAmount),
    outcomeWaitText: optStr((j.outcomeWait as Json | undefined)?.text),
    oldestOverdueDays: numv(j.oldestOverdueDays),
    currentRecoveryState: str(j.currentRecoveryState),
    primaryNextAction: str(j.primaryNextAction),
    reasonForAction: str(j.reasonForAction),
    assignedSalesmanId: str(j.assignedSalesmanId),
    contactNumber: str(j.contactNumber ?? j.mobile),
    alternateContactNumber: str(j.alternateContactNumber),
    auditHistory: ((j.auditHistory as Json[] | undefined) ?? []).map(parseAuditEvent),
    serverDaysSinceLastFollowUp: optNum(j.daysSinceLastFollowUp),
    invoices: ((j.invoices as Json[] | undefined) ?? []).map(parseInvoice),
    lastPaymentAmount: optNum(j.lastPaymentAmount),
    lastPaymentDate: date(j.lastPaymentDate),
    creditLimit: numv(j.creditLimit),
    availableLimit: numv(j.availableLimit),
    creditDays: numv(j.creditDays, 30),
    address: optStr(j.address),
    gstNo: optStr(j.gstNo),
    futureDue: numv(j.futureDue),
    ageing: {
      age0_30: numv(ageing.age0_30),
      age31_60: numv(ageing.age31_60),
      age61_90: numv(ageing.age61_90),
      age90Plus: numv(ageing.age90Plus),
    },
    escalationLevel: (str(j.escalationLevel, "none") || "none") as EscalationLevel,
    ownerMappingRequired: Boolean(j.ownerMappingRequired),
    hasValidNextAction: j.hasValidNextAction == null ? true : Boolean(j.hasValidNextAction),
    creditHealthScore: optNum(j.creditHealthScore),
    creditHealthComponents: (j.creditHealthComponents as Record<string, number> | undefined) ?? null,
    disputedAmount: numv(j.disputedAmount),
    branch: str(j.branch, "Turning Point") || "Turning Point",
    noAnswerAttempts: numv(j.noAnswerAttempts),
    updatedAt: date(j.updatedAt),
    financialFreshness: date(j.financialFreshness),
  };
}

export type CreditBand = "Low Risk" | "Moderate" | "High" | "Critical" | "Insufficient History";

export function creditHealthBand(score: number | null): CreditBand {
  if (score == null) return "Insufficient History";
  if (score >= 85) return "Low Risk";
  if (score >= 70) return "Moderate";
  if (score >= 50) return "High";
  return "Critical";
}

// ── Task ───────────────────────────────────────────────────────────────

export const TASK_TYPES = [
  "customerCall",
  "physicalVisit",
  "disputeResolution",
  "documentFollowUp",
  "financialTeamFollowUp",
  "customerDetailCorrection",
  "paymentVerification",
  "managementInstruction",
] as const;
export type TaskType = (typeof TASK_TYPES)[number];

export type TaskStatus = "pending" | "inProgress" | "completed" | "completedAwaitingVerification" | "closed";

export const TASK_TYPE_LABEL: Record<TaskType, string> = {
  customerCall: "Customer Call",
  physicalVisit: "Physical Visit",
  disputeResolution: "Dispute Resolution",
  documentFollowUp: "Document Follow-Up",
  financialTeamFollowUp: "Internal Action",
  customerDetailCorrection: "Customer Detail Correction",
  paymentVerification: "Payment Verification",
  managementInstruction: "Management Instruction",
};

export type Task = {
  id: string;
  type: TaskType;
  customerId: string;
  customerName: string;
  ownerId: string;
  deadline: Date;
  priority: string;
  reason: string;
  status: TaskStatus;
  outcome: string | null;
  approvalStatus: string | null;
  pendingReason: string | null;
  pendingDeadline: Date | null;
  pendingPriority: string | null;
  source: string;
  isRoutine: boolean;
  completedAt: Date | null;
  createdAt: Date;
  reviewedByRE: boolean;
  note: string | null;
  attachmentPath: string | null;
  disputeId: string | null;
};

export function parseTask(j: Json, customerName?: string): Task {
  const deadline = new Date(j.deadline as string);
  return {
    id: str(j.id),
    type: str(j.type) as TaskType,
    customerId: str(j.customerId),
    customerName: customerName ?? str(j.customerId),
    ownerId: str(j.ownerId),
    deadline,
    priority: str(j.priority, "Normal") || "Normal",
    reason: str(j.reason),
    status: str(j.status) as TaskStatus,
    outcome: optStr(j.outcome),
    approvalStatus: optStr(j.approvalStatus),
    pendingReason: optStr(j.pendingReason),
    pendingDeadline: date(j.pendingDeadline),
    pendingPriority: optStr(j.pendingPriority),
    source: str(j.source, "System") || "System",
    isRoutine: j.isRoutine == null ? true : Boolean(j.isRoutine),
    completedAt: date(j.completedAt),
    createdAt: date(j.createdAt) ?? deadline,
    reviewedByRE: Boolean(j.reviewedByRE),
    note: optStr(j.note),
    attachmentPath: optStr(j.attachmentPath),
    disputeId: optStr(j.disputeId),
  };
}

export const isTaskOpen = (t: Task) => t.status !== "completed" && t.status !== "closed";
export const isTaskOverdue = (t: Task, now = new Date()) => isTaskOpen(t) && t.deadline < now;

export function friendlyTaskReason(reason: string) {
  return reason === "Non-response threshold reached"
    ? "No answer on 3 attempts — a Physical Visit is required now."
    : reason;
}

// ── PTP ────────────────────────────────────────────────────────────────

export type PtpStatus =
  | "scheduled"
  | "pendingVerification"
  | "kept"
  | "partiallyKept"
  | "broken"
  | "financialSyncPending";

export const PTP_STATUS_LABEL: Record<PtpStatus, string> = {
  scheduled: "Scheduled",
  pendingVerification: "Awaiting Reconciliation",
  kept: "Kept",
  partiallyKept: "Partially Kept",
  broken: "Broken",
  financialSyncPending: "Financial Sync Pending",
};

export type Ptp = {
  id: string;
  customerId: string;
  amountPromised: number;
  promiseDate: Date;
  paymentMode: string;
  status: PtpStatus;
  amountReceived: number | null;
  advanceAmount: number | null;
  correctionRequestedAmount: number | null;
  correctionRequestedDate: Date | null;
  correctionRequestedPaymentMode: string | null;
  correctionReason: string | null;
  correctionStatus: string;
  brokenReason: string | null;
};

export function parsePtp(j: Json): Ptp {
  return {
    id: str(j.id),
    customerId: str(j.customerId),
    amountPromised: numv(j.amountPromised),
    promiseDate: new Date(j.promiseDate as string),
    paymentMode: str(j.paymentMode),
    status: str(j.status) as PtpStatus,
    amountReceived: optNum(j.amountReceived),
    advanceAmount: optNum(j.advanceAmount),
    correctionRequestedAmount: optNum(j.correctionRequestedAmount),
    correctionRequestedDate: date(j.correctionRequestedDate),
    correctionRequestedPaymentMode: optStr(j.correctionRequestedPaymentMode),
    correctionReason: optStr(j.correctionReason),
    correctionStatus: str(j.correctionStatus, "none") || "none",
    brokenReason: optStr(j.brokenReason),
  };
}

// ── Dispute ────────────────────────────────────────────────────────────

export type DisputeMessage = {
  authorName: string;
  authorRole: string;
  kind: string;
  body: string;
  attachmentPath: string | null;
  createdAt: Date;
};

export type Dispute = {
  id: string;
  customerId: string;
  amount: number;
  totalDueAtRaise: number;
  reason: string;
  status: string;
  statusDetail: string | null;
  invoiceNumber: string | null;
  priority: string | null;
  resolutionOwner: string | null;
  rejectionReason: string | null;
  infoRequestNote: string | null;
  attachmentPath: string | null;
  messages: DisputeMessage[];
  raisedDate: Date;
  lastUpdated: Date;
  deadline: Date | null;
  department: string | null;
};

export function parseDispute(j: Json): Dispute {
  return {
    id: str(j.id),
    customerId: str(j.customerId),
    amount: numv(j.amount),
    totalDueAtRaise: numv(j.totalDueAtRaise),
    reason: str(j.reason),
    status: str(j.status),
    statusDetail: optStr(j.statusDetail),
    invoiceNumber: optStr(j.invoiceNumber),
    priority: optStr(j.priority),
    resolutionOwner: optStr(j.resolutionOwner),
    rejectionReason: optStr(j.rejectionReason),
    infoRequestNote: optStr(j.infoRequestNote),
    attachmentPath: optStr(j.attachmentPath),
    messages: ((j.messages as Json[] | undefined) ?? []).map((m) => ({
      authorName: str(m.authorName),
      authorRole: str(m.authorRole),
      kind: str(m.kind),
      body: str(m.body),
      attachmentPath: optStr(m.attachmentPath),
      createdAt: new Date(m.createdAt as string),
    })),
    raisedDate: new Date(j.raisedDate as string),
    lastUpdated: new Date(j.lastUpdated as string),
    deadline: date(j.resolutionDeadline),
    department: optStr(j.department),
  };
}

/** Statuses where the RE must act now — a fresh claim, or an owner's resolution to verify (AppStore.disputeNeedsReActionStatuses). */
export const DISPUTE_NEEDS_RE_ACTION = new Set(["Pending Approval", "Awaiting Verification"]);

// ── Payment claim ──────────────────────────────────────────────────────

export type PaymentClaim = {
  id: string;
  customerId: string;
  amount: number;
  claimDate: Date;
  reference: string | null;
  status: string;
  attachmentPath: string | null;
};

export function parsePaymentClaim(j: Json): PaymentClaim {
  return {
    id: str(j.id),
    customerId: str(j.customerId),
    amount: numv(j.amount),
    claimDate: new Date(j.claimDate as string),
    reference: optStr(j.reference),
    status: str(j.status),
    attachmentPath: optStr(j.attachmentPath),
  };
}

export const isClaimPending = (c: PaymentClaim) =>
  c.status === "Awaiting Verification" || c.status === "Sync Pending";

// ── Escalation ─────────────────────────────────────────────────────────

export type Escalation = {
  id: string;
  customerId: string;
  level: "L1" | "L2" | "L3" | "L4";
  reason: string;
  plan: string;
  ownerId: string;
  deadline: Date;
  createdAt: Date;
  resolvedAt: Date | null;
  moneyAtRisk: number;
  cause: string | null;
  isOpen: boolean;
};

export function parseEscalation(j: Json): Escalation {
  const createdAt = new Date(j.createdAt as string);
  const isOpen = Boolean(j.isOpen);
  return {
    id: str(j.id),
    customerId: str(j.customerId),
    level: str(j.level) as Escalation["level"],
    reason: str(j.reason),
    plan: str(j.plan),
    ownerId: str(j.ownerId),
    deadline: date(j.deadline) ?? createdAt,
    createdAt,
    resolvedAt: isOpen ? null : date(j.updatedAt),
    moneyAtRisk: numv(j.moneyAtRisk),
    cause: optStr(j.cause),
    isOpen,
  };
}

// ── Notification ───────────────────────────────────────────────────────

export type NotificationSeverity = "info" | "actionRequired" | "warning" | "critical";

export type NotificationItem = {
  id: string;
  severity: NotificationSeverity;
  title: string;
  body: string;
  customerId: string | null;
  timestamp: Date;
  read: boolean;
};

export function parseNotification(j: Json): NotificationItem {
  return {
    id: str(j.id),
    severity: str(j.severity, "info") as NotificationSeverity,
    title: str(j.title),
    body: str(j.body),
    customerId: optStr(j.customerId),
    timestamp: new Date(j.createdAt as string),
    read: Boolean(j.isRead),
  };
}

// ── Salesman (server-computed roster, salesmanService.js) ──────────────

export type Salesman = {
  id: string;
  username: string;
  fullName: string;
  branch: string;
  phone: string | null;
  recoveryScore: number;
  recoveryScoreComponents: Record<string, number> | null;
  customers: number;
  totalOverdue: number;
  brokenPtps: number;
  overdueTasks: number;
  expectedCollection: number;
  dueTodayPtps: number;
  ptpKeptPercent: number;
  collectionTarget: number;
  collectionAchieved: number;
  collectionAchievedPercent: number;
  taskCompletionRate: number;
  validNextActionRate: number;
  escalatedCustomers: number;
  highRiskCustomers: number;
  underperformanceDismissedThisMonth: boolean;
};

export function parseSalesman(j: Json): Salesman {
  return {
    id: str(j.id),
    username: str(j.username),
    fullName: str(j.fullName) || str(j.id),
    branch: str(j.branch, "Turning Point") || "Turning Point",
    phone: optStr(j.phone),
    recoveryScore: numv(j.recoveryScore, 75),
    recoveryScoreComponents: (j.recoveryScoreComponents as Record<string, number> | undefined) ?? null,
    customers: numv(j.customers),
    totalOverdue: numv(j.totalOverdue),
    brokenPtps: numv(j.brokenPtps),
    overdueTasks: numv(j.overdueTasks),
    expectedCollection: numv(j.expectedCollection),
    dueTodayPtps: numv(j.dueTodayPtps),
    ptpKeptPercent: numv(j.ptpKeptPercent),
    collectionTarget: numv(j.collectionTarget),
    collectionAchieved: numv(j.collectionAchieved),
    collectionAchievedPercent: numv(j.collectionAchievedPercent),
    taskCompletionRate: numv(j.taskCompletionRate),
    validNextActionRate: numv(j.validNextActionRate),
    escalatedCustomers: numv(j.escalatedCustomers),
    highRiskCustomers: numv(j.highRiskCustomers),
    underperformanceDismissedThisMonth: Boolean(j.underperformanceDismissedThisMonth),
  };
}

// ── Dashboard report (reportService.getDashboard) ──────────────────────

export type DashboardReport = {
  totalOverdueAmount?: number;
  totalOverdueCustomerCount?: number;
  dueTodayPtpAmount?: number;
  dueTodayPtpCount?: number;
  overdueCustomersCount?: number;
  overdueCustomersAmount?: number;
  ptpKeptMtdPercent?: number;
  recoveryTarget?: number;
  outstandingAgeingBuckets?: Record<string, number>;
  topOverdueCustomers?: Json[];
  customers30PlusOverdueCount?: number;
  disputeOverviewByStatus?: Record<string, { count: number; amount: number }>;
  totalDisputesCount?: number;
  totalDisputesAmount?: number;
  ptpOverviewStats?: Record<string, number>;
  noFollowUpAccounts?: Json[];
  physicalVisitsPendingReviewCount?: number;
  disputesAwaitingReviewCount?: number;
  pendingTaskExtensionCount?: number;
  ptpCorrectionRequestsCount?: number;
  needsAttentionBadgeCount?: number;
  totalReceivedAllTime?: number;
  todaysCollectedAmount?: number;
  todaysCollectedCustomerCount?: number;
  companyCollectionTargetToday?: number;
  companyCollectionAchievedTodayPercent?: number;
  moneyAtRisk?: number;
};

export type TrendPoint = {
  date: string;
  avgRecoveryScore?: number;
  ptpAmountTotal?: number;
  brokenPtpCount?: number;
  collectionExpected?: number;
  collectionActual?: number;
  noFollowUpCount?: number;
};

export type SyncStatus = {
  syncing: boolean;
  since: string | null;
  lastSync: {
    status: "inProgress" | "success" | "failed" | "stalled";
    finishedAt: string | null;
    startedAt: string | null;
    message: string | null;
    failedBranches: string[];
  } | null;
};
