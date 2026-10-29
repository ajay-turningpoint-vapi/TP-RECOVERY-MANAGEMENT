"use client";

import Link from "next/link";
import { useMemo } from "react";
import { ArrowUpRight, CheckCircle2, Siren } from "lucide-react";
import { ActionDialog, useDialog } from "@/components/app/action-dialog";
import { PageHeader } from "@/components/app/page-header";
import { useSessionUser } from "@/components/app/providers";
import { Pill } from "@/components/app/status";
import { Button } from "@/components/ui/button";
import { Card, CardContent } from "@/components/ui/card";
import { Skeleton } from "@/components/ui/skeleton";
import { deadlineInput, localToIso, useRmsAction } from "@/lib/actions";
import { formatDate, formatINR, formatINRCompact, timeAgo } from "@/lib/format";
import type { Escalation } from "@/lib/models";
import { useRms } from "@/lib/queries";
import { cn } from "@/lib/utils";

const COLUMNS = [
  { level: "L2", title: "L2 · RE Supervision", hint: "Review Customer 360, then assign a task, instruct or escalate." },
  { level: "L3", title: "L3 · RE Control", hint: "Needs an RE owner, plan, next action and deadline." },
  { level: "L4", title: "L4 · Management Attention", hint: "Tracked case — not just a red badge." },
] as const;

export function EscalationsView() {
  const rms = useRms();
  const user = useSessionUser();
  const action = useRmsAction();
  const resolve = useDialog<Escalation>();
  const raise = useDialog<Escalation>();

  const open = rms.openEscalations;
  const resolved = useMemo(
    () => rms.escalations.filter((e) => !e.isOpen),
    [rms.escalations],
  );

  return (
    <div className="mx-auto max-w-[1600px]">
      <PageHeader
        title="Escalations"
        description="1st broken PTP = L1 (salesperson leads). 2nd = L2 RE supervision. 3rd = L3 RE control. Serious L3 = L4 management attention."
        actions={
          <div className="text-right">
            <div className="text-xs text-muted-foreground">Money at risk in open cases</div>
            <div className="text-lg font-semibold tabular">{formatINRCompact(open.reduce((s, e) => s + e.moneyAtRisk, 0))}</div>
          </div>
        }
      />
      <div className="grid gap-4 lg:grid-cols-3">
        {COLUMNS.map((col) => {
          const cases = open.filter((e) => e.level === col.level);
          return (
            <section key={col.level} className="flex flex-col rounded-xl border bg-muted/30">
              <header className="border-b px-4 py-3">
                <div className="flex items-center justify-between">
                  <h2 className="text-sm font-semibold">{col.title}</h2>
                  <Pill tone={col.level === "L2" ? "warning" : "danger"}>{cases.length}</Pill>
                </div>
                <p className="mt-0.5 text-xs text-muted-foreground">{col.hint}</p>
              </header>
              <div className="flex-1 space-y-3 p-3">
                {rms.isLoading && <Skeleton className="h-32 w-full" />}
                {!rms.isLoading && cases.length === 0 && <p className="py-8 text-center text-xs text-muted-foreground">No open {col.level} cases.</p>}
                {cases.map((e) => {
                  const late = e.deadline < new Date();
                  return (
                    <Card key={e.id} size="sm" className="gap-3">
                      <CardContent className="space-y-2.5">
                        <div className="flex items-start justify-between gap-2">
                          <Link href={`/customers/${encodeURIComponent(e.customerId)}`} className="font-medium hover:underline">
                            {rms.customerName(e.customerId)}
                          </Link>
                          <span className="shrink-0 text-sm font-semibold tabular">{formatINRCompact(e.moneyAtRisk)}</span>
                        </div>
                        <p className="text-sm text-muted-foreground">{e.reason}</p>
                        {e.plan ? (
                          <p className="rounded-md bg-background px-2 py-1.5 text-xs">
                            <span className="font-medium">Plan:</span> {e.plan}
                          </p>
                        ) : (
                          <Pill tone="danger">No plan recorded</Pill>
                        )}
                        <div className="flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-muted-foreground">
                          <span>Owner: {e.ownerId ? (e.ownerId === user.id ? "You" : rms.salesmanName(e.ownerId)) : "—"}</span>
                          <span className={cn(late && "font-medium text-destructive")}>
                            {late ? "Overdue · " : "Due "}
                            {formatDate(e.deadline)}
                          </span>
                          <span>Opened {timeAgo(e.createdAt)}</span>
                        </div>
                        <div className="flex gap-2 pt-1">
                          <Button size="sm" variant="outline" onClick={() => resolve.open(e)}>
                            <CheckCircle2 /> Resolve
                          </Button>
                          {e.level !== "L4" && (
                            <Button size="sm" variant="outline" onClick={() => raise.open(e)}>
                              <Siren /> To {e.level === "L2" ? "L3" : "L4"}
                            </Button>
                          )}
                          <Button size="icon-sm" variant="ghost" className="ml-auto" render={<Link href={`/customers/${encodeURIComponent(e.customerId)}`} />} aria-label="Open customer">
                            <ArrowUpRight />
                          </Button>
                        </div>
                      </CardContent>
                    </Card>
                  );
                })}
              </div>
            </section>
          );
        })}
      </div>

      <h2 className="mt-8 mb-3 text-sm font-semibold">Resolved ({resolved.length})</h2>
      <div className="overflow-hidden rounded-xl border bg-card">
        {resolved.length === 0 ? (
          <p className="p-6 text-center text-sm text-muted-foreground">No resolved cases yet.</p>
        ) : (
          resolved.map((e) => (
            <div key={e.id} className="flex flex-wrap items-center gap-x-4 gap-y-1 border-b px-4 py-2.5 text-sm last:border-0">
              <Pill tone="success">{e.level}</Pill>
              <Link href={`/customers/${encodeURIComponent(e.customerId)}`} className="font-medium hover:underline">
                {rms.customerName(e.customerId)}
              </Link>
              <span className="text-muted-foreground">{e.reason}</span>
              <span className="ml-auto text-xs text-muted-foreground">
                {formatINR(e.moneyAtRisk)} · resolved {e.resolvedAt ? timeAgo(e.resolvedAt) : ""}
              </span>
            </div>
          ))
        )}
      </div>

      <ActionDialog
        {...resolve.props}
        title="Resolve escalation"
        description={resolve.target ? `${rms.customerName(resolve.target.customerId)} · ${resolve.target.level}` : undefined}
        submitLabel="Resolve"
        fields={[{ name: "note", label: "Resolution note", type: "textarea", required: true }]}
        onSubmit={(v) => action.mutateAsync({ path: `/escalations/${resolve.target!.id}/resolve`, body: { note: v.note }, success: "Escalation resolved." })}
      />
      <ActionDialog
        {...raise.props}
        title={`Escalate to ${raise.target?.level === "L2" ? "L3" : "L4"}`}
        description={raise.target ? rms.customerName(raise.target.customerId) : undefined}
        submitLabel="Escalate"
        destructive
        fields={[
          { name: "reason", label: "Reason", type: "textarea", required: true },
          { name: "plan", label: "Recovery plan", type: "textarea", required: true, defaultValue: raise.target?.plan },
          { name: "deadline", label: "Plan deadline", type: "datetime", required: true, defaultValue: deadlineInput(3, 18) },
        ]}
        onSubmit={(v) =>
          action.mutateAsync({
            path: `/escalations/customer/${encodeURIComponent(raise.target!.customerId)}`,
            body: {
              level: raise.target!.level === "L2" ? "L3" : "L4",
              reason: v.reason,
              plan: v.plan,
              ownerId: user.id,
              deadline: localToIso(v.deadline),
              moneyAtRisk: raise.target!.moneyAtRisk,
            },
            success: "Escalated.",
          })
        }
      />
    </div>
  );
}
