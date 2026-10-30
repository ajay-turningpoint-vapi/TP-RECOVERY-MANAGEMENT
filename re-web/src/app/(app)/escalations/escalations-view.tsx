"use client";

import Link from "next/link";
import { useMemo, useState } from "react";
import { ChevronDown, ChevronRight, CircleCheck, Siren, TriangleAlert, UserRound } from "lucide-react";
import { ActionDialog, useDialog } from "@/components/app/action-dialog";
import { PageHeader } from "@/components/app/page-header";
import { useSessionUser } from "@/components/app/providers";
import { Button } from "@/components/ui/button";
import { Skeleton } from "@/components/ui/skeleton";
import { deadlineInput, localToIso, useRmsAction } from "@/lib/actions";
import { formatINR, timeAgo } from "@/lib/format";
import type { Escalation } from "@/lib/models";
import { useRms } from "@/lib/queries";
import { useUrlState } from "@/lib/use-url-state";
import { cn } from "@/lib/utils";
import { format } from "date-fns";

/** Same L2 / L3 / L4 / Resolved tabs as the mobile Escalations screen. */
const TABS = [
  {
    key: "L2",
    label: "L2",
    name: "You keep watch",
    help: "The customer broke a payment promise twice. Check the customer and give the salesman a task.",
    tab: "data-active:bg-amber-500",
    band: "border-amber-300 bg-amber-50 text-amber-950 dark:bg-amber-500/10 dark:text-amber-100",
    stripe: "border-l-amber-500",
  },
  {
    key: "L3",
    label: "L3",
    name: "You take charge",
    help: "Broken three times. You now own the case — write a plan and a date for each one.",
    tab: "data-active:bg-orange-600",
    band: "border-orange-300 bg-orange-50 text-orange-950 dark:bg-orange-500/10 dark:text-orange-100",
    stripe: "border-l-orange-600",
  },
  {
    key: "L4",
    label: "L4",
    name: "Management must help",
    help: "The most serious cases. Management is following these.",
    tab: "data-active:bg-red-700",
    band: "border-red-300 bg-red-50 text-red-950 dark:bg-red-500/10 dark:text-red-100",
    stripe: "border-l-red-700",
  },
  {
    key: "solved",
    label: "Solved",
    name: "Closed cases",
    help: "Cases that have been marked as solved.",
    tab: "data-active:bg-green-700",
    band: "border-green-300 bg-green-50 text-green-950 dark:bg-green-500/10 dark:text-green-100",
    stripe: "border-l-green-600",
  },
] as const;

/** "3 confirmed Broken PTP (each reconciled …)" → "Broke a payment promise 3 times". Falls back to the original text. */
function shortReason(reason: string) {
  const m = reason.match(/(\d+)\s+confirmed\s+broken\s+ptp/i);
  if (m) return `Broke a payment promise ${m[1]} times`;
  return reason;
}

export function EscalationsView() {
  const rms = useRms();
  const user = useSessionUser();
  const action = useRmsAction();
  const resolve = useDialog<Escalation>();
  const raise = useDialog<Escalation>();
  const [tab, setTab] = useUrlState("level", "L2");

  const byTab = useMemo(
    () => ({
      L2: rms.openEscalations.filter((e) => e.level === "L2"),
      L3: rms.openEscalations.filter((e) => e.level === "L3"),
      L4: rms.openEscalations.filter((e) => e.level === "L4"),
      solved: rms.escalations.filter((e) => !e.isOpen),
    }),
    [rms.openEscalations, rms.escalations],
  );
  const current = TABS.find((t) => t.key === tab) ?? TABS[0];
  const cases = byTab[current.key];
  const openMoney = rms.openEscalations.reduce((s, e) => s + e.moneyAtRisk, 0);

  return (
    <div className="mx-auto max-w-[1400px]">
      <PageHeader
        icon={<Siren />}
        hue="rose"
        title="Escalations"
        description="Customers who broke their payment promise again and again."
        actions={
          <div className="rounded-xl border-2 bg-card px-4 py-2 text-right">
            <div className="text-sm text-muted-foreground">Money in open cases</div>
            <div className="text-xl font-bold text-red-700 tabular dark:text-red-300">{formatINR(openMoney)}</div>
          </div>
        }
      />

      {/* Big level tabs with counts */}
      <div role="tablist" className="mb-4 grid grid-cols-2 gap-3 md:grid-cols-4">
        {TABS.map((t) => {
          const active = t.key === current.key;
          return (
            <button
              key={t.key}
              role="tab"
              aria-selected={active}
              data-active={active ? "" : undefined}
              onClick={() => setTab(t.key)}
              className={cn(
                "rounded-xl border-2 bg-card p-4 text-left transition-colors hover:border-primary",
                "data-active:border-transparent data-active:text-white",
                t.tab,
              )}
            >
              <div className="flex items-baseline justify-between gap-2">
                <span className="text-lg font-bold">{t.label}</span>
                <span className="text-2xl font-bold tabular">{rms.isLoading ? "…" : byTab[t.key].length}</span>
              </div>
              <div className={cn("text-sm", active ? "text-white/90" : "text-muted-foreground")}>{t.name}</div>
            </button>
          );
        })}
      </div>

      {/* What this level means, in one sentence */}
      <div className={cn("mb-5 rounded-xl border-2 px-5 py-3 text-[15px]", current.band)}>
        <span className="font-bold">
          {current.label} · {current.name}.
        </span>{" "}
        {current.help}
      </div>

      {rms.isLoading ? (
        <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
          {[0, 1, 2].map((k) => (
            <Skeleton key={k} className="h-56 w-full rounded-xl" />
          ))}
        </div>
      ) : cases.length === 0 ? (
        <div className="flex items-center gap-3 rounded-xl border-2 bg-card p-8 text-lg">
          <CircleCheck className="size-6 text-green-700" />
          {current.key === "solved" ? "No solved cases yet." : `No open ${current.label} cases. Good.`}
        </div>
      ) : (
        <div className="grid gap-4 md:grid-cols-2 xl:grid-cols-3">
          {cases.map((e) => (
            <CaseCard
              key={e.id}
              e={e}
              stripe={current.stripe}
              name={rms.customerName(e.customerId)}
              owner={e.ownerId ? (e.ownerId === user.id ? "You" : rms.salesmanName(e.ownerId)) : "—"}
              onResolve={() => resolve.open(e)}
              onRaise={() => raise.open(e)}
            />
          ))}
        </div>
      )}

      <ActionDialog
        {...resolve.props}
        title="Mark this case as solved"
        description={resolve.target ? `${rms.customerName(resolve.target.customerId)} · ${resolve.target.level}` : undefined}
        submitLabel="Mark solved"
        fields={[{ name: "note", label: "What was done to solve it?", type: "textarea", required: true }]}
        onSubmit={(v) => action.mutateAsync({ path: `/escalations/${resolve.target!.id}/resolve`, body: { note: v.note }, success: "Case marked as solved." })}
      />
      <ActionDialog
        {...raise.props}
        title={`Move to ${raise.target?.level === "L2" ? "L3" : "L4"}`}
        description={raise.target ? rms.customerName(raise.target.customerId) : undefined}
        submitLabel="Move up"
        destructive
        fields={[
          { name: "reason", label: "Why move it up?", type: "textarea", required: true },
          { name: "plan", label: "What is the plan?", type: "textarea", required: true, defaultValue: raise.target?.plan },
          { name: "deadline", label: "Plan finish date", type: "datetime", required: true, defaultValue: deadlineInput(3, 18) },
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
            success: "Case moved up.",
          })
        }
      />
    </div>
  );
}

function CaseCard({
  e,
  stripe,
  name,
  owner,
  onResolve,
  onRaise,
}: {
  e: Escalation;
  stripe: string;
  name: string;
  owner: string;
  onResolve: () => void;
  onRaise: () => void;
}) {
  const [showPlan, setShowPlan] = useState(false);
  const late = e.isOpen && e.deadline < new Date();

  return (
    <article className={cn("flex flex-col rounded-xl border-2 border-l-[6px] bg-card", stripe)}>
      <div className="space-y-3 p-4">
        {/* Who + how much */}
        <div>
          <Link href={`/customers/${encodeURIComponent(e.customerId)}`} className="text-base leading-snug font-bold break-words hover:underline">
            {name}
          </Link>
          <div className="mt-1 text-2xl font-bold text-red-700 tabular dark:text-red-300">{formatINR(e.moneyAtRisk)}</div>
          <div className="text-sm text-muted-foreground">money at risk</div>
        </div>

        {/* What happened, short */}
        <div className="flex items-start gap-2 rounded-lg bg-muted/60 px-3 py-2 text-[15px] font-medium">
          <TriangleAlert className="mt-0.5 size-4 shrink-0 text-amber-700" />
          <span className="break-words">{shortReason(e.reason)}</span>
        </div>

        {/* Facts */}
        <dl className="space-y-1.5 text-[15px]">
          <div className="flex items-center justify-between gap-3">
            <dt className="flex items-center gap-1.5 text-muted-foreground">
              <UserRound className="size-4" /> Handled by
            </dt>
            <dd className="text-right font-semibold">{owner}</dd>
          </div>
          {e.isOpen && (
            <div className="flex items-center justify-between gap-3">
              <dt className="text-muted-foreground">Plan due</dt>
              <dd className={cn("text-right font-semibold", late && "text-red-700 dark:text-red-300")}>
                {late && "Late · "}
                {format(e.deadline, "d MMM yyyy")}
              </dd>
            </div>
          )}
          <div className="flex items-center justify-between gap-3">
            <dt className="text-muted-foreground">{e.isOpen ? "Opened" : "Solved"}</dt>
            <dd className="text-right font-semibold">{timeAgo(e.isOpen ? e.createdAt : (e.resolvedAt ?? e.createdAt))}</dd>
          </div>
        </dl>

        {/* Plan: a clear yes/no, details on request */}
        {e.plan.trim() ? (
          <div>
            <button
              type="button"
              onClick={() => setShowPlan((s) => !s)}
              className="flex items-center gap-1.5 text-[15px] font-semibold text-green-800 dark:text-green-300"
            >
              <CircleCheck className="size-4" /> Plan written
              <span className="ml-1 inline-flex items-center text-sm font-medium text-primary">
                {showPlan ? "Hide plan" : "See plan"} {showPlan ? <ChevronDown className="size-4" /> : <ChevronRight className="size-4" />}
              </span>
            </button>
            {showPlan && <p className="mt-2 rounded-lg border-2 bg-muted/40 p-3 text-sm">{e.plan}</p>}
          </div>
        ) : (
          <p className="flex items-center gap-1.5 text-[15px] font-semibold text-red-700 dark:text-red-300">
            <TriangleAlert className="size-4" /> No plan yet
          </p>
        )}
      </div>

      {e.isOpen && (
        <div className="mt-auto grid grid-cols-2 gap-2 border-t-2 p-3">
          <Button variant="outline" onClick={onResolve}>
            <CircleCheck /> Mark solved
          </Button>
          {e.level !== "L4" ? (
            <Button variant="outline" onClick={onRaise}>
              <Siren /> Move to {e.level === "L2" ? "L3" : "L4"}
            </Button>
          ) : (
            <Button variant="outline" render={<Link href={`/customers/${encodeURIComponent(e.customerId)}`} />}>
              Open customer
            </Button>
          )}
        </div>
      )}
    </article>
  );
}
