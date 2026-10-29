"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { format } from "date-fns";
import {
  AlarmClock,
  ArrowRight,
  CalendarX2,
  CircleSlash,
  ClipboardX,
  FileWarning,
  Inbox,
  MapPinOff,
  PhoneOff,
  Siren,
  UserX,
} from "lucide-react";
import { Bar, BarChart, CartesianGrid, Line, LineChart, XAxis, YAxis } from "recharts";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import { Card, CardAction, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import {
  ChartContainer,
  ChartLegend,
  ChartLegendContent,
  ChartTooltip,
  ChartTooltipContent,
  type ChartConfig,
} from "@/components/ui/chart";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { KpiCard } from "@/components/app/kpi-card";
import { PageHeader } from "@/components/app/page-header";
import { EscalationBadge, Pill } from "@/components/app/status";
import { useSessionUser } from "@/components/app/providers";
import { formatINR, formatINRCompact, initials } from "@/lib/format";
import { useRms, useTrends } from "@/lib/queries";
import { AGEING_BUCKETS } from "@/lib/selectors";
import { cn } from "@/lib/utils";

const trendConfig = {
  expected: { label: "Expected", color: "var(--chart-1)" },
  actual: { label: "Collected", color: "var(--chart-2)" },
} satisfies ChartConfig;

const ageingConfig = { amount: { label: "Overdue", color: "var(--chart-1)" } } satisfies ChartConfig;

function greeting() {
  const h = new Date().getHours();
  return h < 12 ? "Good morning" : h < 17 ? "Good afternoon" : "Good evening";
}

export default function DashboardPage() {
  const rms = useRms();
  const router = useRouter();
  const user = useSessionUser();
  const trends = useTrends();
  const loading = rms.isLoading;

  const trendData = (trends.data ?? []).slice(-14).map((t) => ({
    label: format(new Date(t.date), "dd MMM"),
    expected: t.collectionExpected ?? 0,
    actual: t.collectionActual ?? 0,
  }));
  const ageingData = AGEING_BUCKETS.map((k) => ({ bucket: k, amount: rms.outstandingAgeingBuckets[k] ?? 0 }));

  const target = rms.recoveryTarget;
  const pct = (v: number) => (target > 0 ? Math.min(100, Math.round((v / target) * 100)) : 0);

  const exceptions = [
    { label: "Broken PTPs", count: rms.brokenPtps.length, icon: CalendarX2, href: "/ptps?status=broken", tone: "danger" },
    { label: "No follow-up 4+ days", count: rms.noFollowUpAccounts.length, icon: PhoneOff, href: "/queue?view=no-follow-up", tone: "warning" },
    { label: "Owner mapping required", count: rms.ownerMappingRequired.length, icon: UserX, href: "/queue?view=ownerless", tone: "danger", sub: formatINRCompact(rms.ownerlessExposure) },
    { label: "No valid next action", count: rms.noValidNextAction.length, icon: CircleSlash, href: "/queue?view=no-next-action", tone: "warning" },
    { label: "Critical tasks overdue", count: rms.criticalTasks.length, icon: ClipboardX, href: "/tasks?filter=overdue", tone: "danger" },
    { label: "Visits without outcome", count: rms.physicalVisitsPendingReview.length, icon: MapPinOff, href: "/tasks", tone: "warning" },
  ] as const;

  // Same three lists as the mobile Approvals screen (ReApprovalsTab).
  const actions = [
    { label: "PTP corrections", count: rms.ptpCorrectionRequests.length, href: "/approvals?tab=ptp" },
    { label: "Disputes awaiting decision", count: rms.disputesNeedingAction.length, href: "/approvals?tab=disputes" },
    { label: "Payments to verify", count: rms.approvalsPaymentClaims.length, href: "/approvals?tab=claims" },
  ];

  return (
    <div className="mx-auto max-w-[1600px] space-y-6">
      <PageHeader
        eyebrow={format(new Date(), "EEEE, dd MMMM yyyy")}
        title={`${greeting()}, ${user.fullName.split(" ")[0]}`}
        description={
          rms.branchActive
            ? `Showing ${rms.branch}. Figures are recomputed for this branch.`
            : "Company-wide recovery position across all branches."
        }
        actions={
          <>
            <Button variant="outline" render={<Link href="/control" />}>
              <AlarmClock />
              5 PM Control
            </Button>
            <Button render={<Link href="/approvals" />}>
              <Inbox />
              Approval Inbox
              {rms.approvalInboxCount > 0 && (
                <span className="rounded bg-white/20 px-1.5 text-xs tabular">{rms.approvalInboxCount}</span>
              )}
            </Button>
          </>
        }
      />

      {/* Same six cards, figures and drill-downs as the mobile Control Dashboard (ControlDashboardScreen._buildStatCards). */}
      <section className="grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-6">
        <KpiCard loading={loading} label="Total Outstanding" value={formatINR(rms.totalOutstanding)} hint={`${rms.customers.length.toLocaleString("en-IN")} Customers`} href="/queue?mode=outstanding" />
        <KpiCard loading={loading} label="Total Overdue" value={formatINR(rms.totalOverdueAmount)} hint={`${rms.totalOverdueCustomerCount.toLocaleString("en-IN")} Customers`} href="/queue" tone="danger" />
        <KpiCard loading={loading} label="Expected Collection Today" value={formatINR(rms.dueTodayPtpAmount)} hint={`${rms.dueTodayPtpCount} PTPs Active Today`} href="/ptps?status=today" tone="info" />
        <KpiCard loading={loading} label="Total PTPs" value={formatINR(rms.scheduledPtpAmount)} hint={`${rms.scheduledPtps.length} PTPs`} href="/ptps?status=scheduled" />
        <KpiCard loading={loading} label="Total Broken PTPs" value={formatINR(rms.brokenPtpAmount)} hint={`${rms.brokenPtps.length} Broken`} href="/ptps?status=broken" tone="danger" />
        <KpiCard loading={loading} label="Today's Overdue" value={formatINR(rms.overduePtpAmount)} hint={`${rms.overduePtps.length} Overdue`} href="/ptps?status=overdue" tone="warning" />
      </section>

      <section className="grid gap-4 lg:grid-cols-5">
        {/* Today Recovery Control — kept as three separate figures: Target and Expected must never be added together. */}
        <Card className="lg:col-span-3">
          <CardHeader>
            <CardTitle>Today&apos;s recovery control</CardTitle>
            <CardDescription>Recovery target (25% of overdue exposure) against what is promised and what has arrived.</CardDescription>
          </CardHeader>
          <CardContent className="space-y-5">
            {[
              { label: "Recovery target", value: target, pct: 100, bar: "bg-muted-foreground/40" },
              { label: "Expected collection (open PTPs)", value: rms.expectedCollection, pct: pct(rms.expectedCollection), bar: "bg-chart-1" },
              { label: "Collected today", value: rms.todaysCollectedAmount, pct: pct(rms.todaysCollectedAmount), bar: "bg-chart-2" },
            ].map((r) => (
              <div key={r.label} className="space-y-1.5">
                <div className="flex items-baseline justify-between gap-4 text-sm">
                  <span className="text-muted-foreground">{r.label}</span>
                  <span className="font-semibold tabular">
                    {formatINR(r.value)}
                    {r.label !== "Recovery target" && target > 0 && (
                      <span className="ml-2 text-xs font-normal text-muted-foreground">{r.pct}% of target</span>
                    )}
                  </span>
                </div>
                <div className="h-2 overflow-hidden rounded-full bg-muted">
                  <div className={cn("h-full rounded-full transition-all", r.bar)} style={{ width: `${r.pct}%` }} />
                </div>
              </div>
            ))}
            <div className="grid grid-cols-3 gap-3 border-t pt-4 text-sm">
              <div>
                <div className="text-xs text-muted-foreground">PTP kept (MTD)</div>
                <div className={cn("font-semibold tabular", rms.ptpKeptMtdPercent < 75 ? "text-destructive" : "text-success")}>
                  {rms.ptpKeptMtdPercent}% <span className="text-xs font-normal text-muted-foreground">/ 75% target</span>
                </div>
              </div>
              <div>
                <div className="text-xs text-muted-foreground">Money at risk</div>
                <div className="font-semibold tabular">{formatINRCompact(rms.moneyAtRisk)}</div>
              </div>
              <div>
                <div className="text-xs text-muted-foreground">Accounts at risk</div>
                <div className="font-semibold tabular">{rms.atRiskAccounts.length}</div>
              </div>
            </div>
          </CardContent>
        </Card>

        {/* My actions */}
        <Card className="lg:col-span-2">
          <CardHeader>
            <CardTitle>My actions</CardTitle>
            <CardDescription>Decisions only you can take — work these first.</CardDescription>
          </CardHeader>
          <CardContent className="space-y-1">
            {actions.map((a) => (
              <Link
                key={a.label}
                href={a.href}
                className="flex items-center justify-between rounded-lg px-2 py-2 text-sm hover:bg-muted"
              >
                <span>{a.label}</span>
                <span className="flex items-center gap-2">
                  <span
                    className={cn(
                      "min-w-7 rounded-md px-1.5 py-0.5 text-center text-xs font-semibold tabular",
                      a.count ? "bg-destructive/10 text-destructive" : "bg-muted text-muted-foreground",
                    )}
                  >
                    {a.count}
                  </span>
                  <ArrowRight className="size-3.5 text-muted-foreground" />
                </span>
              </Link>
            ))}
            <Link href="/tasks" className="mt-2 flex items-center justify-between rounded-lg border px-3 py-2.5 text-sm font-medium hover:bg-muted">
              All open task items
              <span className="tabular">{rms.totalOpenTaskItemsCount}</span>
            </Link>
          </CardContent>
        </Card>
      </section>

      {/* Exceptions */}
      <section>
        <h2 className="mb-3 text-sm font-semibold">Exceptions</h2>
        <div className="grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-6">
          {exceptions.map((e) => (
            <Link
              key={e.label}
              href={e.href}
              className="group flex items-center gap-3 rounded-xl border bg-card p-3 shadow-xs transition-colors hover:border-primary/40"
            >
              <span
                className={cn(
                  "flex size-9 shrink-0 items-center justify-center rounded-lg",
                  e.count === 0 ? "bg-muted text-muted-foreground" : e.tone === "danger" ? "bg-destructive/10 text-destructive" : "bg-warning/14 text-warning",
                )}
              >
                <e.icon className="size-4" />
              </span>
              <div className="min-w-0">
                <div className="text-lg leading-tight font-semibold tabular">{e.count}</div>
                <div className="line-clamp-2 text-xs leading-snug text-muted-foreground">
                  {e.label}
                  {"sub" in e && e.count > 0 && <> · {e.sub}</>}
                </div>
              </div>
            </Link>
          ))}
        </div>
      </section>

      <section className="grid gap-4 lg:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle>Collections — expected vs collected</CardTitle>
            <CardDescription>Daily snapshot from the 5 PM job, last 14 recorded days.</CardDescription>
          </CardHeader>
          <CardContent>
            {trendData.length < 2 ? (
              <EmptyChart text="Not enough daily snapshots recorded yet." />
            ) : (
              <ChartContainer config={trendConfig} className="h-64 w-full">
                <LineChart data={trendData} margin={{ left: 4, right: 12, top: 8 }}>
                  <CartesianGrid vertical={false} strokeDasharray="3 3" />
                  <XAxis dataKey="label" tickLine={false} axisLine={false} tickMargin={8} minTickGap={24} />
                  <YAxis tickLine={false} axisLine={false} width={64} tickFormatter={(v) => formatINRCompact(v)} />
                  <ChartTooltip cursor content={<ChartTooltipContent formatter={(v, n) => <TooltipRow name={trendConfig[n as keyof typeof trendConfig]?.label ?? String(n)} value={Number(v)} color={`var(--color-${n})`} />} />} />
                  <ChartLegend content={<ChartLegendContent />} />
                  <Line dataKey="expected" type="monotone" stroke="var(--color-expected)" strokeWidth={2} dot={false} activeDot={{ r: 4 }} />
                  <Line dataKey="actual" type="monotone" stroke="var(--color-actual)" strokeWidth={2} dot={false} activeDot={{ r: 4 }} />
                </LineChart>
              </ChartContainer>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Overdue by ageing</CardTitle>
            <CardDescription>Customer overdue grouped by oldest overdue invoice.</CardDescription>
          </CardHeader>
          <CardContent>
            <ChartContainer config={ageingConfig} className="h-64 w-full">
              <BarChart data={ageingData} margin={{ left: 4, right: 12, top: 8 }}>
                <CartesianGrid vertical={false} strokeDasharray="3 3" />
                <XAxis dataKey="bucket" tickLine={false} axisLine={false} tickMargin={8} />
                <YAxis tickLine={false} axisLine={false} width={64} tickFormatter={(v) => formatINRCompact(v)} />
                <ChartTooltip cursor={{ fillOpacity: 0.4 }} content={<ChartTooltipContent hideIndicator formatter={(v) => <span className="font-medium tabular">{formatINR(Number(v))}</span>} />} />
                <Bar dataKey="amount" fill="var(--color-amount)" radius={[4, 4, 0, 0]} maxBarSize={56} />
              </BarChart>
            </ChartContainer>
          </CardContent>
        </Card>
      </section>

      <section className="grid gap-4 xl:grid-cols-5">
        <Card className="xl:col-span-3">
          <CardHeader>
            <CardTitle>Salesmen Performance</CardTitle>
            <CardDescription>Salesmen carrying overdue exposure — same list as the mobile dashboard.</CardDescription>
            <CardAction>
              <Button variant="ghost" size="sm" render={<Link href="/salesmen" />}>
                View all <ArrowRight />
              </Button>
            </CardAction>
          </CardHeader>
          <CardContent className="px-0">
            <Table>
              <TableHeader>
                <TableRow className="hover:bg-transparent">
                  <TableHead className="pl-6">Salesman</TableHead>
                  <TableHead className="text-right">Total Overdue</TableHead>
                  <TableHead className="text-right">Due Today</TableHead>
                  <TableHead className="text-right">Tasks</TableHead>
                  <TableHead className="pr-6 text-right">Kept %</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {rms.salesmenWithOverdue.slice(0, 10).map((s) => (
                  <TableRow key={s.id} className="cursor-pointer" onClick={() => router.push(`/salesmen/${encodeURIComponent(s.id)}`)}>
                    <TableCell className="pl-6">
                      <div className="flex items-center gap-2.5">
                        <Avatar className="size-7">
                          <AvatarFallback className="text-[10px]">{initials(s.fullName)}</AvatarFallback>
                        </Avatar>
                        <div>
                          <div className="font-medium">{s.fullName}</div>
                          <div className="text-xs text-muted-foreground">{s.branch}</div>
                        </div>
                      </div>
                    </TableCell>
                    <TableCell className="text-right tabular">{formatINR(s.totalOverdue)}</TableCell>
                    <TableCell className="text-right tabular">{formatINR(s.dueTodayPtps)}</TableCell>
                    <TableCell className="text-right tabular">{s.taskCompletionRate}%</TableCell>
                    <TableCell
                      className={cn(
                        "pr-6 text-right font-semibold tabular",
                        s.ptpKeptPercent >= 75 ? "text-success" : s.ptpKeptPercent >= 60 ? "text-warning" : "text-destructive",
                      )}
                    >
                      {s.ptpKeptPercent}%
                    </TableCell>
                  </TableRow>
                ))}
                {!loading && rms.salesmenWithOverdue.length === 0 && (
                  <TableRow>
                    <TableCell colSpan={5} className="h-24 text-center text-muted-foreground">
                      No salesmen match this filter.
                    </TableCell>
                  </TableRow>
                )}
              </TableBody>
            </Table>
            <p className="px-6 pt-3 text-xs text-muted-foreground">
              Showing {Math.min(10, rms.salesmenWithOverdue.length)} of {rms.salesmenWithOverdue.length} Salesmen
            </p>
          </CardContent>
        </Card>

        <Card className="xl:col-span-2">
          <CardHeader>
            <CardTitle>Top overdue customers</CardTitle>
            <CardDescription>Largest overdue exposure right now.</CardDescription>
            <CardAction>
              <Button variant="ghost" size="sm" render={<Link href="/queue" />}>
              Queue <ArrowRight />
            </Button>
            </CardAction>
          </CardHeader>
          <CardContent className="space-y-1">
            {rms.topOverdueCustomers.map((c) => (
              <Link
                key={c.id}
                href={`/customers/${encodeURIComponent(c.id)}`}
                className="flex items-center justify-between gap-3 rounded-lg px-2 py-2 hover:bg-muted"
              >
                <div className="min-w-0">
                  <div className="truncate text-sm font-medium">{c.name}</div>
                  <div className="truncate text-xs text-muted-foreground">
                    {rms.salesmanName(c.assignedSalesmanId)} · {c.oldestOverdueDays} days
                  </div>
                </div>
                <div className="flex shrink-0 items-center gap-2">
                  <EscalationBadge level={c.escalationLevel} />
                  <span className="text-sm font-semibold tabular">{formatINRCompact(c.totalDue)}</span>
                </div>
              </Link>
            ))}
            {rms.openEscalations.length > 0 && (
              <Link href="/escalations" className="mt-3 flex items-center gap-2 rounded-lg border border-destructive/30 bg-destructive/5 px-3 py-2 text-sm text-destructive">
                <Siren className="size-4" />
                {rms.openEscalations.length} open escalation{rms.openEscalations.length === 1 ? "" : "s"} need supervision
              </Link>
            )}
            {rms.disputesNeedingAction.length > 0 && (
              <Link href="/disputes" className="flex items-center gap-2 rounded-lg px-3 py-2 text-sm hover:bg-muted">
                <FileWarning className="size-4 text-muted-foreground" />
                <Pill tone="warning">{rms.disputesNeedingAction.length}</Pill> disputes awaiting your decision
              </Link>
            )}
          </CardContent>
        </Card>
      </section>
    </div>
  );
}

function TooltipRow({ name, value, color }: { name: string; value: number; color: string }) {
  return (
    <div className="flex w-full items-center gap-2">
      <span className="size-2 rounded-sm" style={{ background: color }} />
      <span className="text-muted-foreground">{name}</span>
      <span className="ml-auto font-medium tabular">{formatINR(value)}</span>
    </div>
  );
}

function EmptyChart({ text }: { text: string }) {
  return <div className="flex h-64 items-center justify-center rounded-lg border border-dashed text-sm text-muted-foreground">{text}</div>;
}
