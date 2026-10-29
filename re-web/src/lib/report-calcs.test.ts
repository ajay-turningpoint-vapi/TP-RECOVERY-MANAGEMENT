import { describe, expect, it } from "vitest";
import { parseCustomer, parseDispute, parsePtp, parseSalesman } from "./models";
import {
  ALL_SALESMEN,
  disputeReport,
  matchesDate,
  ptpReport,
  recoveryTarget,
  type ReportFilters,
} from "./report-calcs";

const NOW = new Date("2026-10-20T12:00:00+05:30");
const all: ReportFilters = { branch: "All Branches", salesman: ALL_SALESMEN, dateRange: "All Time" };
const customers = [
  parseCustomer({ id: "c1", name: "A", branch: "Vapi", assignedSalesmanId: "s1", totalDue: 1000 }),
  parseCustomer({ id: "c2", name: "B", branch: "Surat", assignedSalesmanId: "s2", totalDue: 3000 }),
];
const salesmen = [parseSalesman({ id: "s1", fullName: "One", branch: "Vapi" }), parseSalesman({ id: "s2", fullName: "Two", branch: "Surat" })];
const ptp = (id: string, extra: Record<string, unknown>) =>
  parsePtp({ id, customerId: "c1", amountPromised: 100, promiseDate: NOW.toISOString(), paymentMode: "Cash", status: "scheduled", ...extra });

function ctx(over: Record<string, unknown> = {}) {
  return {
    customers,
    ptps: [],
    tasks: [],
    disputes: [],
    salesmen,
    claims: [],
    brokenPtps: [],
    noValidNextAction: [],
    noFollowUpAccounts: [],
    daysSinceLastFollowUp: () => 0,
    trends: [],
    now: NOW,
    ...over,
  } as Parameters<typeof ptpReport>[0];
}

describe("ReportFilters.matchesDate", () => {
  it("follows the Dart rules", () => {
    const f = (dateRange: ReportFilters["dateRange"]) => ({ ...all, dateRange });
    expect(matchesDate(f("This Month"), new Date("2026-10-01T00:00:00+05:30"), NOW)).toBe(true);
    expect(matchesDate(f("This Month"), new Date("2026-09-30T12:00:00+05:30"), NOW)).toBe(false);
    expect(matchesDate(f("This Week"), new Date("2026-10-27T11:00:00+05:30"), NOW)).toBe(true); // 6.96 days → 6
    expect(matchesDate(f("This Week"), new Date("2026-10-28T13:00:00+05:30"), NOW)).toBe(false);
  });
});

describe("PTP report", () => {
  it("rates kept/broken over matured PTPs only", () => {
    const r = ptpReport(
      ctx({ ptps: [ptp("k", { status: "kept" }), ptp("b", { status: "broken" }), ptp("b2", { status: "broken" }), ptp("s", {})] }),
      all,
    );
    expect(r.totalCount).toBe(4);
    expect(r.keptRate).toBeCloseTo(33.33, 1);
    expect(r.brokenRate).toBeCloseTo(66.67, 1);
    expect(r.buckets.find((b) => b.name === "Due Today")!.count).toBe(1);
  });
});

describe("Dispute report", () => {
  it("counts Auto-Closed under Rejected (report mapping)", () => {
    const d = (id: string, status: string) =>
      parseDispute({ id, customerId: "c1", amount: 10, totalDueAtRaise: 10, reason: "rate discrepancy", status, raisedDate: NOW.toISOString(), lastUpdated: NOW.toISOString() });
    const r = disputeReport(ctx({ disputes: [d("1", "Auto-Closed"), d("2", "Pending Approval")] }), all);
    expect(r.buckets.find((b) => b.name === "Rejected")!.count).toBe(1);
    expect(r.byReason[0].name).toBe("Rate Discrepancy");
  });
});

describe("Recovery target", () => {
  it("uses 25% of scoped overdue and kept receipts", () => {
    const r = recoveryTarget(ctx({ ptps: [ptp("k", { status: "kept", amountReceived: 500 })] }), { ...all, branch: "Vapi" });
    expect(r.totalOverdue).toBe(1000);
    expect(r.tier1.target).toBe(250);
    expect(r.tier1.achievement).toBe(200);
    expect(r.onTrack).toBe(true);
  });
});
