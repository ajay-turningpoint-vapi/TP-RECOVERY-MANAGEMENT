"use client";

import { useMemo, useState } from "react";
import { Inbox } from "lucide-react";
import { DisputePanel } from "@/components/app/dispute-panel";
import { PageHeader } from "@/components/app/page-header";
import { PriorityBadge } from "@/components/app/status";
import { TaskDetail } from "@/components/app/task-sheet";
import { Input } from "@/components/ui/input";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { formatINR, timeAgo } from "@/lib/format";
import type { PaymentClaim } from "@/lib/models";
import { useRms } from "@/lib/queries";
import { reviewDeadline, type ReTaskItem, type RmsView } from "@/lib/selectors";
import { useUrlState } from "@/lib/use-url-state";
import { cn } from "@/lib/utils";

/** A payment claim as a queue item — built from the unfiltered list, like the mobile Payments tab. */
function claimItem(c: PaymentClaim, rms: RmsView): ReTaskItem {
  const cust = rms.customerById.get(c.customerId);
  return {
    id: `pc_${c.id}`,
    kind: "paymentClaim",
    refId: c.id,
    priority: "HIGH",
    title: "Payment Already Made — Verify",
    customerId: c.customerId,
    customerName: cust?.name ?? c.customerId,
    salesmanId: cust?.assignedSalesmanId ?? "",
    date: reviewDeadline(c.claimDate),
    createdAt: c.claimDate,
    isDone: false,
    autoClosed: false,
    ownerId: "",
    amountLabel: "Claimed Amount",
    amountValue: c.amount,
    detail: c.reference ? `Ref ${c.reference}` : undefined,
  };
}

/**
 * Approval Inbox (spec §19) — every "salesperson asked for a decision"
 * item in one place, split list/detail like a mail client.
 */
export function ApprovalsView() {
  const rms = useRms();
  const [tab, setTab] = useUrlState("tab", "all");
  const [selected, setSelected] = useState<string | null>(null);
  const [q, setQ] = useState("");

  const groups = useMemo(() => {
    const items = rms.buildReTaskItems();
    const ptp = items.filter((i) => i.kind === "ptpCorrection");
    const disputes = items.filter((i) => i.kind === "dispute");
    const claims = rms.approvalsPaymentClaims.map((c) => claimItem(c, rms));
    return { ptp, disputes, claims, all: [...ptp, ...disputes, ...claims] };
  }, [rms]);

  const tabs = [
    { value: "all", label: "All" },
    { value: "ptp", label: "PTP Corrections" },
    { value: "disputes", label: "Disputes" },
    { value: "claims", label: "Payments" },
  ] as const;

  const list = (groups[tab as keyof typeof groups] ?? groups.all)
    .filter((i) => !q || `${i.title} ${i.customerName} ${rms.salesmanName(i.salesmanId)}`.toLowerCase().includes(q.toLowerCase()));
  const current = list.find((i) => i.id === selected) ?? list[0] ?? null;
  const dispute = current?.kind === "dispute" ? rms.disputes.find((d) => d.id === current.refId) : undefined;

  return (
    <div className="mx-auto max-w-[1600px]">
      <PageHeader
        title="Approval Inbox"
        description="PTP corrections, disputes and payment claims waiting on you — the same three lists as the mobile Approvals screen. Original history is always kept."
      />
      <Tabs value={tab} onValueChange={(v) => { setTab(String(v)); setSelected(null); }} className="mb-4">
        <TabsList className="h-auto flex-wrap">
          {tabs.map((t) => (
            <TabsTrigger key={t.value} value={t.value}>
              {t.label}
              <span
                className={cn(
                  "ml-1 rounded px-1 text-xs tabular",
                  groups[t.value].length ? "bg-destructive/10 text-destructive" : "text-muted-foreground",
                )}
              >
                {groups[t.value].length}
              </span>
            </TabsTrigger>
          ))}
        </TabsList>
      </Tabs>

      <div className="grid min-h-[60vh] overflow-hidden rounded-xl border bg-card lg:grid-cols-[380px_1fr]">
        <div className="flex flex-col border-b lg:border-r lg:border-b-0">
          <div className="border-b p-3">
            <Input placeholder="Filter…" value={q} onChange={(e) => setQ(e.target.value)} className="h-8" />
          </div>
          <div className="max-h-[70vh] flex-1 overflow-y-auto">
            {list.length === 0 ? (
              <div className="flex h-60 flex-col items-center justify-center gap-2 text-sm text-muted-foreground">
                <Inbox className="size-6" />
                Inbox zero — nothing waiting here.
              </div>
            ) : (
              list.map((i) => (
                <button
                  key={i.id}
                  type="button"
                  onClick={() => setSelected(i.id)}
                  className={cn(
                    "block w-full border-b px-4 py-3 text-left transition-colors hover:bg-muted/50",
                    current?.id === i.id && "bg-accent/60 shadow-[inset_3px_0_0_var(--primary)]",
                  )}
                >
                  <div className="flex items-center justify-between gap-2">
                    <span className="truncate text-sm font-medium">{i.customerName}</span>
                    <span className="shrink-0 text-sm font-semibold tabular">{formatINR(i.amountValue)}</span>
                  </div>
                  <div className="mt-0.5 flex items-center justify-between gap-2 text-xs text-muted-foreground">
                    <span className="truncate">{i.title}</span>
                    <span className="shrink-0">{timeAgo(i.createdAt)}</span>
                  </div>
                  <div className="mt-1.5 flex items-center gap-2">
                    <PriorityBadge priority={i.priority} />
                    <span className="truncate text-xs text-muted-foreground">{rms.salesmanName(i.salesmanId)}</span>
                    {i.date < new Date() && <span className="text-xs font-medium text-destructive">Overdue</span>}
                  </div>
                </button>
              ))
            )}
          </div>
        </div>
        <div className="min-w-0 overflow-y-auto p-5">
          {!current ? (
            <div className="flex h-full items-center justify-center text-sm text-muted-foreground">Select an item to review.</div>
          ) : dispute ? (
            <DisputePanel key={dispute.id} dispute={dispute} rms={rms} compact />
          ) : (
            <TaskDetail key={current.id} item={current} rms={rms} onDone={() => setSelected(null)} />
          )}
        </div>
      </div>
    </div>
  );
}
