"use client";

import { useMemo } from "react";
import Link from "next/link";
import { useInfiniteQuery, useQuery } from "@tanstack/react-query";
import {
  ArrowLeft,
  ArrowRight,
  Clock,
  CalendarClock,
  ClipboardPlus,
  CreditCard,
  FileWarning,
  IndianRupee,
  Receipt,
  Wallet,
  Zap,
  Loader2,
  Phone,
  ShieldAlert,
  ShieldCheck,
  Siren,
} from "lucide-react";
import { ActionDialog, useDialog } from "@/components/app/action-dialog";
import { ColorAvatar, HUE, IconTile, type Hue } from "@/components/app/visual";
import { AttachmentLink } from "@/components/app/attachment-link";
import { Timeline } from "@/components/app/timeline";
import { useSessionUser } from "@/components/app/providers";
import {
  ClaimStatusBadge,
  DisputeStatusBadge,
  EscalationBadge,
  Pill,
  PriorityBadge,
  PtpStatusBadge,
  RecoveryStateBadge,
} from "@/components/app/status";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { deadlineInput, localToIso, useRmsAction } from "@/lib/actions";
import { ApiError, friendlyError, rmsGet } from "@/lib/api";
import { formatDate, formatDateTime, formatINR, formatRelativeDay, timeAgo } from "@/lib/format";
import { TASK_TYPE_LABEL, creditHealthBand, friendlyTaskReason, isTaskOpen, parseAuditEvent, parseCustomer } from "@/lib/models";
import { useRms } from "@/lib/queries";
import { cn } from "@/lib/utils";

type Json = Record<string, unknown>;

const NEXT_LEVEL: Record<string, "L2" | "L3" | "L4"> = { none: "L2", L1: "L2", L2: "L3", L3: "L4", L4: "L4" };

export function Customer360({ id }: { id: string }) {
  const rms = useRms();
  const user = useSessionUser();
  const action = useRmsAction();

  const detail = useQuery({
    queryKey: ["customer", id],
    queryFn: () => rmsGet<Json>(`/customers/${encodeURIComponent(id)}`),
    select: parseCustomer,
  });

  const audit = useInfiniteQuery({
    queryKey: ["customer", id, "audit"],
    queryFn: ({ pageParam }) =>
      rmsGet<{ items: Json[]; nextCursor: string | null }>(
        `/customers/${encodeURIComponent(id)}/audit-history?limit=30${pageParam ? `&cursor=${encodeURIComponent(pageParam)}` : ""}`,
      ),
    initialPageParam: "",
    getNextPageParam: (last) => last.nextCursor ?? undefined,
  });

  const c = detail.data ?? rms.customerById.get(id);
  const ptps = useMemo(() => rms.ptps.filter((p) => p.customerId === id).sort((a, b) => +b.promiseDate - +a.promiseDate), [rms.ptps, id]);
  const tasks = useMemo(() => rms.tasks.filter((t) => t.customerId === id).sort((a, b) => +b.createdAt - +a.createdAt), [rms.tasks, id]);
  const disputes = rms.disputes.filter((d) => d.customerId === id);
  const claims = rms.paymentClaims.filter((p) => p.customerId === id);
  const escalations = rms.escalations.filter((e) => e.customerId === id);
  // History also leaves out the server's own "auto-closed" entries.
  const events = (audit.data?.pages ?? [])
    .flatMap((p) => p.items.map(parseAuditEvent))
    .filter((e) => !/_AUTO_CLOSED$/.test(e.type));

  const instruct = useDialog();
  const escalate = useDialog();

  if (!c) {
    return detail.isError ? (
      <div role="alert" className="mx-auto max-w-xl rounded-xl border-2 border-red-200 bg-red-50 p-8 text-center dark:bg-red-500/10">
        <h1 className="text-xl font-bold">{detail.error instanceof ApiError && detail.error.status === 404 ? "Customer not found" : "Could not open this customer"}</h1>
        <p className="mt-2 text-[15px]">
          {detail.error instanceof ApiError && detail.error.status === 404
            ? "They may have been removed from BUSY, or they are in another branch."
            : friendlyError(detail.error)}
        </p>
        <div className="mt-6 flex justify-center gap-2">
          {!(detail.error instanceof ApiError && detail.error.status === 404) && (
            <Button onClick={() => detail.refetch()} disabled={detail.isFetching}>
              {detail.isFetching ? <Loader2 className="animate-spin" /> : null} Try again
            </Button>
          )}
          <Button variant="outline" render={<Link href="/customers" />}>
            Back to customers
          </Button>
        </div>
      </div>
    ) : (
      <div className="mx-auto max-w-[1400px] space-y-4">
        <Skeleton className="h-28 w-full" />
        <Skeleton className="h-24 w-full" />
        <Skeleton className="h-96 w-full" />
      </div>
    );
  }

  const salesmanOptions = rms.salesmen.map((s) => ({ value: s.id, label: `${s.fullName} · ${s.branch}` }));
  const salesman = rms.salesmanById.get(c.assignedSalesmanId);
  // The live open task is the source of truth for "what now" — the
  // customer's stored next-action text can be left over from an older step.
  const step = rms.nextStepFor(c);
  const currentTask = step.task;
  // When the recorded outcome is due: promised date, "will confirm" time,
  // end of the No Answer wait, or the date given for a payment already made.
  const openPtp = rms.allPtps
    .filter((p) => p.customerId === c.id && OPEN_PTP.has(p.status))
    .sort((a, b) => +a.promiseDate - +b.promiseDate)[0];
  const pendingClaim = rms.allPaymentClaims.find((p) => p.customerId === c.id && ["Awaiting Verification", "Sync Pending"].includes(p.status));
  const nextWhen: { label: string; at: Date } | null =
    c.outcomeWaitRule === "Will Confirm" && c.outcomeWaitUntil
      ? { label: "Customer will confirm on", at: c.outcomeWaitUntil }
      : c.outcomeWaitRule === "No Answer" && c.outcomeWaitUntil
        ? { label: "Call again after", at: c.outcomeWaitUntil }
        : c.outcomeWaitRule === "Payment Already Made" && pendingClaim
          ? { label: "Payment date given", at: pendingClaim.claimDate }
          : openPtp
            ? { label: "Promised to pay on", at: openPtp.promiseDate }
            : null;
  // Open payment promises only (same open statuses the server counts as covered).
  const promisedAmount = rms.allPtps
    .filter((p) => p.customerId === c.id && OPEN_PTP.has(p.status))
    .reduce((sum, p) => sum + p.amountPromised, 0);

  return (
    <div className="mx-auto max-w-[1400px] space-y-5">
      <Button variant="ghost" size="sm" className="-ml-2 text-muted-foreground" onClick={() => history.back()}>
        <ArrowLeft />
        Back
      </Button>

      {/* Profile — brand-blue card, every value labelled */}
      <section className="rounded-xl bg-[lab(34.2882%_14.8026_-59.6162)] text-white">
        <div className="flex flex-col gap-4 p-5 lg:flex-row lg:items-start lg:justify-between">
          <div className="flex min-w-0 items-center gap-4">
            <ColorAvatar name={c.name} size="lg" className="ring-4 ring-white/40" />
            <div className="min-w-0 space-y-1.5">
              <h1 className="text-2xl font-bold tracking-tight break-words">{c.name}</h1>
              <div className="flex flex-wrap items-center gap-2 [&_[data-slot=badge]]:bg-white">
                <RecoveryStateBadge state={c.currentRecoveryState} />
                <EscalationBadge level={c.escalationLevel} />
                {c.ownerMappingRequired && <Pill tone="danger">No salesman</Pill>}
                {!c.hasValidNextAction && c.totalDue > 0 && <Pill tone="warning">No next step planned</Pill>}
              </div>
            </div>
          </div>
          <div className="flex shrink-0 flex-wrap gap-2">
            <Button size="lg" className="bg-white text-[lab(34.2882%_14.8026_-59.6162)] hover:bg-white/90 disabled:opacity-60" onClick={() => instruct.open(true)} disabled={!!c.outcomeWaitText}>
              <ClipboardPlus />
              Create task
            </Button>
            <Button
              size="lg"
              variant="outline"
              className="border-white bg-white text-red-700 hover:bg-red-50 hover:text-red-800 dark:bg-white dark:text-red-700"
              onClick={() => escalate.open(true)}
              disabled={c.escalationLevel === "L4"}
            >
              <Siren />
              Escalate to {NEXT_LEVEL[c.escalationLevel]}
            </Button>
          </div>
        </div>

        {/* Facts */}
        <dl className="grid grid-cols-2 gap-x-6 gap-y-3 border-t-2 border-white/20 px-5 py-4 md:grid-cols-3 xl:grid-cols-5">
          <Fact label="Customer code">{c.id}</Fact>
          <Fact label="Branch">{c.branch}</Fact>
          <Fact label="Customer phone">
            {c.contactNumber ? (
              <a href={`tel:${c.contactNumber}`} className="inline-flex items-center gap-1.5 underline decoration-white/50 underline-offset-4 hover:decoration-white">
                <Phone className="size-4" /> {c.contactNumber}
              </a>
            ) : (
              "—"
            )}
            {c.alternateContactNumber && <div className="text-sm font-normal text-white/85">Also {c.alternateContactNumber}</div>}
          </Fact>
          <Fact label="Salesman">
            {salesman ? (
              <Link href={`/salesmen/${encodeURIComponent(salesman.id)}`} className="underline decoration-white/50 underline-offset-4 hover:decoration-white">
                {salesman.fullName}
              </Link>
            ) : (
              <span className="rounded bg-red-600 px-2 py-0.5">No salesman</span>
            )}
          </Fact>
          <Fact label="Salesman phone">
            {salesman?.phone ? (
              <a href={`tel:${salesman.phone}`} className="inline-flex items-center gap-1.5 underline decoration-white/50 underline-offset-4 hover:decoration-white">
                <Phone className="size-4" /> {salesman.phone}
              </a>
            ) : (
              "—"
            )}
          </Fact>
        </dl>

        {/* Next step — the one thing to read first */}
        {(currentTask || step.what) && (
          <div className="mx-5 mb-4 flex items-start gap-3 rounded-lg bg-white px-4 py-3 text-foreground dark:bg-card">
            <ArrowRight className="mt-1 size-5 shrink-0 text-blue-700 dark:text-blue-300" />
            <div className="min-w-0 flex-1">
              <div className="text-sm font-semibold text-blue-800 dark:text-blue-300">Next step</div>
              {currentTask ? (
                <>
                  <div className="text-lg font-bold">{step.what}</div>
                  {step.why && <div className="text-[15px] font-medium text-orange-700 dark:text-orange-400">{step.why}</div>}
                  {step.note && <div className="text-[15px] text-muted-foreground">Note: {step.note}</div>}
                  <div className="mt-2 flex flex-wrap gap-x-6 gap-y-1 text-[15px]">
                    {step.amount && (
                      <span>
                        <span className="text-muted-foreground">Amount to collect </span>
                        <span className="font-bold text-orange-700 dark:text-orange-400">{step.amount}</span>
                      </span>
                    )}
                    <span>
                      <span className="text-muted-foreground">Assigned to </span>
                      <span className="font-semibold">{currentTask.ownerId === user.id ? "You" : rms.salesmanName(currentTask.ownerId)}</span>
                    </span>
                    <span>
                      <span className="text-muted-foreground">Priority </span>
                      <span className={cn("font-semibold", /critical|high/i.test(currentTask.priority) && "text-orange-700 dark:text-orange-400")}>{currentTask.priority}</span>
                    </span>
                  </div>
                  <WhenLine label={currentTask.deadline < new Date() ? "Was due on" : "Due by"} at={currentTask.deadline} late={currentTask.deadline < new Date()} />
                </>
              ) : (
                <>
                  <div className="text-lg font-bold">{c.primaryNextAction}</div>
                  {c.reasonForAction && <div className="text-[15px] text-muted-foreground">{readableAmounts(c.reasonForAction)}</div>}
                  {nextWhen && <WhenLine label={nextWhen.label} at={nextWhen.at} />}
                </>
              )}
            </div>
          </div>
        )}
        {c.outcomeWaitText && (
          <div className="mx-5 mb-4 flex items-start gap-3 rounded-lg bg-amber-50 px-4 py-3 text-[15px] text-amber-950 dark:bg-amber-100">
            <ShieldAlert className="mt-0.5 size-5 shrink-0 text-amber-700" />
            <div>
              <span className="font-semibold">Create task is locked for now. </span>
              {c.outcomeWaitText}
            </div>
          </div>
        )}
        <p className="flex items-center gap-1.5 border-t-2 border-white/20 px-5 py-2.5 text-sm text-white/90">
          <Clock className="size-4" /> Money figures updated from BUSY {c.financialFreshness ? timeAgo(c.financialFreshness) : "—"}
        </p>
      </section>

      {/* Financials */}
      <div className="grid grid-cols-2 gap-3 md:grid-cols-4">
        {(
          [
            ["Total Outstanding", formatINR(c.totalOutstanding), "indigo", Wallet],
            ["Total Overdue", formatINR(c.totalDue), "rose", IndianRupee],
            ["Already promised", formatINR(promisedAmount), "emerald", ShieldCheck],
            ["Still to chase now", formatINR(c.actionableAmount), "amber", Zap],
            ["Amount in dispute", formatINR(c.disputedAmount), "violet", FileWarning],
            ["Credit days", `${c.creditDays} days`, "sky", CalendarClock],
            ["Credit limit", formatINR(c.creditLimit), "sky", CreditCard],
            ["Last payment", c.lastPaymentDate ? `${formatINR(c.lastPaymentAmount)} · ${formatDate(c.lastPaymentDate, "dd MMM")}` : "—", "slate", Receipt],
          ] as [string, string, Hue, React.ElementType][]
        ).map(([k, v, hue, Icon]) => (
          <div key={k} className="relative flex items-center gap-3 rounded-xl border-2 bg-card p-4">
            <div aria-hidden className={cn("pointer-events-none absolute inset-0 bg-linear-to-br to-transparent to-70%", HUE[hue].wash)} />
            <IconTile hue={hue} size="sm" className="relative">
              <Icon />
            </IconTile>
            <div className="relative min-w-0">
              <div className="text-base font-medium text-muted-foreground">{k}</div>
              <div className="text-lg font-bold tabular">{v}</div>
            </div>
          </div>
        ))}
      </div>

      <Tabs defaultValue="overview">
        <TabsList className="h-auto flex-wrap">
          <TabsTrigger value="overview">Overview</TabsTrigger>
          <TabsTrigger value="invoices">Invoices ({c.invoices.length})</TabsTrigger>
          <TabsTrigger value="ptps">PTPs ({ptps.length})</TabsTrigger>
          <TabsTrigger value="tasks">Tasks ({tasks.length})</TabsTrigger>
          <TabsTrigger value="disputes">Disputes ({disputes.length})</TabsTrigger>
          <TabsTrigger value="claims">Payment claims ({claims.length})</TabsTrigger>
          <TabsTrigger value="escalations">Escalations ({escalations.length})</TabsTrigger>
          <TabsTrigger value="timeline">History</TabsTrigger>
        </TabsList>

        <TabsContent value="overview" className="mt-4 grid gap-4 lg:grid-cols-3">
          <Card>
            <CardHeader>
              <CardTitle>Ageing</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3">
              {(
                [
                  ["0–30 days", c.ageing.age0_30, AGE_TONE[0]],
                  ["31–60 days", c.ageing.age31_60, AGE_TONE[1]],
                  ["61–90 days", c.ageing.age61_90, AGE_TONE[2]],
                  ["90+ days", c.ageing.age90Plus, AGE_TONE[3]],
                ] as const
              ).map(([k, v, tone]) => {
                const total = c.ageing.age0_30 + c.ageing.age31_60 + c.ageing.age61_90 + c.ageing.age90Plus;
                return (
                  <div key={k} className={cn("space-y-1.5 rounded-lg px-3 py-2", v > 0 ? tone.bg : "bg-muted/40")}>
                    <div className="flex items-center justify-between text-[15px]">
                      <span className="flex items-center gap-2 font-medium">
                        <span className={cn("size-2.5 rounded-full", tone.bar)} />
                        {k}
                      </span>
                      <span className={cn("font-bold tabular", v > 0 ? tone.text : "text-muted-foreground")}>{formatINR(v)}</span>
                    </div>
                    <div className="h-2 overflow-hidden rounded-full bg-background/80">
                      <div className={cn("h-full rounded-full", tone.bar)} style={{ width: `${total ? (v / total) * 100 : 0}%` }} />
                    </div>
                  </div>
                );
              })}
              {c.futureDue > 0 && <div className="pt-1 text-sm text-muted-foreground">Not yet due: {formatINR(c.futureDue)}</div>}
            </CardContent>
          </Card>
          <Card>
            <CardHeader>
              <CardTitle>Risk</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm">
              {(() => {
                const t = scoreTone(c.creditHealthScore);
                return (
                  <div className={cn("flex items-center justify-between rounded-lg border-2 px-4 py-3", t.bg, t.border)}>
                    <div>
                      <div className="text-sm font-medium text-muted-foreground">Customer credit health</div>
                      <div className={cn("text-lg font-bold", t.text)}>{creditHealthBand(c.creditHealthScore)}</div>
                    </div>
                    <div className={cn("text-3xl font-bold tabular", t.text)}>{c.creditHealthScore ?? "—"}</div>
                  </div>
                );
              })()}
              {c.creditHealthComponents &&
                Object.entries(c.creditHealthComponents)
                  .filter(([k]) => k.toLowerCase() !== "total")
                  .map(([k, v]) => {
                    const t = scoreTone(v);
                    return (
                      <div key={k} className="space-y-1">
                        <div className="flex justify-between text-sm">
                          <span className="capitalize">{k.replace(/([A-Z])/g, " $1").toLowerCase()}</span>
                          <span className={cn("font-bold tabular", t.text)}>{v}</span>
                        </div>
                        <div className="h-1.5 overflow-hidden rounded-full bg-muted">
                          <div className={cn("h-full rounded-full", t.bar)} style={{ width: `${Math.max(0, Math.min(100, v))}%` }} />
                        </div>
                      </div>
                    );
                  })}
              <div className={cn("flex justify-between rounded-lg px-3 py-2", c.noAnswerAttempts > 0 ? "bg-amber-50 dark:bg-amber-500/10" : "bg-muted/40")}>
                <span>No-answer attempts</span>
                <span className={cn("font-bold tabular", c.noAnswerAttempts > 0 && "text-amber-800 dark:text-amber-300")}>{c.noAnswerAttempts}</span>
              </div>
              <div className="flex justify-between px-3">
                <span className="text-muted-foreground">Credit days</span>
                <span className="tabular">{c.creditDays}</span>
              </div>
              {c.gstNo && (
                <div className="flex justify-between px-3">
                  <span className="text-muted-foreground">GST</span>
                  <span>{c.gstNo}</span>
                </div>
              )}
              {c.address && <div className="px-3 text-xs text-muted-foreground">{c.address}</div>}
            </CardContent>
          </Card>
          <Card>
            <CardHeader>
              <CardTitle>Open work</CardTitle>
            </CardHeader>
            <CardContent className="space-y-2 text-sm">
              {tasks.filter(isTaskOpen).slice(0, 5).map((t) => (
                <div key={t.id} className="flex items-start justify-between gap-2 rounded-lg border px-3 py-2">
                  <div className="min-w-0">
                    <div className="font-medium">{TASK_TYPE_LABEL[t.type]}</div>
                    <div className="truncate text-xs text-muted-foreground">{friendlyTaskReason(t.reason)}</div>
                  </div>
                  <span className={cn("shrink-0 text-xs tabular", t.deadline < new Date() && "text-destructive")}>
                    {formatRelativeDay(t.deadline)}
                  </span>
                </div>
              ))}
              {tasks.filter(isTaskOpen).length === 0 && <p className="text-muted-foreground">No open tasks.</p>}
              {ptps.filter((p) => p.status === "scheduled").map((p) => (
                <div key={p.id} className="flex justify-between rounded-lg bg-info/8 px-3 py-2">
                  <span>PTP {formatINR(p.amountPromised)}</span>
                  <span className="text-xs text-muted-foreground">{formatDate(p.promiseDate)}</span>
                </div>
              ))}
            </CardContent>
          </Card>
        </TabsContent>

        <TabsContent value="invoices" className="mt-4">
          <SimpleTable
            empty={detail.isLoading ? "Loading invoices…" : "No open invoices."}
            head={["Invoice", "Date", "Due date", "Days", "Amount", "Pending", "Status"]}
            rows={c.invoices.map((i) => [
              i.number,
              formatDate(i.date),
              formatDate(i.dueDate),
              i.dueDays ?? "—",
              formatINR(i.totalAmount),
              <span key="p" className="font-medium">{formatINR(i.pendingAmount)}</span>,
              <Pill key="s" tone={i.status === "Outstanding" ? "danger" : "info"}>{i.message ?? i.status}</Pill>,
            ])}
            align={[, , , "right", "right", "right"]}
          />
        </TabsContent>

        <TabsContent value="ptps" className="mt-4">
          <SimpleTable
            empty="No promises to pay."
            head={["Promise date", "Amount", "Mode", "Status", "Received", "Correction", "Note"]}
            rows={ptps.map((p) => [
              formatDate(p.promiseDate),
              formatINR(p.amountPromised),
              p.paymentMode,
              <PtpStatusBadge key="s" status={p.status} />,
              p.amountReceived != null ? formatINR(p.amountReceived) : "—",
              p.correctionStatus === "none" ? "—" : <Pill key="c" tone={p.correctionStatus === "Pending" ? "warning" : "neutral"}>{p.correctionStatus}</Pill>,
              p.brokenReason ?? p.correctionReason ?? "",
            ])}
            align={[, "right", , , "right"]}
          />
        </TabsContent>

        <TabsContent value="tasks" className="mt-4">
          <SimpleTable
            empty="No tasks."
            head={["Task", "Reason", "Owner", "Priority", "Deadline", "Status", "Source"]}
            rows={tasks.map((t) => [
              TASK_TYPE_LABEL[t.type],
              <span key="r" className="line-clamp-2 max-w-xs">{friendlyTaskReason(t.reason)}</span>,
              rms.salesmanName(t.ownerId),
              <PriorityBadge key="p" priority={t.priority} />,
              <span key="d" className={cn(isTaskOpen(t) && t.deadline < new Date() && "text-destructive")}>{formatDateTime(t.deadline)}</span>,
              <span key="s" className="capitalize">{t.status.replace(/([A-Z])/g, " $1").toLowerCase()}</span>,
              t.source,
            ])}
          />
        </TabsContent>

        <TabsContent value="disputes" className="mt-4">
          <SimpleTable
            empty="No disputes."
            head={["Raised", "Invoice", "Amount", "Reason", "Status", "Owner", ""]}
            rows={disputes.map((d) => [
              formatDate(d.raisedDate),
              d.invoiceNumber ?? "—",
              formatINR(d.amount),
              <span key="r" className="line-clamp-2 max-w-xs">{d.reason}</span>,
              <DisputeStatusBadge key="s" status={d.status} />,
              d.resolutionOwner ?? "—",
              <Button key="o" variant="ghost" size="sm" render={<Link href={`/disputes/${d.id}`} />}>Open</Button>,
            ])}
            align={[, , "right"]}
          />
        </TabsContent>

        <TabsContent value="claims" className="mt-4">
          <SimpleTable
            empty="No payment claims."
            head={["Claim date", "Amount", "Reference", "Status", "Evidence"]}
            rows={claims.map((p) => [
              formatDate(p.claimDate),
              formatINR(p.amount),
              p.reference ?? "—",
              <ClaimStatusBadge key="s" status={p.status} />,
              p.attachmentPath ? <AttachmentLink key="a" path={p.attachmentPath} size="sm" label="Payment proof" /> : "—",
            ])}
            align={[, "right"]}
          />
        </TabsContent>

        <TabsContent value="escalations" className="mt-4">
          <SimpleTable
            empty="Never escalated."
            head={["Level", "Reason", "Plan", "Deadline", "Money at risk", "Status"]}
            rows={escalations.map((e) => [
              <EscalationBadge key="l" level={e.level} />,
              e.reason,
              e.plan || <span key="np" className="text-destructive">No plan</span>,
              formatDate(e.deadline),
              formatINR(e.moneyAtRisk),
              e.isOpen ? <Pill key="o" tone="warning">Open</Pill> : <Pill key="r" tone="success">Resolved</Pill>,
            ])}
            align={[, , , , "right"]}
          />
        </TabsContent>

        <TabsContent value="timeline" className="mt-4">
          <Card>
            <CardContent className="pt-6">
              {audit.isLoading ? (
                <div className="space-y-4" aria-label="Loading">
                  {Array.from({ length: 4 }).map((_, i) => (
                    <div key={i} className="grid grid-cols-[5.5rem_3rem_1fr] gap-3">
                      <Skeleton className="mt-2 h-4 w-16 justify-self-end" />
                      <Skeleton className="size-10 justify-self-center rounded-full" />
                      <Skeleton className="h-24 w-full rounded-xl" />
                    </div>
                  ))}
                </div>
              ) : audit.isError ? (
                <div role="alert" className="flex flex-wrap items-center gap-3 rounded-xl border-2 border-red-200 bg-red-50 p-4 text-[15px] dark:bg-red-500/10">
                  <span className="flex-1">Could not load the history. {friendlyError(audit.error)}</span>
                  <Button variant="outline" onClick={() => audit.refetch()} disabled={audit.isFetching}>
                    {audit.isFetching && <Loader2 className="animate-spin" />} Try again
                  </Button>
                </div>
              ) : events.length === 0 ? (
                <p className="py-8 text-center text-base text-muted-foreground">Nothing has happened on this customer yet.</p>
              ) : (
                <Timeline events={events} />
              )}
              {audit.hasNextPage && (
                <div className="mt-2 flex justify-center">
                  <Button variant="outline" size="lg" onClick={() => audit.fetchNextPage()} disabled={audit.isFetchingNextPage}>
                    {audit.isFetchingNextPage && <Loader2 className="animate-spin" />}
                    {audit.isFetchingNextPage ? "Loading older history…" : "Show older history"}
                  </Button>
                </div>
              )}
            </CardContent>
          </Card>
        </TabsContent>
      </Tabs>

      {/* Commands */}
      <ActionDialog
        {...instruct.props}
        title="Create task for salesman"
        description="A management instruction or task the salesperson must act on. It appears in their app immediately."
        submitLabel="Create task"
        fields={[
          {
            name: "taskType",
            label: "Task type",
            type: "select",
            required: true,
            defaultValue: "managementInstruction",
            options: [
              { value: "managementInstruction", label: "Management instruction" },
              { value: "customerCall", label: "Call customer" },
              { value: "physicalVisit", label: "Physical visit" },
            ],
          },
          { name: "salesmanId", label: "Assign to", type: "select", required: true, defaultValue: c.assignedSalesmanId, options: salesmanOptions },
          { name: "desc", label: "Instruction", type: "textarea", required: true, placeholder: "What exactly should the salesman do?" },
          { name: "deadline", label: "Deadline", type: "datetime", required: true, defaultValue: deadlineInput(1, 18) },
          {
            name: "priority",
            label: "Priority",
            type: "select",
            defaultValue: "High",
            options: ["Low", "Normal", "High", "Critical"].map((p) => ({ value: p, label: p })),
          },
        ]}
        onSubmit={(v) =>
          action.mutateAsync({
            path: `/customers/${encodeURIComponent(c.id)}/management-instruction`,
            body: { salesmanId: v.salesmanId, desc: v.desc, deadline: localToIso(v.deadline), priority: v.priority, taskType: v.taskType },
            success: "Done. The task is now in the salesman's app.",
          })
        }
      />
      <ActionDialog
        {...escalate.props}
        title={`Escalate to ${NEXT_LEVEL[c.escalationLevel]}`}
        description={
          NEXT_LEVEL[c.escalationLevel] === "L4"
            ? "L4 = Management Attention: a tracked case with a plan, owner and deadline."
            : "Record why, the recovery plan and the deadline. You become the case owner."
        }
        submitLabel="Escalate"
        destructive
        fields={[
          { name: "reason", label: "Reason", type: "textarea", required: true },
          { name: "plan", label: "Recovery plan", type: "textarea", required: true },
          { name: "deadline", label: "Plan deadline", type: "datetime", required: true, defaultValue: deadlineInput(3, 18) },
          { name: "moneyAtRisk", label: "Money at risk (₹)", type: "number", defaultValue: String(Math.round(c.totalDue)) },
        ]}
        onSubmit={(v) =>
          action.mutateAsync({
            path: `/escalations/customer/${encodeURIComponent(c.id)}`,
            body: {
              level: NEXT_LEVEL[c.escalationLevel],
              reason: v.reason,
              plan: v.plan,
              ownerId: user.id,
              deadline: localToIso(v.deadline),
              moneyAtRisk: Number(v.moneyAtRisk || 0),
            },
            success: `Escalated to ${NEXT_LEVEL[c.escalationLevel]}.`,
          })
        }
      />
    </div>
  );
}

function WhenLine({ label, at, late }: { label: string; at: Date; late?: boolean }) {
  return (
    <div className={cn("mt-2 inline-flex flex-wrap items-center gap-x-3 gap-y-1 rounded-md px-3 py-1.5 text-[15px]", late ? "bg-red-50 text-red-800 dark:bg-red-500/10 dark:text-red-300" : "bg-blue-50 dark:bg-blue-500/10")}>
      <span className={late ? "" : "text-muted-foreground"}>{label}</span>
      <span className="inline-flex items-center gap-1.5 font-bold">
        <CalendarClock className="size-4" /> {formatDate(at, "d/M/yyyy")}
      </span>
      <span className="inline-flex items-center gap-1.5 font-bold">
        <Clock className="size-4" /> {formatDate(at, "HH:mm")}
      </span>
    </div>
  );
}

function Fact({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="min-w-0">
      <dt className="text-sm text-white/85">{label}</dt>
      <dd className="text-base font-semibold break-words">{children}</dd>
    </div>
  );
}

/** Server text like "PTP of ₹3000000.0" → "PTP of ₹30,00,000". */
const readableAmounts = (text: string) => text.replace(/₹\s?(\d+(?:\.\d+)?)/g, (_, n: string) => formatINR(Number(n)));

function SimpleTable({
  head,
  rows,
  empty,
  align = [],
}: {
  head: string[];
  rows: React.ReactNode[][];
  empty: string;
  align?: (("right" | "center") | undefined)[];
}) {
  return (
    <div className="overflow-hidden rounded-xl border bg-card">
      <div className="overflow-x-auto">
        <Table>
          <TableHeader className="bg-muted/50">
            <TableRow className="hover:bg-transparent">
              {head.map((h, i) => (
                <TableHead key={i} className={cn("h-9 text-xs", align[i] === "right" && "text-right")}>
                  {h}
                </TableHead>
              ))}
            </TableRow>
          </TableHeader>
          <TableBody>
            {rows.length === 0 ? (
              <TableRow className="hover:bg-transparent">
                <TableCell colSpan={head.length} className="h-24 text-center text-muted-foreground">
                  {empty}
                </TableCell>
              </TableRow>
            ) : (
              rows.map((r, i) => (
                <TableRow key={i}>
                  {r.map((cell, j) => (
                    <TableCell key={j} className={cn("py-2.5", align[j] === "right" && "text-right tabular")}>
                      {cell}
                    </TableCell>
                  ))}
                </TableRow>
              ))
            )}
          </TableBody>
        </Table>
      </div>
    </div>
  );
}

const OPEN_PTP = new Set(["scheduled", "pendingVerification", "financialSyncPending"]);

/** Older money = hotter colour. */
const AGE_TONE = [
  { bg: "bg-green-50 dark:bg-green-500/10", bar: "bg-green-600", text: "text-green-800 dark:text-green-300" },
  { bg: "bg-amber-50 dark:bg-amber-500/10", bar: "bg-amber-500", text: "text-amber-800 dark:text-amber-300" },
  { bg: "bg-orange-50 dark:bg-orange-500/10", bar: "bg-orange-600", text: "text-orange-800 dark:text-orange-300" },
  { bg: "bg-red-50 dark:bg-red-500/10", bar: "bg-red-600", text: "text-red-700 dark:text-red-300" },
] as const;

/** Same bands as creditHealthBand: 85+ low risk, 70+ moderate, 50+ high, below critical. */
function scoreTone(score: number | null) {
  if (score == null) return { bg: "bg-muted/40", border: "border-border", bar: "bg-slate-400", text: "text-muted-foreground" };
  if (score >= 85) return { bg: "bg-green-50 dark:bg-green-500/10", border: "border-green-200 dark:border-green-500/30", bar: "bg-green-600", text: "text-green-800 dark:text-green-300" };
  if (score >= 70) return { bg: "bg-amber-50 dark:bg-amber-500/10", border: "border-amber-200 dark:border-amber-500/30", bar: "bg-amber-500", text: "text-amber-800 dark:text-amber-300" };
  if (score >= 50) return { bg: "bg-orange-50 dark:bg-orange-500/10", border: "border-orange-200 dark:border-orange-500/30", bar: "bg-orange-600", text: "text-orange-800 dark:text-orange-300" };
  return { bg: "bg-red-50 dark:bg-red-500/10", border: "border-red-200 dark:border-red-500/30", bar: "bg-red-600", text: "text-red-700 dark:text-red-300" };
}
