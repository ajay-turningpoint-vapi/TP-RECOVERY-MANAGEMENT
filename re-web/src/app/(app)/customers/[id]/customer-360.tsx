"use client";

import { useMemo } from "react";
import Link from "next/link";
import { useInfiniteQuery, useQuery } from "@tanstack/react-query";
import {
  ArrowLeft,
  ClipboardPlus,
  Loader2,
  MoreHorizontal,
  Phone,
  ShieldAlert,
  ShieldCheck,
  ShieldOff,
  Siren,
  UserRoundCog,
} from "lucide-react";
import { ActionDialog, useDialog } from "@/components/app/action-dialog";
import { AttachmentLink } from "@/components/app/attachment-link";
import { useSessionUser } from "@/components/app/providers";
import {
  ClaimStatusBadge,
  CreditHealthBadge,
  DisputeStatusBadge,
  EscalationBadge,
  Pill,
  PriorityBadge,
  PtpStatusBadge,
  RecoveryStateBadge,
} from "@/components/app/status";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Skeleton } from "@/components/ui/skeleton";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { deadlineInput, localToIso, useRmsAction } from "@/lib/actions";
import { rmsGet } from "@/lib/api";
import { formatDate, formatDateTime, formatINR, formatRelativeDay, timeAgo } from "@/lib/format";
import { TASK_TYPE_LABEL, friendlyTaskReason, isTaskOpen, parseAuditEvent, parseCustomer } from "@/lib/models";
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
  const events = (audit.data?.pages ?? []).flatMap((p) => p.items.map(parseAuditEvent));

  const instruct = useDialog();
  const reassign = useDialog();
  const escalate = useDialog();
  const control = useDialog<"take" | "release">();

  if (!c) {
    return detail.isError ? (
      <div className="mx-auto max-w-xl py-20 text-center">
        <h1 className="text-lg font-semibold">Customer not found</h1>
        <p className="mt-1 text-sm text-muted-foreground">They may have been removed from BUSY or are outside your scope.</p>
        <Button className="mt-6" variant="outline" render={<Link href="/customers" />}>
          Back to customers
        </Button>
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
  const inReControl = c.currentRecoveryState === "RE Control";
  const salesman = rms.salesmanById.get(c.assignedSalesmanId);

  return (
    <div className="mx-auto max-w-[1400px] space-y-5">
      <Button variant="ghost" size="sm" className="-ml-2 text-muted-foreground" onClick={() => history.back()}>
        <ArrowLeft />
        Back
      </Button>

      {/* Header */}
      <div className="flex flex-col gap-4 rounded-xl border bg-card p-5 shadow-xs lg:flex-row lg:items-start lg:justify-between">
        <div className="min-w-0 space-y-2">
          <div className="flex flex-wrap items-center gap-2">
            <h1 className="text-2xl font-semibold tracking-tight">{c.name}</h1>
            <RecoveryStateBadge state={c.currentRecoveryState} />
            <EscalationBadge level={c.escalationLevel} />
            {c.ownerMappingRequired && <Pill tone="danger">Owner mapping required</Pill>}
            {!c.hasValidNextAction && c.totalDue > 0 && <Pill tone="warning">No valid next action</Pill>}
          </div>
          <div className="flex flex-wrap gap-x-5 gap-y-1 text-sm text-muted-foreground">
            <span>{c.id}</span>
            <span>{c.branch}</span>
            {c.contactNumber && (
              <a href={`tel:${c.contactNumber}`} className="inline-flex items-center gap-1 hover:text-foreground">
                <Phone className="size-3.5" />
                {c.contactNumber}
              </a>
            )}
            {c.alternateContactNumber && <span>Alt: {c.alternateContactNumber}</span>}
            <span>
              Salesman:{" "}
              {salesman ? (
                <Link href={`/salesmen/${encodeURIComponent(salesman.id)}`} className="font-medium text-foreground hover:underline">
                  {salesman.fullName}
                </Link>
              ) : (
                <span className="text-destructive">Unmapped</span>
              )}
              {salesman?.phone && (
                <a href={`tel:${salesman.phone}`} className="ml-1.5 inline-flex items-center gap-1 hover:text-foreground">
                  <Phone className="size-3" />
                  {salesman.phone}
                </a>
              )}
            </span>
          </div>
          {c.primaryNextAction && (
            <div className="text-sm">
              <span className="text-muted-foreground">Primary next action:</span>{" "}
              <span className="font-medium">{c.primaryNextAction}</span>
              {c.reasonForAction && <span className="text-muted-foreground"> — {c.reasonForAction}</span>}
            </div>
          )}
          <div className="text-xs text-muted-foreground">
            Financials synced from BUSY {c.financialFreshness ? timeAgo(c.financialFreshness) : "—"}
          </div>
        </div>
        <div className="flex shrink-0 flex-wrap gap-2">
          <Button onClick={() => instruct.open(true)} disabled={!!c.outcomeWaitText}>
            <ClipboardPlus />
            Create task
          </Button>
          <Button variant="outline" onClick={() => escalate.open(true)} disabled={c.escalationLevel === "L4"}>
            <Siren />
            Escalate to {NEXT_LEVEL[c.escalationLevel]}
          </Button>
          <DropdownMenu>
            <DropdownMenuTrigger render={<Button variant="outline" size="icon" aria-label="More actions" />}>
              <MoreHorizontal />
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end" className="w-56">
              <DropdownMenuItem onClick={() => reassign.open(true)}>
                <UserRoundCog />
                Reassign salesman
              </DropdownMenuItem>
              <DropdownMenuSeparator />
              {inReControl ? (
                <DropdownMenuItem onClick={() => control.open("release")}>
                  <ShieldOff />
                  Release RE control
                </DropdownMenuItem>
              ) : (
                <DropdownMenuItem onClick={() => control.open("take")}>
                  <ShieldCheck />
                  Take RE control
                </DropdownMenuItem>
              )}
            </DropdownMenuContent>
          </DropdownMenu>
        </div>
      </div>

      {c.outcomeWaitText && (
        <Alert>
          <ShieldAlert />
          <AlertDescription>{c.outcomeWaitText} New tasks can be created once this resolves.</AlertDescription>
        </Alert>
      )}

      {/* Financial strip */}
      <div className="grid grid-cols-2 gap-px overflow-hidden rounded-xl border bg-border sm:grid-cols-4">
        {[
          ["Outstanding", formatINR(c.totalOutstanding)],
          ["Overdue", formatINR(c.totalDue)],
          ["Covered (PTP / dispute / claim)", formatINR(c.coveredAmount)],
          ["Actionable now", formatINR(c.actionableAmount)],
          ["Disputed", formatINR(c.disputedAmount)],
          ["Oldest overdue", `${c.oldestOverdueDays} days`],
          ["Credit limit / available", `${formatINR(c.creditLimit)} / ${formatINR(c.availableLimit)}`],
          ["Last payment", c.lastPaymentDate ? `${formatINR(c.lastPaymentAmount)} · ${formatDate(c.lastPaymentDate, "dd MMM")}` : "—"],
        ].map(([k, v]) => (
          <div key={k} className="bg-card px-4 py-3">
            <div className="truncate text-xs text-muted-foreground">{k}</div>
            <div className="mt-0.5 truncate text-sm font-semibold tabular">{v}</div>
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
          <TabsTrigger value="timeline">Timeline</TabsTrigger>
        </TabsList>

        <TabsContent value="overview" className="mt-4 grid gap-4 lg:grid-cols-3">
          <Card>
            <CardHeader>
              <CardTitle>Ageing</CardTitle>
            </CardHeader>
            <CardContent className="space-y-2.5">
              {(
                [
                  ["0–30 days", c.ageing.age0_30],
                  ["31–60 days", c.ageing.age31_60],
                  ["61–90 days", c.ageing.age61_90],
                  ["90+ days", c.ageing.age90Plus],
                ] as const
              ).map(([k, v]) => {
                const total = c.ageing.age0_30 + c.ageing.age31_60 + c.ageing.age61_90 + c.ageing.age90Plus;
                return (
                  <div key={k} className="space-y-1">
                    <div className="flex justify-between text-sm">
                      <span className="text-muted-foreground">{k}</span>
                      <span className="font-medium tabular">{formatINR(v)}</span>
                    </div>
                    <div className="h-1.5 overflow-hidden rounded-full bg-muted">
                      <div className="h-full rounded-full bg-chart-1" style={{ width: `${total ? (v / total) * 100 : 0}%` }} />
                    </div>
                  </div>
                );
              })}
              {c.futureDue > 0 && <div className="pt-1 text-xs text-muted-foreground">Not yet due: {formatINR(c.futureDue)}</div>}
            </CardContent>
          </Card>
          <Card>
            <CardHeader>
              <CardTitle>Risk</CardTitle>
            </CardHeader>
            <CardContent className="space-y-3 text-sm">
              <div className="flex items-center justify-between">
                <span className="text-muted-foreground">Customer credit health</span>
                <CreditHealthBadge score={c.creditHealthScore} />
              </div>
              {c.creditHealthComponents &&
                Object.entries(c.creditHealthComponents).map(([k, v]) => (
                  <div key={k} className="flex justify-between text-xs">
                    <span className="text-muted-foreground capitalize">{k.replace(/([A-Z])/g, " $1").toLowerCase()}</span>
                    <span className="tabular">{v}</span>
                  </div>
                ))}
              <div className="flex justify-between">
                <span className="text-muted-foreground">No-answer attempts</span>
                <span className="tabular">{c.noAnswerAttempts}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-muted-foreground">Credit days</span>
                <span className="tabular">{c.creditDays}</span>
              </div>
              {c.gstNo && (
                <div className="flex justify-between">
                  <span className="text-muted-foreground">GST</span>
                  <span>{c.gstNo}</span>
                </div>
              )}
              {c.address && <div className="text-xs text-muted-foreground">{c.address}</div>}
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
              p.attachmentPath ? <AttachmentLink key="a" path={p.attachmentPath} /> : "—",
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
                <div className="space-y-3">
                  {Array.from({ length: 5 }).map((_, i) => (
                    <Skeleton key={i} className="h-12 w-full" />
                  ))}
                </div>
              ) : events.length === 0 ? (
                <p className="text-sm text-muted-foreground">No history yet.</p>
              ) : (
                <ol className="relative space-y-5 border-l pl-6">
                  {events.map((e, i) => (
                    <li key={e.id ?? i} className="relative">
                      <span
                        className={cn(
                          "absolute top-1.5 -left-[29px] size-2.5 rounded-full ring-4 ring-card",
                          e.actor === "System" ? "bg-muted-foreground/40" : "bg-primary",
                        )}
                      />
                      <div className="flex flex-wrap items-baseline gap-x-2 text-xs text-muted-foreground">
                        <span className="font-medium text-foreground">{e.actor}</span>
                        <span>{formatDateTime(e.timestamp)}</span>
                        <span>· {e.source}</span>
                        {e.previousState && e.newState && (
                          <span>
                            · {e.previousState} → {e.newState}
                          </span>
                        )}
                      </div>
                      <p className="mt-0.5 text-sm">{e.description}</p>
                      {e.attachmentPath && <AttachmentLink path={e.attachmentPath} />}
                    </li>
                  ))}
                </ol>
              )}
              {audit.hasNextPage && (
                <Button variant="outline" size="sm" className="mt-6" onClick={() => audit.fetchNextPage()} disabled={audit.isFetchingNextPage}>
                  {audit.isFetchingNextPage && <Loader2 className="animate-spin" />}
                  Load older history
                </Button>
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
            success: "Task created and sent to the salesman.",
          })
        }
      />
      <ActionDialog
        {...reassign.props}
        title="Reassign salesman"
        description="Changes the current owner only. History stays with this customer and is never rewritten."
        submitLabel="Reassign"
        fields={[
          { name: "toSalesmanId", label: "New salesman", type: "select", required: true, options: salesmanOptions.filter((o) => o.value !== c.assignedSalesmanId) },
          { name: "reason", label: "Reason", type: "textarea", required: true },
        ]}
        onSubmit={(v) =>
          action.mutateAsync({
            path: `/customers/${encodeURIComponent(c.id)}/reassign`,
            body: v,
            success: "Customer reassigned.",
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
      <ActionDialog
        {...control.props}
        title={control.target === "release" ? "Release RE control" : "Take RE control"}
        description={
          control.target === "release"
            ? "Recovery ownership returns to the assigned salesperson, who must set the next action."
            : "You take direct ownership of the recovery approach. The salesperson's open tasks on this account are superseded."
        }
        submitLabel={control.target === "release" ? "Release control" : "Take control"}
        destructive={control.target === "take"}
        fields={[]}
        onSubmit={() =>
          action.mutateAsync({
            path: `/customers/${encodeURIComponent(c.id)}/${control.target === "release" ? "release-control" : "take-control"}`,
            success: control.target === "release" ? "Control released to the salesperson." : "You now have RE control of this account.",
          })
        }
      />
    </div>
  );
}

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
