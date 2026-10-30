import { describe, expect, it } from "vitest";
import { parseCustomer, parsePtp, parseTask, parseDispute, parsePaymentClaim, parseEscalation, parseSalesman } from "./models";
import { ALL_BRANCHES, buildView, EMPTY_DATA, isSystemClosed, reviewDeadline, type RmsData } from "./selectors";

const NOW = new Date("2026-10-20T12:00:00+05:30");
const RE = "re-1";

const cust = (id: string, extra: Record<string, unknown> = {}) =>
  parseCustomer({ id, name: `Cust ${id}`, totalOutstanding: 1000, totalDue: 500, branch: "Vapi", assignedSalesmanId: "s1", oldestOverdueDays: 10, ...extra });
const task = (id: string, extra: Record<string, unknown> = {}) =>
  parseTask({ id, type: "customerCall", customerId: "c1", ownerId: "s1", deadline: "2026-10-21T18:00:00+05:30", reason: "r", status: "pending", source: "System", createdAt: "2026-10-19T10:00:00+05:30", ...extra });
const ptp = (id: string, extra: Record<string, unknown> = {}) =>
  parsePtp({ id, customerId: "c1", amountPromised: 300, promiseDate: "2026-10-20T10:00:00+05:30", paymentMode: "Cash", status: "scheduled", ...extra });

function data(over: Partial<RmsData>): RmsData {
  return {
    ...EMPTY_DATA,
    salesmen: [parseSalesman({ id: "s1", fullName: "Ravi Patel", branch: "Vapi", collectionAchievedPercent: 80 })],
    ...over,
  };
}

describe("branch filter", () => {
  it("keeps server figures for All Branches and recomputes for a branch", () => {
    const d = data({
      customers: [cust("c1"), cust("c2", { branch: "Surat", totalDue: 900 })],
      dashboard: { totalOverdueAmount: 12345, totalOverdueCustomerCount: 7 },
    });
    const all = buildView(d, ALL_BRANCHES, RE, NOW);
    expect(all.totalOverdueAmount).toBe(12345);
    expect(all.totalOverdueCustomerCount).toBe(7);

    const surat = buildView(d, "Surat", RE, NOW);
    expect(surat.customers.map((c) => c.id)).toEqual(["c2"]);
    expect(surat.totalOverdueAmount).toBe(900);
    expect(surat.totalOverdueCustomerCount).toBe(1);
  });

  it("scopes PTPs, disputes and claims through their customer's branch", () => {
    const d = data({
      customers: [cust("c1"), cust("c2", { branch: "Surat" })],
      ptps: [ptp("p1"), ptp("p2", { customerId: "c2" })],
      disputes: [parseDispute({ id: "d1", customerId: "c2", amount: 10, totalDueAtRaise: 20, reason: "x", status: "Pending Approval", raisedDate: NOW.toISOString(), lastUpdated: NOW.toISOString() })],
      paymentClaims: [parsePaymentClaim({ id: "pc1", customerId: "c1", amount: 5, claimDate: NOW.toISOString(), status: "Awaiting Verification" })],
    });
    const v = buildView(d, "Vapi", RE, NOW);
    expect(v.ptps.map((p) => p.id)).toEqual(["p1"]);
    expect(v.disputes).toHaveLength(0);
    expect(v.pendingPaymentClaims).toHaveLength(1);
  });
});

describe("unified RE task queue", () => {
  it("hides a salesman's own follow-up until it is overdue", () => {
    const d = data({
      customers: [cust("c1")],
      tasks: [
        task("future", { source: "Record Outcome", deadline: "2026-10-21T18:00:00+05:30" }),
        task("late", { source: "Record Outcome", deadline: "2026-10-19T18:00:00+05:30" }),
        task("mgmt", { type: "managementInstruction", source: "RE" }),
      ],
    });
    const ids = buildView(d, ALL_BRANCHES, RE, NOW).buildReTaskItems().map((i) => i.refId);
    expect(ids).toContain("late");
    expect(ids).toContain("mgmt");
    expect(ids).not.toContain("future");
  });

  it("surfaces a broken PTP only when nothing else handles it", () => {
    const base = { customers: [cust("c1")], ptps: [ptp("p1", { status: "broken" })] };
    const bare = buildView(data(base), ALL_BRANCHES, RE, NOW).buildReTaskItems();
    expect(bare.some((i) => i.kind === "ptpMissed")).toBe(true);

    const withTask = buildView(data({ ...base, tasks: [task("t1", { type: "managementInstruction" })] }), ALL_BRANCHES, RE, NOW).buildReTaskItems();
    expect(withTask.some((i) => i.kind === "ptpMissed")).toBe(false);

    const escalated = buildView(
      data({ ...base, escalations: [parseEscalation({ id: "e1", customerId: "c1", level: "L2", reason: "x", isOpen: true, moneyAtRisk: 1, createdAt: NOW.toISOString() })] }),
      ALL_BRANCHES,
      RE,
      NOW,
    ).buildReTaskItems();
    expect(escalated.some((i) => i.kind === "ptpMissed")).toBe(false);
  });

  it("gives salesman-raised items a 9 PM review deadline", () => {
    expect(reviewDeadline(new Date("2026-10-20T09:15:00")).getHours()).toBe(21);
  });

  it("recognises system-closed outcomes", () => {
    expect(isSystemClosed("Auto-closed — customer paid")).toBe(true);
    expect(isSystemClosed("Superseded by RE")).toBe(true);
    expect(isSystemClosed("Called, will pay Friday")).toBe(false);
  });
});

describe("recovery queue (CompanyRecoveryQueueScreen._priorityRank)", () => {
  it("ranks L4 > broken PTP > owner mapping > no next action > L2/L3 > PTP > 30+ days, ties in server order", () => {
    const d = data({
      customers: [
        cust("plain", { oldestOverdueDays: 5 }),
        cust("old", { oldestOverdueDays: 45 }),
        cust("ptp", { primaryNextAction: "PTP Follow-up" }),
        cust("l2", { escalationLevel: "L2" }),
        cust("nonext", { hasValidNextAction: false }),
        cust("owner", { ownerMappingRequired: true }),
        cust("broken"),
        cust("l4", { escalationLevel: "L4" }),
        cust("paid", { totalDue: 0 }),
      ],
      ptps: [ptp("p1", { customerId: "broken", status: "broken" })],
    });
    const v = buildView(d, ALL_BRANCHES, RE, NOW);
    expect(v.recoveryQueue().map((r) => r.customer.id)).toEqual(["l4", "broken", "owner", "nonext", "l2", "ptp", "old", "plain"]);
    // Total Outstanding card opens the same screen over outstanding > 0.
    expect(v.recoveryQueue("outstanding").map((r) => r.customer.id)).toContain("paid");
  });
});

describe("dashboard stat cards (ControlDashboardScreen)", () => {
  it("splits scheduled PTPs into Total PTPs / Today's Overdue / Expected Today", () => {
    const d = data({
      customers: [cust("c1")],
      ptps: [
        ptp("today", { promiseDate: "2026-10-20T16:00:00+05:30" }),
        ptp("past", { promiseDate: "2026-10-18T10:00:00+05:30" }),
        ptp("future", { promiseDate: "2026-10-25T10:00:00+05:30" }),
        ptp("verifying", { promiseDate: "2026-10-20T09:00:00+05:30", status: "pendingVerification" }),
      ],
    });
    const v = buildView(d, ALL_BRANCHES, RE, NOW);
    expect(v.scheduledPtps.map((p) => p.id).sort()).toEqual(["future", "past", "today"]);
    expect(v.overduePtps.map((p) => p.id)).toEqual(["past"]);
    expect(v.dueTodayPtps.map((p) => p.id).sort()).toEqual(["today", "verifying"]);
  });
});

describe("5 PM control", () => {
  it("matches AppStore.runFivePmControl rules", () => {
    const d = data({
      customers: [cust("c1", { hasValidNextAction: false }), cust("c2", { ownerMappingRequired: true, totalDue: 700 })],
      tasks: [task("t1", { deadline: "2026-10-19T18:00:00+05:30", priority: "Critical" })],
      ptps: [ptp("p1", { status: "broken" })],
      escalations: [parseEscalation({ id: "e1", customerId: "c1", level: "L3", reason: "x", plan: "", isOpen: true, moneyAtRisk: 1, createdAt: NOW.toISOString() })],
    });
    const s = buildView(d, ALL_BRANCHES, RE, NOW).fivePmControl();
    expect(s.overdueTasks).toHaveLength(1);
    expect(s.mandatoryNotDone).toHaveLength(1);
    expect(s.brokenNoNext).toHaveLength(1);
    expect(s.ownerlessExposure).toBe(700);
    expect(s.l3NoPlan).toHaveLength(1);
  });
});

describe("My Tasks vs Approvals (no item on two pages)", () => {
  it("keeps disputes, promise changes and payment claims out of My Tasks", () => {
    const d = data({
      customers: [cust("c1")],
      tasks: [task("t1", { type: "managementInstruction" })],
      ptps: [ptp("p1", { correctionStatus: "Pending" })],
      disputes: [parseDispute({ id: "d1", customerId: "c1", amount: 10, totalDueAtRaise: 20, reason: "x", status: "Pending Approval", raisedDate: NOW.toISOString(), lastUpdated: NOW.toISOString() })],
      paymentClaims: [parsePaymentClaim({ id: "pc1", customerId: "c1", amount: 5, claimDate: NOW.toISOString(), status: "Awaiting Verification" })],
    });
    const v = buildView(d, ALL_BRANCHES, RE, NOW);
    expect(v.buildReTaskItems().map((i) => i.kind).sort()).toEqual(["dispute", "paymentClaim", "ptpCorrection", "realTask"]);
    expect(v.buildWorkItems().map((i) => i.kind)).toEqual(["realTask"]);
    expect(v.workOpenCount).toBe(1);
    expect(v.approvalInboxCount).toBe(2); // disputes are on the Disputes page only
    expect(v.disputesNeedingAction).toHaveLength(1);
  });
});

describe("next step (same as the app's task screen)", () => {
  // SURESH SUTHAR.(R), 30 Oct: the PTP broke, the server opened a new call
  // task but left reasonForAction at the old "PTP of ₹50,000 …" text.
  const stale = cust("c1", { name: "SURESH SUTHAR.(R)", primaryNextAction: "CALL CUSTOMER", reasonForAction: "PTP of ₹50000.0 via Phone Call. Contact: SURESH SUTHAR.(R)" });

  it("uses the open task, never the stale stored reason", () => {
    const t = task("t1", { reason: "Call SURESH SUTHAR.(R) — promise broken, nothing received. Collect ₹1,36,832, record a new outcome.", priority: "High" });
    const step = buildView(data({ customers: [stale], tasks: [t] }), ALL_BRANCHES, RE, NOW).nextStepFor(stale);
    expect(step.task?.id).toBe("t1");
    expect(step.what).toBe("Call SURESH SUTHAR.(R)");
    expect(step.why).toBe("Customer promised to pay, but the payment did not come.");
    expect(step.amount).toBe("₹1,36,832");
    expect(step.why).not.toContain("50000");
  });

  it("picks the earliest-due open task and ignores finished ones", () => {
    const done = task("old", { reason: "Overdue still open.", status: "completed", deadline: "2026-10-19T18:00:00+05:30" });
    const later = task("later", { reason: "Keep calling.", deadline: "2026-10-25T18:00:00+05:30" });
    const sooner = task("sooner", { reason: "Call X — promise broken, nothing received. Collect ₹10, record a new outcome.", deadline: "2026-10-21T18:00:00+05:30" });
    const step = buildView(data({ customers: [stale], tasks: [done, later, sooner] }), ALL_BRANCHES, RE, NOW).nextStepFor(stale);
    expect(step.task?.id).toBe("sooner");
  });

  it("falls back to the stored next action only when no task is open", () => {
    const step = buildView(data({ customers: [stale] }), ALL_BRANCHES, RE, NOW).nextStepFor(stale);
    expect(step.task).toBeNull();
    expect(step.what).toBe("CALL CUSTOMER");
  });
});
