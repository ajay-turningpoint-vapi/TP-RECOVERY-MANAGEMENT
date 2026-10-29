/**
 * Line-for-line ports of the RE report calculations in
 * lib/v3/screens/report_detail_screens.dart, so every web report shows
 * the same figures as the mobile report with the same filters. Where the
 * mobile formula has a quirk, it is kept on purpose (and noted) — the RE
 * uses both apps and the numbers must agree.
 */
import type { Customer, Dispute, PaymentClaim, Ptp, Salesman, Task, TrendPoint } from "./models";
import type { RmsView } from "./selectors";

export const ALL_SALESMEN = "All Salesmen";
export const DATE_RANGES = ["Today", "This Week", "This Month", "This Quarter", "All Time"] as const;
export type DateRange = (typeof DATE_RANGES)[number];

export type ReportFilters = { branch: string; salesman: string; dateRange: DateRange };

const DAY = 86_400_000;
/** Dart `Duration.inDays` truncates toward zero. */
const inDays = (ms: number) => Math.trunc(ms / DAY);
export const sameDay = (a: Date, b: Date) =>
  a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
const sum = <T,>(l: T[], f: (x: T) => number) => l.reduce((s, x) => s + f(x), 0);

/** ReportFilters.matchesDate */
export function matchesDate(f: ReportFilters, d: Date, now = new Date()) {
  switch (f.dateRange) {
    case "Today":
      return sameDay(d, now);
    case "This Week":
      return Math.abs(inDays(+d - +now)) <= 7;
    case "This Month":
      return d.getFullYear() === now.getFullYear() && d.getMonth() === now.getMonth();
    case "This Quarter":
      return Math.abs(inDays(+d - +now)) <= 90;
    default:
      return true;
  }
}

/** ReportFilters.matchesCustomer */
export const matchesCustomer = (f: ReportFilters, c: Customer) =>
  (f.branch === "All Branches" || c.branch === f.branch) && (f.salesman === ALL_SALESMEN || c.assignedSalesmanId === f.salesman);

const matchesSalesman = (f: ReportFilters, s: Salesman) =>
  (f.branch === "All Branches" || s.branch === f.branch) && (f.salesman === ALL_SALESMEN || s.id === f.salesman);

const isMatured = (p: Ptp) => p.status !== "scheduled" && p.status !== "pendingVerification" && p.status !== "financialSyncPending";
const isKeptish = (p: Ptp) => p.status === "kept" || p.status === "partiallyKept";

type Ctx = {
  customers: Customer[]; // store.customers (all branches — reports apply their own branch filter)
  ptps: Ptp[]; // store.ptps
  tasks: Task[]; // store.tasks
  disputes: Dispute[]; // store.disputes
  salesmen: Salesman[]; // store.salesmen
  claims: PaymentClaim[];
  brokenPtps: Ptp[]; // store.brokenPtps — branch-scoped by the global filter, as on mobile
  noValidNextAction: Customer[]; // store.noValidNextActionCustomers — branch-scoped
  noFollowUpAccounts: Customer[]; // store.noFollowUpAccounts
  daysSinceLastFollowUp: (c: Customer) => number;
  trends: TrendPoint[];
  now: Date;
};

export function reportCtx(rms: RmsView, trends: TrendPoint[], now = new Date()): Ctx {
  return {
    customers: rms.allCustomers,
    ptps: rms.allPtps,
    tasks: rms.allTasks,
    disputes: rms.allDisputes,
    salesmen: rms.allSalesmen,
    claims: rms.allPaymentClaims,
    brokenPtps: rms.brokenPtps,
    noValidNextAction: rms.noValidNextAction,
    noFollowUpAccounts: rms.noFollowUpAccounts,
    daysSinceLastFollowUp: rms.daysSinceLastFollowUp,
    trends,
    now,
  };
}

const ownedIds = (x: Ctx, salesmanId: string) =>
  new Set(x.customers.filter((c) => c.assignedSalesmanId === salesmanId).map((c) => c.id));

// ── helpers shared by several mobile reports ───────────────────────────

/** _collectedFor */
const collectedFor = (x: Ctx, id: string) => {
  const ids = ownedIds(x, id);
  return sum(x.ptps.filter((p) => ids.has(p.customerId) && isKeptish(p)), (p) => p.amountReceived ?? 0);
};

/** _brokenRateFor */
const brokenRateFor = (x: Ctx, id: string) => {
  const ids = ownedIds(x, id);
  const matured = x.ptps.filter((p) => ids.has(p.customerId) && isMatured(p));
  return matured.length ? (matured.filter((p) => p.status === "broken").length / matured.length) * 100 : 0;
};

export function performanceBand(score: number) {
  if (score >= 80) return "Excellent";
  if (score >= 60) return "Good";
  if (score >= 40) return "Average";
  if (score >= 20) return "Below Average";
  return "Poor";
}

export function ptpBand(pct: number) {
  if (pct >= 80) return "Excellent";
  if (pct >= 65) return "Good";
  if (pct >= 50) return "Average";
  if (pct >= 30) return "At Risk";
  return "Critical";
}

export function brokenBand(pct: number) {
  if (pct < 10) return "Good";
  if (pct < 18) return "Average";
  if (pct < 24) return "At Risk";
  return "Critical";
}

export function efficiencyBand(pct: number) {
  if (pct >= 85) return "Excellent";
  if (pct >= 70) return "Good";
  if (pct >= 50) return "Average";
  if (pct >= 30) return "Below Average";
  return "Poor";
}

export function followUpPriority(days: number) {
  if (days >= 15) return "Critical";
  if (days >= 11) return "High";
  if (days >= 7) return "Medium";
  return "Low";
}

export const HIGH_VALUE_THRESHOLD = 200_000; // kHighValueThreshold

// ── 1. Daily Recovery Summary ──────────────────────────────────────────

export function dailyRecovery(x: Ctx, f: ReportFilters) {
  const salesmenAll = x.salesmen.filter((s) => matchesSalesman(f, s)).sort((a, b) => b.collectionAchieved - a.collectionAchieved);
  const salesmenWithOverdue = salesmenAll.filter((s) => s.totalOverdue > 0);
  const totalTarget = sum(salesmenAll, (s) => s.collectionTarget);
  const names = new Set(salesmenAll.map((s) => s.id));
  const todaysVisits = x.tasks.filter((t) => t.type === "physicalVisit" && names.has(t.ownerId) && sameDay(t.deadline, x.now)).length;
  const owned = new Set(x.customers.filter((c) => names.has(c.assignedSalesmanId)).map((c) => c.id));
  const totalCollected = sum(
    x.ptps.filter((p) => owned.has(p.customerId) && isKeptish(p) && sameDay(p.promiseDate, x.now)),
    (p) => p.amountReceived ?? 0,
  );
  const pendingAmount = Math.max(0, totalTarget - totalCollected);
  const collectionPercent = totalTarget <= 0 ? 0 : Math.min(999, Math.max(0, (totalCollected / totalTarget) * 100));
  return {
    totalTarget,
    totalCollected,
    pendingAmount,
    todaysVisits,
    collectionPercent,
    trend: x.trends.map((t) => ({ date: t.date, amount: t.collectionActual ?? 0 })),
    salesmen: salesmenWithOverdue,
  };
}

// ── 2. Salesman Performance ────────────────────────────────────────────

export function salesmanPerformance(x: Ctx, f: ReportFilters) {
  const salesmen = x.salesmen.filter((s) => matchesSalesman(f, s));
  const branchCount = new Set(salesmen.map((s) => s.branch)).size;
  const avgScore = salesmen.length ? sum(salesmen, (s) => s.recoveryScore) / salesmen.length : 0;
  const sorted = [...salesmen].sort((a, b) => b.recoveryScore - a.recoveryScore);
  const totalCollected = sum(salesmen, (s) => collectedFor(x, s.id));
  const ids = new Set(salesmen.map((s) => s.id));
  const byId = new Map(x.customers.map((c) => [c.id, c]));
  const companyMatured = x.ptps.filter((p) => {
    const c = byId.get(p.customerId);
    return c != null && ids.has(c.assignedSalesmanId) && isMatured(p);
  });
  const companyBroken = companyMatured.filter((p) => p.status === "broken").length;
  const noFollowUp = x.noValidNextAction.filter((c) => ids.has(c.assignedSalesmanId));
  const bands = ["Excellent", "Good", "Average", "Below Average", "Poor"] as const;
  return {
    salesmenCount: salesmen.length,
    branchCount,
    avgScore,
    top: sorted[0] ?? null,
    totalCollected,
    maturedCount: companyMatured.length,
    companyBroken,
    brokenRate: companyMatured.length ? (companyBroken / companyMatured.length) * 100 : 0,
    noFollowUpAmount: sum(noFollowUp, (c) => c.totalDue),
    noFollowUpCount: noFollowUp.length,
    bands: bands.map((b) => ({ band: b, count: salesmen.filter((s) => performanceBand(s.recoveryScore) === b).length })),
    trend: x.trends.map((t) => ({ date: t.date, score: t.avgRecoveryScore ?? 0 })),
    rows: sorted.map((s) => ({
      salesman: s,
      band: performanceBand(s.recoveryScore),
      collected: collectedFor(x, s.id),
      followUpDiscipline: s.recoveryScoreComponents?.followUpDiscipline ?? 0,
      brokenRate: brokenRateFor(x, s.id),
      noFollowUp: x.noValidNextAction.filter((c) => c.assignedSalesmanId === s.id).length,
      // Mobile reads Customer.agingBuckets['>60'], which the app never
      // populates from the API — so this column is always ₹0 on mobile too.
      aging60: 0,
    })),
  };
}

// ── 3. PTP Report ──────────────────────────────────────────────────────

export function ptpReport(x: Ctx, f: ReportFilters) {
  const byId = new Map(x.customers.map((c) => [c.id, c]));
  const ptps = x.ptps.filter((p) => {
    const c = byId.get(p.customerId);
    return c != null && matchesCustomer(f, c) && matchesDate(f, p.promiseDate, x.now);
  });
  const dueToday = (p: Ptp) => p.status === "pendingVerification" || (p.status === "scheduled" && sameDay(p.promiseDate, x.now));
  const buckets: [string, Ptp[]][] = [
    ["Kept", ptps.filter((p) => p.status === "kept")],
    ["Partially Kept", ptps.filter((p) => p.status === "partiallyKept")],
    ["Due Today", ptps.filter(dueToday)],
    ["Upcoming", ptps.filter((p) => p.status === "scheduled" && p.promiseDate > x.now && !sameDay(p.promiseDate, x.now))],
    ["Broken", ptps.filter((p) => p.status === "broken")],
    ["Financial Sync Pending", ptps.filter((p) => p.status === "financialSyncPending")],
  ];
  const get = (k: string) => buckets.find((b) => b[0] === k)![1];
  const matured = ptps.filter(isMatured);
  const dueTodayItems = get("Due Today");
  const rows = x.salesmen
    .filter((s) => matchesSalesman(f, s))
    .map((s) => {
      const ids = ownedIds(x, s.id);
      const mine = ptps.filter((p) => ids.has(p.customerId));
      const mineMatured = mine.filter(isMatured);
      const keptPct = mineMatured.length ? (mineMatured.filter((p) => p.status === "kept").length / mineMatured.length) * 100 : 0;
      const brokenPct = mineMatured.length ? (mineMatured.filter((p) => p.status === "broken").length / mineMatured.length) * 100 : 0;
      return {
        salesman: s,
        active: sum(mine.filter((p) => p.status === "scheduled" || p.status === "pendingVerification"), (p) => p.amountPromised),
        dueToday: sum(mine.filter(dueToday), (p) => p.amountPromised),
        keptPct,
        brokenPct,
        band: ptpBand(keptPct),
      };
    })
    .sort((a, b) => b.keptPct - a.keptPct);
  return {
    totalCount: ptps.length,
    totalAmount: sum(ptps, (p) => p.amountPromised),
    dueTodayAmount: sum(dueTodayItems, (p) => p.amountPromised),
    dueTodayAccounts: new Set(dueTodayItems.map((p) => p.customerId)).size,
    keptRate: matured.length ? (get("Kept").length / matured.length) * 100 : 0,
    brokenRate: matured.length ? (get("Broken").length / matured.length) * 100 : 0,
    buckets: buckets.map(([name, list]) => ({ name, count: list.length, amount: sum(list, (p) => p.amountPromised) })),
    trend: x.trends.map((t) => ({ date: t.date, amount: t.ptpAmountTotal ?? 0 })),
    rows,
  };
}

// ── 4. Broken PTP Report ───────────────────────────────────────────────

export function brokenCustomerBucket(c: Customer) {
  if (c.escalationLevel === "L4") return "Management Attention";
  if (c.currentRecoveryState === "RE Control") return "Under RE Control";
  if (c.escalationLevel === "L3") return "Third+ Broken";
  if (c.escalationLevel === "L2") return "Second Broken";
  return "First Broken";
}

export function brokenPtpReport(x: Ctx, f: ReportFilters) {
  const byId = new Map(x.customers.map((c) => [c.id, c]));
  const items = x.brokenPtps.filter((p) => {
    const c = byId.get(p.customerId);
    return c != null && matchesCustomer(f, c) && matchesDate(f, p.promiseDate, x.now);
  });
  const byCustomer = new Map<string, Ptp[]>();
  for (const p of items) byCustomer.set(p.customerId, [...(byCustomer.get(p.customerId) ?? []), p]);
  const brokenCustomers = [...byCustomer.keys()].map((id) => byId.get(id)).filter((c): c is Customer => !!c);
  const bucketNames = ["First Broken", "Second Broken", "Third+ Broken", "Under RE Control", "Management Attention"];
  const rows = x.salesmen
    .filter((s) => matchesSalesman(f, s))
    .map((s) => {
      const ids = ownedIds(x, s.id);
      const mineBroken = items.filter((p) => ids.has(p.customerId));
      const mineMatured = x.ptps.filter((p) => ids.has(p.customerId) && isMatured(p) && matchesDate(f, p.promiseDate, x.now));
      const brokenPct = mineMatured.length ? (mineBroken.length / mineMatured.length) * 100 : 0;
      return { salesman: s, brokenCount: mineBroken.length, brokenAmount: sum(mineBroken, (p) => p.amountPromised), brokenPct, band: brokenBand(brokenPct) };
    })
    .sort((a, b) => b.brokenAmount - a.brokenAmount);
  return {
    count: items.length,
    totalAmount: sum(items, (p) => p.amountPromised),
    brokenToday: sum(items.filter((p) => sameDay(p.promiseDate, x.now)), (p) => p.amountPromised),
    repeatBrokenAccounts: [...byCustomer.values()].filter((l) => l.length >= 2).length,
    reControlCount: brokenCustomers.filter((c) => c.currentRecoveryState === "RE Control" && c.escalationLevel !== "L4").length,
    managementAttentionCount: brokenCustomers.filter((c) => c.escalationLevel === "L4").length,
    buckets: bucketNames.map((name) => {
      const list = brokenCustomers.filter((c) => brokenCustomerBucket(c) === name);
      return { name, count: list.length, customers: list };
    }),
    brokenCustomerCount: brokenCustomers.length,
    trend: x.trends.map((t) => ({ date: t.date, count: t.brokenPtpCount ?? 0 })),
    rows,
    items,
  };
}

// ── 5. Dispute Status Report ───────────────────────────────────────────

/** _disputeBucket (the report's own mapping — Auto-Closed counts as Rejected here). */
export function disputeReportBucket(status: string) {
  switch (status) {
    case "Pending Approval":
      return "Awaiting Review";
    case "Approved":
    case "In Resolution":
    case "Awaiting Verification":
    case "Need More Information":
      return "In Progress";
    case "Resolved":
      return "Resolved";
    case "Rejected":
    case "Returned to Recovery":
    case "Auto-Closed":
      return "Rejected";
    default:
      return "Awaiting Review";
  }
}

export function disputeReasonCategory(reason: string) {
  const r = reason.toLowerCase();
  if (r.includes("wrong") || r.includes("damage")) return "Goods Issue";
  if (r.includes("quantity") || r.includes("shortage") || r.includes("short delivery")) return "Short Delivery";
  if (r.includes("rate") || r.includes("discrepancy")) return "Rate Discrepancy";
  if (r.includes("freight")) return "Freight Charge";
  if (r.includes("invoice") || r.includes("credit") || r.includes("reflected")) return "Invoice Issue";
  return "Others";
}

export function disputeReport(x: Ctx, f: ReportFilters) {
  const byId = new Map(x.customers.map((c) => [c.id, c]));
  const disputes = x.disputes
    .filter((d) => {
      const c = byId.get(d.customerId);
      return c != null && matchesCustomer(f, c) && matchesDate(f, d.raisedDate, x.now);
    })
    .sort((a, b) => +b.raisedDate - +a.raisedDate);
  const group = (key: (d: Dispute) => string, order?: string[]) => {
    const m = new Map<string, Dispute[]>();
    for (const k of order ?? []) m.set(k, []);
    for (const d of disputes) m.set(key(d), [...(m.get(key(d)) ?? []), d]);
    return [...m].map(([name, list]) => ({ name, count: list.length, amount: sum(list, (d) => d.amount) }));
  };
  const ageBucket = (d: Dispute) => {
    const days = inDays(+x.now - +d.raisedDate);
    return days <= 7 ? "0-7 Days" : days <= 15 ? "8-15 Days" : days <= 30 ? "16-30 Days" : days <= 60 ? "31-60 Days" : "60+ Days";
  };
  return {
    disputes,
    totalAmount: sum(disputes, (d) => d.amount),
    buckets: group((d) => disputeReportBucket(d.status), ["Awaiting Review", "In Progress", "Resolved", "Rejected"]),
    byReason: group((d) => disputeReasonCategory(d.reason)).sort((a, b) => b.count - a.count),
    ageing: group(ageBucket, ["0-7 Days", "8-15 Days", "16-30 Days", "31-60 Days", "60+ Days"]),
  };
}

// ── 6. Ageing Receivables ──────────────────────────────────────────────

export const AGEING_REPORT_BUCKETS = ["Not Due", "0 - 30 Days", "31 - 60 Days", "61 - 90 Days", "90+ Days"] as const;

export function ageingReport(x: Ctx, f: ReportFilters) {
  const customers = x.customers.filter((c) => matchesCustomer(f, c));
  const rows: { customer: Customer; bucket: string; amount: number }[] = [];
  for (const c of customers) {
    const add = (bucket: string, amount: number) => amount > 0 && rows.push({ customer: c, bucket, amount });
    add("Not Due", c.futureDue);
    add("0 - 30 Days", c.ageing.age0_30);
    add("31 - 60 Days", c.ageing.age31_60);
    add("61 - 90 Days", c.ageing.age61_90);
    add("90+ Days", c.ageing.age90Plus);
  }
  rows.sort((a, b) => b.amount - a.amount);
  const total = sum(rows, (r) => r.amount);
  return {
    rows,
    total,
    customersWithDue: customers.filter((c) => c.totalDue > 0).length,
    buckets: AGEING_REPORT_BUCKETS.map((b) => {
      const amt = sum(rows.filter((r) => r.bucket === b), (r) => r.amount);
      return { name: b, amount: amt, pct: total === 0 ? 0 : (amt / total) * 100 };
    }),
  };
}

// ── 7. Expected vs Actual Collection ───────────────────────────────────

export function expectedVsActual(x: Ctx, f: ReportFilters) {
  const byId = new Map(x.customers.map((c) => [c.id, c]));
  const matured = x.ptps
    .filter((p) => {
      const c = byId.get(p.customerId);
      return c != null && matchesCustomer(f, c) && matchesDate(f, p.promiseDate, x.now) && isMatured(p);
    })
    .sort((a, b) => +b.promiseDate - +a.promiseDate);
  const expected = sum(matured, (p) => p.amountPromised);
  const actual = sum(matured, (p) => p.amountReceived ?? 0);
  const outcomes: [string, Ptp[]][] = [
    ["Fully Kept", matured.filter((p) => p.status === "kept")],
    ["Partially Kept", matured.filter((p) => p.status === "partiallyKept")],
    ["Broken", matured.filter((p) => p.status === "broken")],
  ];
  const rows = x.salesmen
    .filter((s) => matchesSalesman(f, s))
    .map((s) => {
      const ids = ownedIds(x, s.id);
      const mine = matured.filter((p) => ids.has(p.customerId));
      const e = sum(mine, (p) => p.amountPromised);
      const a = sum(mine, (p) => p.amountReceived ?? 0);
      const efficiency = e === 0 ? 0 : (a / e) * 100;
      return { salesman: s, expected: e, actual: a, efficiency, band: efficiencyBand(efficiency) };
    })
    .sort((a, b) => b.efficiency - a.efficiency);
  return {
    matured,
    expected,
    actual,
    gap: Math.max(0, expected - actual),
    pct: expected === 0 ? 0 : (actual / expected) * 100,
    fullyUncollected: outcomes[2][1].length,
    outcomes: outcomes.map(([name, list]) => ({ name, count: list.length, amount: sum(list, (p) => p.amountPromised) })),
    trend: x.trends.map((t) => ({ date: t.date, expected: t.collectionExpected ?? 0, actual: t.collectionActual ?? 0 })),
    rows,
  };
}

// ── 8. Recovery Target vs Actual ───────────────────────────────────────

export const RECOVERY_TARGET_TIERS = [
  { label: "Tier 1", pct: 0.25 },
  { label: "Tier 2", pct: 0.35 },
  { label: "Tier 3", pct: 0.5 },
  { label: "Tier 4", pct: 0.7 },
];

export function recoveryTarget(x: Ctx, f: ReportFilters) {
  const scoped = x.customers.filter((c) => matchesCustomer(f, c));
  const totalOverdue = sum(scoped, (c) => c.totalDue);
  const ids = new Set(scoped.map((c) => c.id));
  const actualRecovery = sum(x.ptps.filter((p) => isKeptish(p) && ids.has(p.customerId)), (p) => p.amountReceived ?? 0);
  const tiers = RECOVERY_TARGET_TIERS.map((t) => {
    const target = totalOverdue * t.pct;
    return { ...t, target, achievement: target <= 0 ? null : (actualRecovery / target) * 100, delta: actualRecovery - target };
  });
  const tier1 = tiers[0];
  return { totalOverdue, actualRecovery, tiers, tier1, onTrack: tier1.achievement != null && tier1.achievement >= 100 };
}

// ── 9. No Follow-Up Accounts ───────────────────────────────────────────

export function noFollowUp(x: Ctx, f: ReportFilters) {
  const days = x.daysSinceLastFollowUp;
  const items = x.noFollowUpAccounts.filter((c) => matchesCustomer(f, c)).sort((a, b) => days(b) - days(a));
  const priorities = ["Critical", "High", "Medium", "Low"] as const;
  const salesmanRows = x.salesmen
    .filter((s) => matchesSalesman(f, s))
    .map((s) => {
      const accounts = items.filter((c) => c.assignedSalesmanId === s.id);
      return { salesman: s, accounts: accounts.length, amount: sum(accounts, (c) => c.totalDue) };
    })
    .filter((r) => r.accounts > 0)
    .sort((a, b) => b.accounts - a.accounts);
  return {
    items,
    outstandingAtRisk: sum(items, (c) => c.totalDue),
    highValueCount: items.filter((c) => c.totalDue >= HIGH_VALUE_THRESHOLD).length,
    salesmenInvolved: new Set(items.map((c) => c.assignedSalesmanId).filter(Boolean)).size,
    avgDays: items.length ? sum(items, days) / items.length : 0,
    criticalCount: items.filter((c) => days(c) >= 15).length,
    priorities: priorities.map((p) => ({ name: p, count: items.filter((c) => followUpPriority(days(c)) === p).length })),
    trend: x.trends.map((t) => ({ date: t.date, count: t.noFollowUpCount ?? 0 })),
    salesmanRows,
  };
}
