"use client";

import Link from "next/link";
import { useMemo, useState } from "react";
import { format } from "date-fns";
import { AlarmClock, Check, ChevronRight, Printer, RefreshCw, X } from "lucide-react";
import { PageHeader } from "@/components/app/page-header";
import { GradientBar } from "@/components/app/visual";
import { Button } from "@/components/ui/button";
import { formatINR } from "@/lib/format";
import { useRms } from "@/lib/queries";
import { cn } from "@/lib/utils";

/**
 * End-of-Day Check (5 PM Control, spec §51) — a short checklist, not a
 * second copy of My Tasks or Approvals. Each line answers one question
 * with a count (same rules as AppStore.runFivePmControl) and sends the
 * RE to the one page where it is fixed.
 */
export function ControlView() {
  const rms = useRms();
  const [stamp, setStamp] = useState(() => Date.now());
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const snap = useMemo(() => rms.fivePmControl(), [rms, stamp]);
  // Each check counts exactly what its "Go fix it" page shows, so the
  // number here always matches the number she sees after clicking.
  const work = useMemo(() => {
    const now = new Date();
    const open = rms.buildWorkItems().filter((i) => !i.isDone);
    return { late: open.filter((i) => i.date < now).length, urgent: open.filter((i) => i.priority === "HIGH").length };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [rms, stamp]);

  const checks: { question: string; problem: (n: number) => string; count: number; extra?: string; href: string; where: string }[] = [
    {
      question: "Have you answered every request from salesmen?",
      problem: (n) => `${n} request${n === 1 ? " is" : "s are"} still waiting for your yes or no.`,
      count: rms.approvalInboxCount,
      href: "/approvals",
      where: "Approvals",
    },
    {
      question: "Have you decided every bill dispute?",
      problem: (n) => `${n} dispute${n === 1 ? " is" : "s are"} waiting for your decision.`,
      count: rms.disputesNeedingAction.length,
      href: "/disputes?stage=decide",
      where: "Disputes — Needs your decision",
    },
    {
      question: "Were all tasks done on time?",
      problem: (n) => `${n} task${n === 1 ? " is" : "s are"} late.`,
      count: work.late,
      href: "/tasks?filter=overdue",
      where: "My Tasks — Late",
    },
    {
      question: "Are all urgent tasks finished?",
      problem: (n) => `${n} urgent task${n === 1 ? " is" : "s are"} not finished.`,
      count: work.urgent,
      href: "/tasks?priority=HIGH",
      where: "My Tasks — Urgent",
    },
    {
      question: "Does every customer with overdue money have a next step planned?",
      problem: (n) => `${n} customer${n === 1 ? " has" : "s have"} no next step planned.`,
      count: rms.noValidNextAction.length,
      href: "/queue?view=no-next-action",
      where: "Follow-up List — No next step",
    },
    {
      question: "Does every customer with overdue money have a salesman?",
      problem: (n) => `${n} customer${n === 1 ? " has" : "s have"} no salesman.`,
      count: rms.ownerMappingRequired.filter((c) => c.totalDue > 0).length,
      extra: snap.ownerlessExposure > 0 ? `${formatINR(snap.ownerlessExposure)} overdue with nobody chasing it.` : undefined,
      href: "/queue?view=ownerless",
      where: "Follow-up List — No salesman",
    },
    {
      question: "Does every serious (L3) case have a written plan?",
      problem: (n) => `${n} serious case${n === 1 ? " has" : "s have"} no plan.`,
      count: snap.l3NoPlan.length,
      href: "/escalations",
      where: "Escalations",
    },
  ];

  const done = checks.filter((c) => c.count === 0).length;

  return (
    <div className="mx-auto max-w-[1000px] space-y-6 print:max-w-none">
      <PageHeader
        icon={<AlarmClock />}
        hue="amber"
        eyebrow={`Checked at ${format(snap.timestamp, "h:mm a, d MMM yyyy")}`}
        title="End-of-Day Check"
        description="Before you finish for the day, go through these questions. Fix anything marked in red."
        actions={
          <>
            <Button variant="outline" onClick={() => setStamp(Date.now())}>
              <RefreshCw /> Check again
            </Button>
            <Button variant="outline" onClick={() => window.print()}>
              <Printer /> Print
            </Button>
          </>
        }
      />

      {rms.loadFailed ? (
        <div role="alert" className="rounded-xl border-2 border-red-200 bg-red-50 p-6 text-[15px] dark:bg-red-500/10">
          The check could not run because the data did not load. Press <span className="font-semibold">Try again</span> at the top of the page.
        </div>
      ) : rms.isLoading ? (
        <div className="space-y-3" aria-label="Loading">
          {[0, 1, 2, 3].map((k) => (
            <div key={k} className="h-24 animate-pulse rounded-xl border-2 bg-muted/60" />
          ))}
        </div>
      ) : (
      <>
      {/* Score */}
      <div className={cn("rounded-xl border-2 p-5", done === checks.length ? "border-green-300 bg-green-50 dark:bg-green-500/10" : "bg-card")}>
        <div className="flex flex-wrap items-baseline justify-between gap-2">
          <p className="text-xl font-bold">
            {done === checks.length ? "All done for today. Well done!" : `${done} of ${checks.length} checks are done`}
          </p>
          {done < checks.length && <p className="text-[15px] text-muted-foreground">{checks.length - done} still need you</p>}
        </div>
        <GradientBar value={(done / checks.length) * 100} hue="emerald" className="mt-3 h-3" />
      </div>

      {/* Checklist */}
      <ol className="space-y-3">
        {checks.map((c, i) => {
          const ok = c.count === 0;
          return (
            <li
              key={c.question}
              className={cn(
                "flex flex-col gap-4 rounded-xl border-2 bg-card p-5 sm:flex-row sm:items-center",
                ok ? "border-green-200 dark:border-green-500/30" : "border-red-200 dark:border-red-500/30",
              )}
            >
              <span
                className={cn(
                  "flex size-11 shrink-0 items-center justify-center rounded-full text-white",
                  ok ? "bg-green-600" : "bg-red-600",
                )}
                aria-label={ok ? "Done" : "Needs action"}
              >
                {ok ? <Check className="size-6" /> : <X className="size-6" />}
              </span>
              <div className="min-w-0 flex-1">
                <p className="text-[15px] text-muted-foreground">Check {i + 1}</p>
                <p className="text-lg font-semibold">{c.question}</p>
                {ok ? (
                  <p className="text-[15px] font-medium text-green-700 dark:text-green-300">Yes — nothing to do here.</p>
                ) : (
                  <>
                    <p className="text-[15px] font-medium text-red-700 dark:text-red-300">{c.problem(c.count)}</p>
                    {c.extra && <p className="text-[15px] text-muted-foreground">{c.extra}</p>}
                  </>
                )}
              </div>
              {!ok && (
                <Button size="lg" render={<Link href={c.href} />} className="shrink-0">
                  Go fix it <ChevronRight />
                </Button>
              )}
              {!ok && <span className="sr-only">Opens {c.where}</span>}
            </li>
          );
        })}
      </ol>
      </>
      )}
    </div>
  );
}
