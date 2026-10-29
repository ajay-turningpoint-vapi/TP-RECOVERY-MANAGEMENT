"use client";

import Link from "next/link";
import { useMemo, useState } from "react";
import { format } from "date-fns";
import { CalendarX2, ClipboardX, Printer, RefreshCw, Siren, TriangleAlert, UserX } from "lucide-react";
import { PageHeader } from "@/components/app/page-header";
import { Pill, PriorityBadge } from "@/components/app/status";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { formatDateTime, formatINR } from "@/lib/format";
import { TASK_TYPE_LABEL } from "@/lib/models";
import { useRms } from "@/lib/queries";
import { cn } from "@/lib/utils";

/**
 * 5 PM Control (spec §51) — what is still unresolved at the end of the
 * working day. Same rules as AppStore.runFivePmControl; the server's
 * missed-deadline job records the permanent history events.
 */
export function ControlView() {
  const rms = useRms();
  const [stamp, setStamp] = useState(() => Date.now());
  // eslint-disable-next-line react-hooks/exhaustive-deps
  const snap = useMemo(() => rms.fivePmControl(), [rms, stamp]);

  const tiles = [
    { label: "Overdue tasks", value: snap.overdueTasks.length, icon: ClipboardX },
    { label: "Critical tasks not completed", value: snap.mandatoryNotDone.length, icon: TriangleAlert },
    { label: "Broken PTP without next action", value: snap.brokenNoNext.length, icon: CalendarX2 },
    { label: "Ownerless exposure", value: formatINR(snap.ownerlessExposure), icon: UserX, bad: snap.ownerlessExposure > 0 },
    { label: "L3 cases without plan", value: snap.l3NoPlan.length, icon: Siren },
  ];

  return (
    <div className="mx-auto max-w-[1400px] space-y-6 print:max-w-none">
      <PageHeader
        eyebrow={`Snapshot · ${format(snap.timestamp, "dd MMM yyyy, h:mm a")}`}
        title="5 PM Control"
        description="End-of-day check of unresolved mandatory work. Resolve or re-plan each item before you sign off."
        actions={
          <>
            <Button variant="outline" onClick={() => setStamp(Date.now())}>
              <RefreshCw /> Re-run
            </Button>
            <Button variant="outline" onClick={() => window.print()}>
              <Printer /> Print
            </Button>
          </>
        }
      />
      <div className="grid grid-cols-2 gap-3 md:grid-cols-5">
        {tiles.map((t) => {
          const bad = "bad" in t ? t.bad : (t.value as number) > 0;
          return (
            <div key={t.label} className={cn("rounded-xl border bg-card p-4 shadow-xs", bad && "border-destructive/30 bg-destructive/5")}>
              <t.icon className={cn("size-4", bad ? "text-destructive" : "text-success")} />
              <div className={cn("mt-2 text-2xl font-semibold tabular", bad && "text-destructive")}>{t.value}</div>
              <div className="text-xs text-muted-foreground">{t.label}</div>
            </div>
          );
        })}
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        <Section title="Overdue tasks" description="Open past their deadline." empty="No overdue tasks.">
          {snap.overdueTasks
            .sort((a, b) => +a.deadline - +b.deadline)
            .slice(0, 50)
            .map((t) => (
              <Row key={t.id} href={`/customers/${encodeURIComponent(t.customerId)}`} title={`${TASK_TYPE_LABEL[t.type]} · ${t.customerName}`} sub={`${rms.salesmanName(t.ownerId)} · due ${formatDateTime(t.deadline)}`} right={<PriorityBadge priority={t.priority} />} />
            ))}
        </Section>
        <Section title="Broken PTP without next action" description="Broken promise and nothing valid planned." empty="Every broken PTP has a next action.">
          {snap.brokenNoNext.map((p) => (
            <Row key={p.id} href={`/customers/${encodeURIComponent(p.customerId)}`} title={rms.customerName(p.customerId)} sub={`Promised ${formatINR(p.amountPromised)}`} right={<Pill tone="danger">Broken</Pill>} />
          ))}
        </Section>
        <Section title="Ownerless exposure" description="Overdue with no mapped salesman — must stay visible until owned." empty="All exposure is owned.">
          {snap.ownerlessCustomers.map((c) => (
            <Row key={c.id} href={`/customers/${encodeURIComponent(c.id)}`} title={c.name} sub={c.branch} right={<span className="font-semibold tabular">{formatINR(c.totalDue)}</span>} />
          ))}
        </Section>
        <Section title="L3 cases without a plan" description="RE control cases need a written plan and deadline." empty="Every L3 case has a plan.">
          {snap.l3NoPlan.map((e) => (
            <Row key={e.id} href={`/customers/${encodeURIComponent(e.customerId)}`} title={rms.customerName(e.customerId)} sub={e.reason} right={<span className="tabular">{formatINR(e.moneyAtRisk)}</span>} />
          ))}
        </Section>
      </div>
    </div>
  );
}

function Section({ title, description, empty, children }: { title: string; description: string; empty: string; children: React.ReactNode[] }) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>
          {title} <span className="ml-1 text-muted-foreground tabular">{children.length}</span>
        </CardTitle>
        <CardDescription>{description}</CardDescription>
      </CardHeader>
      <CardContent className="max-h-96 space-y-1 overflow-y-auto">
        {children.length ? children : <p className="py-6 text-center text-sm text-success">{empty}</p>}
      </CardContent>
    </Card>
  );
}

function Row({ href, title, sub, right }: { href: string; title: string; sub: string; right: React.ReactNode }) {
  return (
    <Link href={href} className="flex items-center justify-between gap-3 rounded-lg px-2 py-2 hover:bg-muted">
      <div className="min-w-0">
        <div className="truncate text-sm font-medium">{title}</div>
        <div className="truncate text-xs text-muted-foreground">{sub}</div>
      </div>
      <div className="shrink-0">{right}</div>
    </Link>
  );
}
