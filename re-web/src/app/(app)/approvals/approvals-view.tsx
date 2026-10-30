"use client";

import { useEffect, useMemo, useState } from "react";
import { Inbox as InboxIcon } from "lucide-react";
import { Inbox } from "lucide-react";
import { EmptyState } from "@/components/app/empty-state";
import { KIND_HUE, KIND_ICON } from "@/components/app/kinds";
import { HUE } from "@/components/app/visual";
import { CircleAlert } from "lucide-react";
import { PageHeader } from "@/components/app/page-header";
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
    title: "Customer says they already paid",
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
    const claims = rms.approvalsPaymentClaims.map((c) => claimItem(c, rms));
    return { ptp, claims, all: [...ptp, ...claims] };
  }, [rms]);

  const tabs = [
    { value: "all", label: "All" },
    { value: "ptp", label: "Promise changes" },
    { value: "claims", label: "Payment checks" },
  ] as const;

  const list = (groups[tab as keyof typeof groups] ?? groups.all)
    .filter((i) => !q || `${i.title} ${i.customerName} ${rms.salesmanName(i.salesmanId)}`.toLowerCase().includes(q.toLowerCase()));
  const current = list.find((i) => i.id === selected) ?? list[0] ?? null;

  // ↑/↓ or j/k move through the list, like a mail client.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      const el = e.target as HTMLElement | null;
      if (e.metaKey || e.ctrlKey || el?.closest("input, textarea, select, [role=dialog]")) return;
      const dir = e.key === "ArrowDown" || e.key === "j" ? 1 : e.key === "ArrowUp" || e.key === "k" ? -1 : 0;
      if (!dir || list.length === 0) return;
      e.preventDefault();
      const i = Math.max(0, list.findIndex((x) => x.id === current?.id));
      const next = list[Math.min(list.length - 1, Math.max(0, i + dir))];
      setSelected(next.id);
      document.getElementById(`appr-${next.id}`)?.scrollIntoView({ block: "nearest" });
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [list, current?.id]);

  return (
    <div className="mx-auto max-w-[1600px]">
      <PageHeader icon={<InboxIcon />} hue="indigo"
        title="Approvals"
        description="Salesmen are asking for your yes or no on payment promise changes and payment checks. Bill disputes are on the Disputes page."
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

      <div className="grid min-h-[60vh] overflow-hidden lg:h-[calc(100vh-15rem)] lg:min-h-[34rem] rounded-2xl border bg-card shadow-xs lg:grid-cols-[minmax(0,9fr)_minmax(0,11fr)]">
        <div className="flex min-h-0 flex-col border-b lg:border-r lg:border-b-0">
          <div className="flex items-center gap-2 border-b p-3">
            <Input placeholder="Type a name to find a request" value={q} onChange={(e) => setQ(e.target.value)} />

          </div>
          <div className="max-h-[70vh] min-h-0 flex-1 overflow-y-auto lg:max-h-none">
            {rms.isLoading ? (
              <div className="space-y-3 p-4" aria-label="Loading">
                {[0, 1, 2].map((k) => (
                  <div key={k} className="space-y-2 rounded-lg border-2 p-4">
                    <div className="h-4 w-1/2 animate-pulse rounded bg-muted" />
                    <div className="h-5 w-3/4 animate-pulse rounded bg-muted" />
                    <div className="h-6 w-1/3 animate-pulse rounded bg-muted" />
                  </div>
                ))}
              </div>
            ) : rms.loadFailed ? (
              <EmptyState icon={<CircleAlert />} title="Could not load requests" hint="See the red message at the top of the page and press Try again." />
            ) : list.length === 0 ? (
              <EmptyState icon={<Inbox />} title="Nothing waiting" hint="You have answered everything here. Well done." />
            ) : (
              (["ptpCorrection", "paymentClaim"] as const).map((kind) => {
                const rows = list.filter((i) => i.kind === kind);
                if (rows.length === 0) return null;
                return (
                  <section key={kind}>
                    {/* One coloured header per type, so the type isn't repeated on every row */}
                    <div className={cn("sticky top-0 z-10 flex items-center gap-2 border-b-2 px-6 py-3 text-[15px] font-bold", HUE[KIND_HUE[kind]].tile)}>
                      <span className="[&_svg]:size-4">{KIND_ICON[kind]}</span>
                      {kind === "ptpCorrection" ? "Promise changes" : "Payment checks — customer says paid"}
                      <span className="ml-auto rounded-full bg-white/70 px-2 tabular dark:bg-black/20">{rows.length}</span>
                    </div>
                    {rows.map((i) => {
                      const late = i.date < new Date();
                      const active = current?.id === i.id;
                      return (
                        <button
                          key={i.id}
                          id={`appr-${i.id}`}
                          type="button"
                          onClick={() => setSelected(i.id)}
                          className={cn(
                            "block w-full border-b px-6 py-4 text-left transition-colors hover:bg-muted/60 focus-visible:outline-none",
                            active && "bg-blue-50 shadow-[inset_5px_0_0_var(--primary)] hover:bg-blue-50 dark:bg-blue-500/10",
                          )}
                        >
                          <div className="flex items-baseline justify-between gap-3">
                            <span className="min-w-0 text-base leading-snug font-bold break-words">{i.customerName}</span>
                            <span className="shrink-0 text-lg font-bold tabular">{formatINR(i.amountValue)}</span>
                          </div>
                          <div className="mt-1 flex items-center justify-between gap-3 text-[15px] text-muted-foreground">
                            <span className="min-w-0 truncate">
                              {rms.salesmanName(i.salesmanId)} · {timeAgo(i.createdAt)}
                            </span>
                            {late && <span className="shrink-0 font-bold text-red-700 dark:text-red-300">Late</span>}
                          </div>
                        </button>
                      );
                    })}
                  </section>
                );
              })
            )}
          </div>
        </div>
        <div className="min-h-0 min-w-0 overflow-y-auto p-5 pb-0">
          {!current ? (
            <div className="flex h-full items-center justify-center text-sm text-muted-foreground">Select an item to review.</div>
          ) : (
            <div key={current.id} className="animate-in fade-in slide-in-from-right-2 duration-200 motion-reduce:animate-none">
              <TaskDetail item={current} rms={rms} onDone={() => setSelected(null)} />
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
