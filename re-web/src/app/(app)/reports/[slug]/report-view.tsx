"use client";

import Link from "next/link";
import { useMemo, type ReactNode } from "react";
import { useRouter } from "next/navigation";
import { format } from "date-fns";
import type { ColumnDef } from "@tanstack/react-table";
import { ArrowLeft } from "lucide-react";
import { Bar, BarChart, CartesianGrid, Line, LineChart, XAxis, YAxis } from "recharts";
import { DataTable } from "@/components/app/data-table";
import { PageHeader } from "@/components/app/page-header";
import { SimpleSelect } from "@/components/app/simple-select";
import { DisputeStatusBadge, Pill } from "@/components/app/status";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import {
  ChartContainer,
  ChartLegend,
  ChartLegendContent,
  ChartTooltip,
  ChartTooltipContent,
  type ChartConfig,
} from "@/components/ui/chart";
import { formatDate, formatINR, formatINRCompact } from "@/lib/format";
import type { Customer, Dispute, Ptp } from "@/lib/models";
import { useRms, useTrends } from "@/lib/queries";
import {
  ALL_SALESMEN,
  DATE_RANGES,
  ageingReport,
  brokenPtpReport,
  dailyRecovery,
  disputeReasonCategory,
  disputeReport,
  disputeReportBucket,
  expectedVsActual,
  followUpPriority,
  noFollowUp,
  ptpReport,
  recoveryTarget,
  reportCtx,
  salesmanPerformance,
  type DateRange,
  type ReportFilters,
} from "@/lib/report-calcs";
import { useUrlState } from "@/lib/use-url-state";
import { cn } from "@/lib/utils";
import { REPORTS, type ReportSlug } from "../catalog";

/* eslint-disable @typescript-eslint/no-explicit-any -- each table has its own row type */

type Ctx = ReturnType<typeof reportCtx>;

/** Reports that have a date-range filter on mobile (default "This Month"). */
const DATED: ReportSlug[] = ["ptp", "broken-ptp", "dispute-status", "expected-vs-actual"];

const right = { align: "right" as const };
const money = (v: unknown) => formatINR(v as number);
const pct1 = (v: number) => `${v.toFixed(1)}%`;
const label = (d: string) => format(new Date(d), "dd MMM");

export function ReportView({ slug }: { slug: ReportSlug }) {
  const rms = useRms();
  const trends = useTrends();
  const router = useRouter();
  const meta = REPORTS.find((r) => r.slug === slug)!;

  // Same defaults as mobile: branch = the global branch filter, all salesmen, This Month.
  const [branch, setBranch] = useUrlState("branch", rms.branch);
  const [salesman, setSalesman] = useUrlState("salesman", ALL_SALESMEN);
  const [dateRange, setDateRange] = useUrlState("range", "This Month");
  const filters: ReportFilters = { branch, salesman, dateRange: (DATED.includes(slug) ? dateRange : "All Time") as DateRange };

  const ctx = useMemo(() => reportCtx(rms, trends.data ?? []), [rms, trends.data]);
  const toCustomer = (id: string) => router.push(`/customers/${encodeURIComponent(id)}`);
  const toSalesman = (id: string) => router.push(`/salesmen/${encodeURIComponent(id)}`);

  const salesmanOptions = [
    { value: ALL_SALESMEN, label: "All Salesmen" },
    ...rms.allSalesmen.filter((s) => branch === "All Branches" || s.branch === branch).map((s) => ({ value: s.id, label: s.fullName })),
  ];

  return (
    <div className="mx-auto max-w-[1600px] space-y-5">
      <Button variant="ghost" size="sm" className="-ml-2 text-muted-foreground" render={<Link href="/reports" />}>
        <ArrowLeft /> Reports
      </Button>
      <PageHeader
        title={meta.title}
        description={meta.description}
        actions={
          <div className="flex flex-wrap gap-2">
            {DATED.includes(slug) && <SimpleSelect value={dateRange} onChange={setDateRange} options={[...DATE_RANGES]} aria-label="Date range" />}
            <SimpleSelect
              value={branch}
              onChange={(v) => {
                setBranch(v);
                setSalesman(ALL_SALESMEN);
              }}
              options={rms.branchOptions}
              aria-label="Branch"
            />
            <SimpleSelect value={salesman} onChange={setSalesman} options={salesmanOptions} aria-label="Salesman" className="min-w-44" />
          </div>
        }
      />
      <Body slug={slug} ctx={ctx} filters={filters} toCustomer={toCustomer} toSalesman={toSalesman} loading={rms.isLoading} />
      <p className="text-xs text-muted-foreground">Figures use the same formulas and filters as the mobile report.</p>
    </div>
  );
}

function Body({
  slug,
  ctx,
  filters,
  toCustomer,
  toSalesman,
  loading,
}: {
  slug: ReportSlug;
  ctx: Ctx;
  filters: ReportFilters;
  toCustomer: (id: string) => void;
  toSalesman: (id: string) => void;
  loading: boolean;
}) {
  const bandCol: ColumnDef<any, any> = {
    id: "band",
    header: "Band",
    accessorFn: (x: any) => x.band,
    cell: ({ getValue }) => <Pill tone={bandTone(getValue() as string)}>{getValue() as string}</Pill>,
  };
  const salesmanCols: ColumnDef<any, any>[] = [
    { id: "name", header: "Salesman", accessorFn: (x: any) => x.salesman.fullName, cell: Bold },
    { id: "branch", header: "Branch", accessorFn: (x: any) => x.salesman.branch },
  ];

  switch (slug) {
    case "daily-recovery": {
      const r = dailyRecovery(ctx, filters);
      return (
        <>
          <Tiles
            items={[
              ["Total Target", formatINR(r.totalTarget)],
              ["Total Collected", formatINR(r.totalCollected)],
              ["Pending Amount", formatINR(r.pendingAmount)],
              ["Today's Visits", r.todaysVisits],
              ["Collection %", pct1(r.collectionPercent)],
            ]}
          />
          <ChartCard title="Collection Trend">
            <Bars data={r.trend.map((t) => ({ x: label(t.date), y: t.amount }))} name="Collected" />
          </ChartCard>
          <Table
            title={`Top Salesmen Performance · ${r.salesmen.length} Salesmen`}
            rows={r.salesmen}
            loading={loading}
            onRow={(s) => toSalesman(s.id)}
            search={(s) => s.fullName}
            columns={[
              { id: "name", header: "Salesman", accessorFn: (s: any) => s.fullName, cell: Bold },
              { id: "target", header: "Target", accessorFn: (s: any) => s.collectionTarget, cell: ({ getValue }) => money(getValue()), meta: right },
              { id: "collected", header: "Collected", accessorFn: (s: any) => s.collectionAchieved, cell: ({ getValue }) => money(getValue()), meta: right },
              {
                id: "pct",
                header: "Achieved",
                accessorFn: (s: any) => s.collectionAchievedPercent,
                cell: ({ getValue }) => <PctPill v={getValue() as number} />,
                meta: right,
              },
            ]}
          />
        </>
      );
    }

    case "salesman-performance": {
      const r = salesmanPerformance(ctx, filters);
      return (
        <>
          <Tiles
            items={[
              ["Total Salesmen Evaluated", r.salesmenCount, `Across ${r.branchCount} Branches`],
              ["Average Recovery Score", `${r.avgScore.toFixed(2)}%`, "Weighted Performance Index"],
              ["Top Performer Score", r.top ? `${r.top.recoveryScore}%` : "-", r.top ? `${r.top.fullName} · ${r.top.branch}` : "-"],
              ["Total Collection Achieved", formatINR(r.totalCollected), `${r.maturedCount} matured PTPs`],
              ["Broken PTP Rate", `${r.brokenRate.toFixed(2)}%`, `${r.companyBroken} of ${r.maturedCount} matured`],
              ["No Follow-Up Accounts", formatINR(r.noFollowUpAmount), `${r.noFollowUpCount} customers`],
            ]}
          />
          <div className="grid gap-4 lg:grid-cols-3">
            <ChartCard title="Recovery Score Trend" className="lg:col-span-2">
              <Lines data={r.trend.map((t) => ({ x: label(t.date), a: t.score }))} series={{ a: "Avg score" }} percent />
            </ChartCard>
            <Breakdown title="Performance Distribution" total={r.salesmenCount} rows={r.bands.map((b) => ({ name: b.band, count: b.count }))} />
          </div>
          <Table
            title="Salesman Performance Summary"
            rows={r.rows}
            loading={loading}
            onRow={(row) => toSalesman(row.salesman.id)}
            search={(row) => row.salesman.fullName}
            columns={[
              ...salesmanCols,
              bandCol,
              { id: "score", header: "Recovery Score", accessorFn: (x: any) => x.salesman.recoveryScore, cell: ({ getValue }) => `${getValue()}%`, meta: right },
              { id: "collected", header: "Collection Achieved", accessorFn: (x: any) => x.collected, cell: ({ getValue }) => money(getValue()), meta: right },
              { id: "followUp", header: "Follow-Up Discipline", accessorFn: (x: any) => x.followUpDiscipline, cell: ({ getValue }) => pct1(getValue() as number), meta: right },
              { id: "broken", header: "Broken PTP Rate", accessorFn: (x: any) => x.brokenRate, cell: ({ getValue }) => <span className="text-destructive">{pct1(getValue() as number)}</span>, meta: right },
              { id: "noFollow", header: "No Follow-Up Accounts", accessorFn: (x: any) => x.noFollowUp, meta: right },
              { id: "aging60", header: "Aging > 60 Days", accessorFn: (x: any) => x.aging60, cell: ({ getValue }) => money(getValue()), meta: right },
            ]}
          />
        </>
      );
    }

    case "ptp": {
      const r = ptpReport(ctx, filters);
      return (
        <>
          <Tiles
            items={[
              ["Total PTPs", r.totalCount],
              ["PTP Amount", formatINR(r.totalAmount)],
              ["PTP Due Today", formatINR(r.dueTodayAmount)],
              ["Kept PTP Rate", pct1(r.keptRate)],
              ["Broken PTP Rate", pct1(r.brokenRate)],
              ["Due Today Accounts", r.dueTodayAccounts],
            ]}
          />
          <div className="grid gap-4 lg:grid-cols-3">
            <ChartCard title="PTP Trend" className="lg:col-span-2">
              <Bars data={r.trend.map((t) => ({ x: label(t.date), y: t.amount }))} name="PTP amount" />
            </ChartCard>
            <Breakdown title="PTP Status Distribution" total={r.totalCount} rows={r.buckets} />
          </div>
          <Table
            title="Salesman PTP Summary"
            rows={r.rows}
            loading={loading}
            onRow={(row) => toSalesman(row.salesman.id)}
            search={(row) => row.salesman.fullName}
            columns={[
              ...salesmanCols,
              bandCol,
              { id: "active", header: "Active PTP", accessorFn: (x: any) => x.active, cell: ({ getValue }) => money(getValue()), meta: right },
              { id: "dueToday", header: "Due Today", accessorFn: (x: any) => x.dueToday, cell: ({ getValue }) => money(getValue()), meta: right },
              { id: "kept", header: "Kept %", accessorFn: (x: any) => x.keptPct, cell: ({ getValue }) => pct1(getValue() as number), meta: right },
              { id: "broken", header: "Broken %", accessorFn: (x: any) => x.brokenPct, cell: ({ getValue }) => pct1(getValue() as number), meta: right },
            ]}
          />
        </>
      );
    }

    case "broken-ptp": {
      const r = brokenPtpReport(ctx, filters);
      return (
        <>
          <Tiles
            items={[
              ["Total Broken PTPs", r.count],
              ["Broken PTP Amount", formatINR(r.totalAmount)],
              ["Broken Today", formatINR(r.brokenToday)],
              ["Repeat Broken Accounts", r.repeatBrokenAccounts],
              ["Recovery Executive Control", r.reControlCount],
              ["Management Attention", r.managementAttentionCount],
            ]}
          />
          <div className="grid gap-4 lg:grid-cols-3">
            <ChartCard title="Broken PTP Trend" className="lg:col-span-2">
              <Bars data={r.trend.map((t) => ({ x: label(t.date), y: t.count }))} name="Broken PTPs" count />
            </ChartCard>
            <Breakdown title="Broken PTP Status Distribution" total={r.brokenCustomerCount} rows={r.buckets} />
          </div>
          <Table
            title="Salesman Broken PTP Summary"
            rows={r.rows}
            loading={loading}
            onRow={(row) => toSalesman(row.salesman.id)}
            search={(row) => row.salesman.fullName}
            columns={[
              ...salesmanCols,
              bandCol,
              { id: "count", header: "Broken PTPs", accessorFn: (x: any) => x.brokenCount, meta: right },
              { id: "amount", header: "Broken Amount", accessorFn: (x: any) => x.brokenAmount, cell: ({ getValue }) => <span className="text-destructive">{money(getValue())}</span>, meta: right },
              { id: "pct", header: "Broken %", accessorFn: (x: any) => x.brokenPct, cell: ({ getValue }) => pct1(getValue() as number), meta: right },
            ]}
          />
          <Table
            title={`Broken PTPs · ${r.items.length}`}
            rows={r.items}
            loading={loading}
            onRow={(p: Ptp) => toCustomer(p.customerId)}
            search={(p: Ptp) => ctxName(ctx, p.customerId)}
            columns={[
              { id: "customer", header: "Customer", accessorFn: (p: any) => ctxName(ctx, p.customerId), cell: Bold },
              { id: "amount", header: "Promised", accessorFn: (p: any) => p.amountPromised, cell: ({ getValue }) => money(getValue()), meta: right },
              { id: "date", header: "Promise date", accessorFn: (p: any) => +p.promiseDate, cell: ({ row }) => formatDate(row.original.promiseDate), meta: { csv: (p: any) => formatDate(p.promiseDate) } },
              { id: "reason", header: "Reason", accessorFn: (p: any) => p.brokenReason ?? "" },
            ]}
          />
        </>
      );
    }

    case "dispute-status": {
      const r = disputeReport(ctx, filters);
      return (
        <>
          <Tiles
            items={[
              ["Total Disputes", r.disputes.length, formatINR(r.totalAmount)],
              ...r.buckets.map((b) => [b.name, b.count, formatINR(b.amount)] as [string, number, string]),
            ]}
          />
          <div className="grid gap-4 lg:grid-cols-3">
            <Breakdown title="Disputes by Status" total={r.disputes.length} rows={r.buckets} />
            <Breakdown title="Disputes by Reason" total={r.disputes.length} rows={r.byReason} />
            <Breakdown title="Disputes Aging" total={r.disputes.length} rows={r.ageing} />
          </div>
          <Table
            title="Dispute Status Details"
            rows={r.disputes}
            loading={loading}
            onRow={(d: Dispute) => toCustomer(d.customerId)}
            search={(d: Dispute) => ctxName(ctx, d.customerId)}
            columns={[
              { id: "customer", header: "Customer", accessorFn: (d: any) => ctxName(ctx, d.customerId), cell: Bold },
              { id: "invoice", header: "Invoice", accessorFn: (d: any) => d.invoiceNumber ?? "" },
              { id: "amount", header: "Amount", accessorFn: (d: any) => d.amount, cell: ({ getValue }) => money(getValue()), meta: right },
              { id: "bucket", header: "Stage", accessorFn: (d: any) => disputeReportBucket(d.status) },
              { id: "status", header: "Status", accessorFn: (d: any) => d.status, cell: ({ getValue }) => <DisputeStatusBadge status={getValue() as string} /> },
              { id: "reason", header: "Reason", accessorFn: (d: any) => disputeReasonCategory(d.reason) },
              { id: "raised", header: "Raised", accessorFn: (d: any) => +d.raisedDate, cell: ({ row }) => formatDate(row.original.raisedDate), meta: { csv: (d: any) => formatDate(d.raisedDate) } },
            ]}
          />
        </>
      );
    }

    case "ageing": {
      const r = ageingReport(ctx, filters);
      return (
        <>
          <Tiles
            items={[
              ["Total Outstanding", formatINR(r.total), `From ${r.customersWithDue} Customers`],
              ...r.buckets.map((b) => [b.name, formatINR(b.amount), `${b.pct.toFixed(1)}%`] as [string, string, string]),
            ]}
          />
          <ChartCard title="Ageing Summary" note="From the current BUSY ageing.">
            <Bars data={r.buckets.map((b) => ({ x: b.name, y: b.amount }))} name="Amount" />
          </ChartCard>
          <Table
            title={`Ageing Receivables Details · ${r.rows.length} Records`}
            rows={r.rows}
            loading={loading}
            onRow={(row) => toCustomer(row.customer.id)}
            search={(row) => row.customer.name}
            columns={[
              { id: "customer", header: "Customer", accessorFn: (x: any) => x.customer.name, cell: Bold },
              { id: "salesman", header: "Salesman", accessorFn: (x: any) => ctxSalesman(ctx, x.customer.assignedSalesmanId) },
              { id: "bucket", header: "Bucket", accessorFn: (x: any) => x.bucket },
              { id: "amount", header: "Amount", accessorFn: (x: any) => x.amount, cell: ({ getValue }) => money(getValue()), meta: right },
            ]}
          />
        </>
      );
    }

    case "expected-vs-actual": {
      const r = expectedVsActual(ctx, filters);
      return (
        <>
          <Tiles
            items={[
              ["Matured PTPs", r.matured.length],
              ["Expected (Committed)", formatINR(r.expected)],
              ["Actual (Received)", formatINR(r.actual)],
              ["Shortfall", formatINR(r.gap)],
              ["Collection Efficiency", pct1(r.pct)],
              ["Fully Uncollected", r.fullyUncollected],
            ]}
          />
          <div className="grid gap-4 lg:grid-cols-3">
            <ChartCard title="Collection Trend" className="lg:col-span-2">
              <Lines data={r.trend.map((t) => ({ x: label(t.date), a: t.expected, b: t.actual }))} series={{ a: "Expected", b: "Actual" }} />
            </ChartCard>
            <Breakdown title="Outcome Distribution" total={r.matured.length} rows={r.outcomes} />
          </div>
          <Table
            title="Salesman Collection Summary"
            rows={r.rows}
            loading={loading}
            onRow={(row) => toSalesman(row.salesman.id)}
            search={(row) => row.salesman.fullName}
            columns={[
              ...salesmanCols,
              bandCol,
              { id: "expected", header: "Expected", accessorFn: (x: any) => x.expected, cell: ({ getValue }) => money(getValue()), meta: right },
              { id: "actual", header: "Actual", accessorFn: (x: any) => x.actual, cell: ({ getValue }) => money(getValue()), meta: right },
              { id: "eff", header: "Efficiency", accessorFn: (x: any) => x.efficiency, cell: ({ getValue }) => pct1(getValue() as number), meta: right },
            ]}
          />
          <Table
            title={`Collection Details · ${r.matured.length} PTPs`}
            rows={r.matured}
            loading={loading}
            onRow={(p: Ptp) => toCustomer(p.customerId)}
            search={(p: Ptp) => ctxName(ctx, p.customerId)}
            columns={[
              { id: "customer", header: "Customer", accessorFn: (p: any) => ctxName(ctx, p.customerId), cell: Bold },
              { id: "date", header: "Promise date", accessorFn: (p: any) => +p.promiseDate, cell: ({ row }) => formatDate(row.original.promiseDate), meta: { csv: (p: any) => formatDate(p.promiseDate) } },
              { id: "promised", header: "Promised", accessorFn: (p: any) => p.amountPromised, cell: ({ getValue }) => money(getValue()), meta: right },
              { id: "received", header: "Received", accessorFn: (p: any) => p.amountReceived ?? 0, cell: ({ getValue }) => money(getValue()), meta: right },
              { id: "status", header: "Outcome", accessorFn: (p: any) => (p.status === "kept" ? "Fully Kept" : p.status === "partiallyKept" ? "Partially Kept" : "Broken") },
            ]}
          />
        </>
      );
    }

    case "recovery-target": {
      const r = recoveryTarget(ctx, filters);
      return (
        <>
          <Tiles
            items={[
              ["Total Overdue", formatINR(r.totalOverdue)],
              ["Actual Recovery", formatINR(r.actualRecovery)],
              ["Target (Tier 1 · 25%)", formatINR(r.tier1.target)],
              ["Achievement", r.tier1.achievement == null ? "—" : `${r.tier1.achievement.toFixed(2)}%`],
              ["Status", r.onTrack ? "On Track" : "Behind"],
            ]}
          />
          <Table
            title="Tier Comparison"
            rows={r.tiers}
            loading={loading}
            columns={[
              { id: "tier", header: "Tier", accessorFn: (t: any) => `${t.label} · ${Math.round(t.pct * 100)}%`, cell: Bold },
              { id: "target", header: "Target", accessorFn: (t: any) => t.target, cell: ({ getValue }) => money(getValue()), meta: right },
              {
                id: "ach",
                header: "Achievement",
                accessorFn: (t: any) => t.achievement ?? -1,
                cell: ({ row }) => (row.original.achievement == null ? "—" : `${row.original.achievement.toFixed(2)}%`),
                meta: right,
              },
              {
                id: "delta",
                header: "Ahead / Behind",
                accessorFn: (t: any) => t.delta,
                cell: ({ getValue }) => <span className={cn((getValue() as number) < 0 ? "text-destructive" : "text-success")}>{money(getValue())}</span>,
                meta: right,
              },
            ]}
          />
        </>
      );
    }

    case "no-follow-up": {
      const r = noFollowUp(ctx, filters);
      return (
        <>
          <Tiles
            items={[
              ["Total No Follow-Up Accounts", r.items.length],
              ["Outstanding at Risk", formatINR(r.outstandingAtRisk)],
              ["High Value Accounts", r.highValueCount],
              ["Salesmen Involved", r.salesmenInvolved],
              ["Avg Days Since Last Follow-Up", `${r.avgDays.toFixed(1)} Days`],
              ["Critical Accounts (15+ Days)", r.criticalCount],
            ]}
          />
          <div className="grid gap-4 lg:grid-cols-3">
            <ChartCard title="No Follow-Up Trend" className="lg:col-span-2">
              <Bars data={r.trend.map((t) => ({ x: label(t.date), y: t.count }))} name="Accounts" count />
            </ChartCard>
            <Breakdown title="Priority Summary" total={r.items.length} rows={r.priorities} />
          </div>
          <Table
            title={`No Follow-Up Account List · ${r.items.length} Accounts`}
            rows={r.items}
            loading={loading}
            onRow={(c: Customer) => toCustomer(c.id)}
            search={(c: Customer) => c.name}
            columns={[
              { id: "customer", header: "Customer", accessorFn: (c: any) => c.name, cell: Bold },
              { id: "salesman", header: "Salesman", accessorFn: (c: any) => ctxSalesman(ctx, c.assignedSalesmanId) },
              { id: "days", header: "Days Since Last Follow-Up", accessorFn: (c: any) => ctx.daysSinceLastFollowUp(c), meta: right },
              {
                id: "priority",
                header: "Priority",
                accessorFn: (c: any) => followUpPriority(ctx.daysSinceLastFollowUp(c)),
                cell: ({ getValue }) => <Pill tone={bandTone(getValue() as string)}>{getValue() as string}</Pill>,
              },
              { id: "due", header: "Overdue", accessorFn: (c: any) => c.totalDue, cell: ({ getValue }) => money(getValue()), meta: right },
            ]}
          />
          <Table
            title="Salesman No Follow-Up Summary"
            rows={r.salesmanRows}
            loading={loading}
            onRow={(row) => toSalesman(row.salesman.id)}
            columns={[
              { id: "name", header: "Salesman", accessorFn: (x: any) => x.salesman.fullName, cell: Bold },
              { id: "accounts", header: "Accounts", accessorFn: (x: any) => x.accounts, meta: right },
              { id: "amount", header: "Overdue", accessorFn: (x: any) => x.amount, cell: ({ getValue }) => money(getValue()), meta: right },
            ]}
          />
        </>
      );
    }
  }
}

// ── presentation helpers ───────────────────────────────────────────────

const ctxName = (ctx: Ctx, id: string) => ctx.customers.find((c) => c.id === id)?.name ?? id;
const ctxSalesman = (ctx: Ctx, id: string) => (id ? (ctx.salesmen.find((s) => s.id === id)?.fullName ?? id) : "Unmapped");

const Bold = ({ getValue }: { getValue: () => unknown }) => <span className="font-medium">{getValue() as string}</span>;

function bandTone(band: string): "success" | "info" | "warning" | "danger" | "neutral" {
  if (band === "Excellent" || band === "Low") return "success";
  if (band === "Good") return "info";
  if (band === "Average" || band === "Medium" || band === "Below Average" || band === "At Risk" || band === "High") return "warning";
  if (band === "Poor" || band === "Critical") return "danger";
  return "neutral";
}

/** Same colour steps as the mobile Daily Recovery salesman rows (100 / 60 / 30). */
function PctPill({ v }: { v: number }) {
  const tone = v >= 100 ? "success" : v >= 60 ? "info" : v >= 30 ? "warning" : "danger";
  return <Pill tone={tone}>{v}%</Pill>;
}

function Tiles({ items }: { items: [string, ReactNode, ReactNode?][] }) {
  return (
    <div className="grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-6">
      {items.map(([k, v, sub]) => (
        <div key={k} className="rounded-xl border bg-card p-4 shadow-xs">
          <div className="text-xs text-muted-foreground">{k}</div>
          <div className="mt-1 text-xl font-semibold tabular">{v}</div>
          {sub != null && <div className="mt-0.5 truncate text-xs text-muted-foreground">{sub}</div>}
        </div>
      ))}
    </div>
  );
}

function ChartCard({ title, children, className, note = "Daily snapshots recorded by the 5 PM job." }: { title: string; children: ReactNode; className?: string; note?: string }) {
  return (
    <Card className={className}>
      <CardHeader>
        <CardTitle>{title}</CardTitle>
        <CardDescription>{note}</CardDescription>
      </CardHeader>
      <CardContent>{children}</CardContent>
    </Card>
  );
}

function Breakdown({ title, total, rows }: { title: string; total: number; rows: { name: string; count: number; amount?: number }[] }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>{title}</CardTitle>
      </CardHeader>
      <CardContent className="space-y-2.5">
        {rows.map((r) => {
          const p = total ? (r.count / total) * 100 : 0;
          return (
            <div key={r.name} className="space-y-1">
              <div className="flex justify-between gap-2 text-sm">
                <span>{r.name}</span>
                <span className="tabular text-muted-foreground">
                  {r.count} ({p.toFixed(1)}%){r.amount != null && <> · {formatINR(r.amount)}</>}
                </span>
              </div>
              <div className="h-1.5 overflow-hidden rounded-full bg-muted">
                <div className="h-full rounded-full bg-chart-1" style={{ width: `${p}%` }} />
              </div>
            </div>
          );
        })}
      </CardContent>
    </Card>
  );
}

function Table<T>({
  title,
  rows,
  columns,
  onRow,
  search,
  loading,
}: {
  title: string;
  rows: T[];
  columns: ColumnDef<any, any>[];
  onRow?: (r: T) => void;
  search?: (r: T) => string;
  loading: boolean;
}) {
  return (
    <section className="space-y-2">
      <h2 className="text-sm font-semibold">{title}</h2>
      <DataTable<any>
        columns={columns}
        data={rows}
        loading={loading}
        onRowClick={onRow as ((r: any) => void) | undefined}
        searchText={search as ((r: any) => string) | undefined}
        exportName={title.split(" ·")[0].toLowerCase().replace(/\s+/g, "-")}
        pageSize={25}
      />
    </section>
  );
}

function Bars({ data, name, count }: { data: { x: string; y: number }[]; name: string; count?: boolean }) {
  const config = { y: { label: name, color: "var(--chart-1)" } } satisfies ChartConfig;
  if (data.length === 0) return <p className="py-16 text-center text-sm text-muted-foreground">No snapshots recorded yet.</p>;
  return (
    <ChartContainer config={config} className="h-64 w-full">
      <BarChart data={data} margin={{ left: 4, right: 12, top: 8 }}>
        <CartesianGrid vertical={false} strokeDasharray="3 3" />
        <XAxis dataKey="x" tickLine={false} axisLine={false} tickMargin={8} minTickGap={16} />
        <YAxis tickLine={false} axisLine={false} width={64} allowDecimals={false} tickFormatter={(v) => (count ? String(v) : formatINRCompact(v))} />
        <ChartTooltip
          cursor={{ fillOpacity: 0.4 }}
          content={<ChartTooltipContent formatter={(v) => <span className="font-medium tabular">{count ? String(v) : formatINR(Number(v))}</span>} />}
        />
        <Bar dataKey="y" fill="var(--color-y)" radius={[4, 4, 0, 0]} maxBarSize={40} />
      </BarChart>
    </ChartContainer>
  );
}

function Lines({ data, series, percent }: { data: { x: string; a: number; b?: number }[]; series: { a: string; b?: string }; percent?: boolean }) {
  const config: ChartConfig = { a: { label: series.a, color: "var(--chart-1)" }, ...(series.b ? { b: { label: series.b, color: "var(--chart-2)" } } : {}) };
  if (data.length < 2) return <p className="py-16 text-center text-sm text-muted-foreground">Not enough snapshots recorded yet.</p>;
  return (
    <ChartContainer config={config} className="h-64 w-full">
      <LineChart data={data} margin={{ left: 4, right: 12, top: 8 }}>
        <CartesianGrid vertical={false} strokeDasharray="3 3" />
        <XAxis dataKey="x" tickLine={false} axisLine={false} tickMargin={8} minTickGap={24} />
        <YAxis tickLine={false} axisLine={false} width={64} tickFormatter={(v) => (percent ? `${v}%` : formatINRCompact(v))} domain={percent ? [0, 100] : undefined} />
        <ChartTooltip
          content={
            <ChartTooltipContent
              formatter={(v, n) => (
                <span className="flex w-full justify-between gap-4">
                  <span className="text-muted-foreground">{config[n as string]?.label}</span>
                  <span className="font-medium tabular">{percent ? `${v}%` : formatINR(Number(v))}</span>
                </span>
              )}
            />
          }
        />
        {series.b && <ChartLegend content={<ChartLegendContent />} />}
        <Line dataKey="a" stroke="var(--color-a)" strokeWidth={2} dot={false} activeDot={{ r: 4 }} />
        {series.b && <Line dataKey="b" stroke="var(--color-b)" strokeWidth={2} dot={false} activeDot={{ r: 4 }} />}
      </LineChart>
    </ChartContainer>
  );
}
