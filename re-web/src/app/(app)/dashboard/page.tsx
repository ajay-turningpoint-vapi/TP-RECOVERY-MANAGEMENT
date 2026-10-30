"use client";

import Link from "next/link";
import { format } from "date-fns";
import {
  AlarmClock,
  CalendarCheck,
  CalendarClock,
  CalendarX2,
  ChevronRight,
  CircleSlash,
  ClipboardList,
  ClipboardX,
  FileWarning,
  Handshake,
  IndianRupee,
  Inbox,
  MapPinOff,
  PhoneOff,
  Siren,
  Unlink,
  UserX,
  Wallet,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { KpiCard } from "@/components/app/kpi-card";
import { useSessionUser } from "@/components/app/providers";
import { ColorAvatar, GradientBar, HUE, IconTile, type Hue } from "@/components/app/visual";
import { formatINR } from "@/lib/format";
import { useRms } from "@/lib/queries";
import { cn } from "@/lib/utils";

function greeting() {
  const h = new Date().getHours();
  return h < 12 ? "Good morning" : h < 17 ? "Good afternoon" : "Good evening";
}

/**
 * Home — written for someone who is not technical and needs large text:
 * one clear question per section, plain words, big numbers, and every
 * list reachable with one obvious button. Figures are the same as the
 * mobile Control Dashboard.
 */
export default function DashboardPage() {
  const rms = useRms();
  const user = useSessionUser();
  const loading = rms.isLoading;

  const target = rms.recoveryTarget;
  const collectedPct = target > 0 ? Math.round((rms.todaysCollectedAmount / target) * 100) : 0;

  const todo: { label: string; help: string; count: number; href: string; icon: React.ElementType; hue: Hue }[] = [
    { label: "Approvals waiting", help: "Promise changes and payment checks — yes or no", count: rms.approvalInboxCount, href: "/approvals", icon: Inbox, hue: "rose" },
    { label: "Tasks to do", help: "Work to do — calls, visits, follow-ups", count: rms.workOpenCount, href: "/tasks", icon: ClipboardList, hue: "indigo" },
    { label: "Disputes to decide", help: "Customers who say the bill is wrong", count: rms.disputesNeedingAction.length, href: "/disputes?stage=decide", icon: FileWarning, hue: "violet" },
    { label: "Escalations open", help: "Serious cases you are watching", count: rms.openEscalations.length, href: "/escalations", icon: Siren, hue: "amber" },
  ];

  const problems: { label: string; count: number; icon: React.ElementType; href: string; hue: Hue }[] = [
    { label: "Customers who broke a payment promise", count: rms.brokenPtps.length, icon: CalendarX2, href: "/ptps?status=broken", hue: "rose" },
    { label: "Customers whose task is not done for 5+ days", count: rms.noFollowUpAccounts.length, icon: PhoneOff, href: "/queue?view=no-follow-up", hue: "amber" },
    { label: "Customers with no salesman", count: rms.ownerMappingRequired.length, icon: UserX, href: "/queue?view=ownerless", hue: "violet" },
    { label: "Customers never contacted (no outcome recorded yet)", count: rms.noValidNextAction.length, icon: CircleSlash, href: "/queue?view=no-next-action", hue: "amber" },
    { label: "Important tasks that are late", count: rms.criticalTasks.length, icon: ClipboardX, href: "/tasks?filter=overdue", hue: "rose" },
    { label: "Visits with no result written", count: rms.physicalVisitsPendingReview.length, icon: MapPinOff, href: "/tasks", hue: "sky" },
  ];

  return (
    <div className="mx-auto max-w-[1400px] space-y-8">
      {/* Greeting */}
      <header className="flex flex-col gap-4 sm:flex-row sm:items-end sm:justify-between">
        <div>
          <p className="text-base text-muted-foreground">{format(new Date(), "EEEE, d MMMM yyyy")}</p>
          <h1 className="text-2xl font-bold tracking-tight md:text-3xl">
            {greeting()}, {user.fullName.split(" ")[0]}
          </h1>
          <p className="mt-1 text-base text-muted-foreground">
            {rms.branchActive ? `Showing branch: ${rms.branch}` : "Showing all branches"}
          </p>
        </div>
        <Button variant="outline" size="lg" render={<Link href="/control" />}>
          <AlarmClock /> End-of-Day Check
        </Button>
      </header>

      {/* Step 1 — what needs her */}
      <Section number={1} title="What needs you today">
        <div className="grid gap-4 md:grid-cols-2">
          {todo.map((t) => (
            <Link
              key={t.label}
              href={t.href}
              className="flex items-center gap-4 rounded-xl border-2 bg-card p-5 transition-colors hover:border-primary hover:bg-accent/40"
            >
              <IconTile hue={t.hue} size="lg">
                <t.icon />
              </IconTile>
              <div className="min-w-0 flex-1">
                <div className="text-lg font-bold">{t.label}</div>
                <div className="text-base text-muted-foreground">{t.help}</div>
              </div>
              <span
                className={cn(
                  "flex h-11 min-w-11 items-center justify-center rounded-xl px-3 text-2xl font-bold tabular",
                  t.count ? HUE[t.hue].solid : "bg-slate-100 text-slate-500 dark:bg-slate-800",
                )}
              >
                {loading ? "…" : t.count}
              </span>
              <ChevronRight className="size-6 shrink-0 text-muted-foreground" />
            </Link>
          ))}
        </div>
      </Section>

      {/* Step 2 — money (same six figures as the mobile dashboard) */}
      <Section number={2} title="Money today" note="Same figures as the mobile app.">
        <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
          <KpiCard loading={loading} icon={<Wallet />} label="Total Outstanding" value={rms.totalOutstanding} format={formatINR} hint={`${rms.customers.length.toLocaleString("en-IN")} customers`} href="/queue?mode=outstanding" />
          <KpiCard loading={loading} icon={<IndianRupee />} label="Total Overdue" value={rms.totalOverdueAmount} format={formatINR} hint={`${rms.totalOverdueCustomerCount.toLocaleString("en-IN")} customers`} href="/queue" tone="danger" />
          <KpiCard loading={loading} icon={<CalendarCheck />} label="Promised to pay today" value={rms.dueTodayPtpAmount} format={formatINR} hint={`${rms.dueTodayPtpCount} promises · Expected Collection Today`} href="/ptps?status=today" tone="info" />
          <KpiCard loading={loading} icon={<Handshake />} label="All open payment promises" value={rms.scheduledPtpAmount} format={formatINR} hint={`${rms.scheduledPtps.length} promises · Total PTPs`} href="/ptps?status=scheduled" hue="violet" />
          <KpiCard loading={loading} icon={<Unlink />} label="Broken payment promises" value={rms.brokenPtpAmount} format={formatINR} hint={`${rms.brokenPtps.length} broken · Total Broken PTPs`} href="/ptps?status=broken" tone="danger" />
          <KpiCard loading={loading} icon={<CalendarClock />} label="Promises now late" value={rms.overduePtpAmount} format={formatINR} hint={`${rms.overduePtps.length} late · Today's Overdue`} href="/ptps?status=overdue" tone="warning" />
        </div>
      </Section>

      {/* Step 3 — collected vs target, in one sentence and one bar */}
      <Section number={3} title="Collected today">
        {loading ? (
          <div className="h-40 animate-pulse rounded-xl border-2 bg-muted/60" aria-label="Loading" />
        ) : (
        <div className="rounded-xl border-2 bg-card p-6">
          <p className="text-lg">
            <span className="text-2xl font-bold text-green-700 tabular dark:text-green-300">{formatINR(rms.todaysCollectedAmount)}</span>{" "}
            collected today, out of a target of <span className="font-bold tabular">{formatINR(target)}</span>.
          </p>
          <GradientBar value={collectedPct} hue="emerald" className="mt-4 h-5" />
          <p className="mt-2 text-base font-semibold">{collectedPct}% of today&apos;s target</p>
          <p className="mt-1 text-base text-muted-foreground">
            {rms.todaysCollectedCustomerCount} customers paid today. Payment promises kept this month: {rms.ptpKeptMtdPercent}% (goal 75%).
          </p>
        </div>
        )}
      </Section>

      {/* Step 4 — problems */}
      <Section number={4} title="Problems to check">
        <div className="divide-y-2 overflow-hidden rounded-xl border-2 bg-card">
          {problems.map((p) => (
            <Link key={p.label} href={p.href} className="flex items-center gap-4 p-4 transition-colors hover:bg-accent/50">
              <IconTile hue={p.count ? p.hue : "slate"} size="md">
                <p.icon />
              </IconTile>
              <span className="flex-1 text-base font-medium">{p.label}</span>
              <span className={cn("text-xl font-bold tabular", p.count ? HUE[p.hue].text : "text-muted-foreground")}>{loading ? "…" : p.count}</span>
              <span className="hidden items-center gap-1 text-base font-semibold text-primary sm:inline-flex">
                Open <ChevronRight className="size-5" />
              </span>
            </Link>
          ))}
        </div>
      </Section>

      {/* Step 5 — people */}
      <Section number={5} title="Salesmen with overdue money" note="Same list as the mobile app.">
        <div className="overflow-hidden rounded-xl border-2 bg-card">
          <div className="hidden grid-cols-[1fr_12rem_10rem_8rem] gap-4 border-b-2 bg-muted/60 px-5 py-3 text-base font-semibold sm:grid">
            <span>Salesman</span>
            <span className="text-right">Total Overdue</span>
            <span className="text-right">Due today</span>
            <span className="text-right">Promises kept</span>
          </div>
          {rms.salesmenWithOverdue.slice(0, 10).map((s) => (
            <Link
              key={s.id}
              href={`/salesmen/${encodeURIComponent(s.id)}`}
              className="grid grid-cols-[1fr_auto] items-center gap-4 border-b-2 px-5 py-4 transition-colors last:border-b-0 hover:bg-accent/50 sm:grid-cols-[1fr_12rem_10rem_8rem]"
            >
              <span className="flex min-w-0 items-center gap-3">
                <ColorAvatar name={s.fullName} />
                <span className="min-w-0">
                  <span className="block truncate text-base font-semibold">{s.fullName}</span>
                  <span className="block text-base text-muted-foreground">{s.branch}</span>
                </span>
              </span>
              <span className="text-right text-base font-bold tabular">{formatINR(s.totalOverdue)}</span>
              <span className="hidden text-right text-base tabular sm:block">{formatINR(s.dueTodayPtps)}</span>
              <span
                className={cn(
                  "hidden text-right text-base font-bold tabular sm:block",
                  s.ptpKeptPercent >= 75 ? "text-green-700 dark:text-green-300" : s.ptpKeptPercent >= 60 ? "text-amber-700 dark:text-amber-300" : "text-red-700 dark:text-red-300",
                )}
              >
                {s.ptpKeptPercent}%
              </span>
            </Link>
          ))}
          {!loading && rms.salesmenWithOverdue.length === 0 && <p className="p-8 text-center text-base text-muted-foreground">No salesmen have overdue money.</p>}
        </div>
        <div className="mt-3">
          <Button variant="outline" size="lg" render={<Link href="/salesmen" />}>
            See all salesmen <ChevronRight />
          </Button>
        </div>
      </Section>
    </div>
  );
}

function Section({ number, title, note, children }: { number: number; title: string; note?: string; children: React.ReactNode }) {
  return (
    <section className="space-y-4">
      <div className="flex flex-wrap items-baseline gap-x-3">
        <span className="flex size-9 items-center justify-center self-center rounded-full bg-primary text-base font-bold text-primary-foreground">{number}</span>
        <h2 className="text-xl font-bold tracking-tight">{title}</h2>
        {note && <span className="text-base text-muted-foreground">{note}</span>}
      </div>
      {children}
    </section>
  );
}
