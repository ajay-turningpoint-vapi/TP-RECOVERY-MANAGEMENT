"use client";

import Link from "next/link";
import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import type { ColumnDef } from "@tanstack/react-table";
import { ArrowLeft, CheckCircle2, Phone, Repeat2 } from "lucide-react";
import { toast } from "sonner";
import { useQueryClient } from "@tanstack/react-query";
import { ActionDialog, useDialog } from "@/components/app/action-dialog";
import { customerColumns } from "@/components/app/customer-columns";
import { DataTable } from "@/components/app/data-table";
import { KpiCard } from "@/components/app/kpi-card";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Checkbox } from "@/components/ui/checkbox";
import { Progress } from "@/components/ui/progress";
import { Skeleton } from "@/components/ui/skeleton";
import { useRmsAction } from "@/lib/actions";
import { rmsPost } from "@/lib/api";
import { formatINR, formatINRCompact, initials } from "@/lib/format";
import type { Customer } from "@/lib/models";
import { useRms } from "@/lib/queries";
import { cn } from "@/lib/utils";
import { scoreTone } from "../salesmen-view";

export function SalesmanDetail({ id }: { id: string }) {
  const rms = useRms();
  const router = useRouter();
  const qc = useQueryClient();
  const action = useRmsAction();
  const s = rms.salesmanById.get(id);
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const reassign = useDialog();

  const portfolio = useMemo(
    () => rms.allCustomers.filter((c) => c.assignedSalesmanId === id).sort((a, b) => b.totalDue - a.totalDue),
    [rms.allCustomers, id],
  );
  const m = useMemo(() => {
    const ids = new Set(portfolio.map((c) => c.id));
    const owned = rms.allPtps.filter((p) => ids.has(p.customerId));
    const scheduled = owned.filter((p) => p.status === "scheduled" || p.status === "pendingVerification");
    const kept = owned.filter((p) => p.status === "kept" || p.status === "partiallyKept");
    const broken = owned.filter((p) => p.status === "broken");
    const matured = owned.filter((p) => p.status !== "scheduled" && p.status !== "pendingVerification" && p.status !== "financialSyncPending");
    const verifiedClaims = rms.allPaymentClaims.filter((c) => c.status === "Verified" && ids.has(c.customerId));
    const today = new Date().toDateString();
    return {
      totalOutstanding: portfolio.reduce((x, c) => x + c.totalOutstanding, 0),
      totalOverdue: portfolio.reduce((x, c) => x + c.totalDue, 0),
      overdueCustomers: portfolio.filter((c) => c.totalDue > 0).length,
      totalCollected:
        kept.reduce((x, p) => x + (p.amountReceived ?? 0), 0) +
        kept.reduce((x, p) => x + (p.advanceAmount ?? 0), 0) +
        verifiedClaims.reduce((x, c) => x + c.amount, 0),
      ownedPtps: owned.length,
      scheduledAmt: scheduled.reduce((x, p) => x + p.amountPromised, 0),
      broken: broken.length,
      brokenRate: matured.length ? (broken.length / matured.length) * 100 : 0,
      dueTodayCount: scheduled.filter((p) => p.promiseDate.toDateString() === today).length,
    };
  }, [portfolio, rms.allPtps, rms.allPaymentClaims]);
  const difficult = portfolio.filter((c) => c.totalDue > 0 && (c.creditHealthScore ?? 100) < 50);

  const columns: ColumnDef<Customer, unknown>[] = [
      {
        id: "select",
        enableSorting: false,
        enableHiding: false,
        header: () => (
          <Checkbox
            checked={portfolio.length > 0 && selected.size === portfolio.length}
            onCheckedChange={(v) => setSelected(v ? new Set(portfolio.map((c) => c.id)) : new Set())}
            aria-label="Select all"
          />
        ),
        cell: ({ row }) => (
          <div onClick={(e) => e.stopPropagation()}>
            <Checkbox
              checked={selected.has(row.original.id)}
              onCheckedChange={(v) =>
                setSelected((prev) => {
                  const next = new Set(prev);
                  if (v) next.add(row.original.id);
                  else next.delete(row.original.id);
                  return next;
                })
              }
              aria-label="Select row"
            />
          </div>
        ),
      },
      ...customerColumns<Customer>(rms, (c) => c).filter((c) => c.id !== "salesman"),
  ];

  if (!s) {
    return rms.isLoading ? <Skeleton className="mx-auto h-96 max-w-[1400px]" /> : <p className="py-20 text-center text-muted-foreground">Salesman not found.</p>;
  }

  const components = s.recoveryScoreComponents ?? {};

  return (
    <div className="mx-auto max-w-[1400px] space-y-5">
      <Button variant="ghost" size="sm" className="-ml-2 text-muted-foreground" render={<Link href="/salesmen" />}>
        <ArrowLeft /> Salesmen
      </Button>

      <div className="flex flex-col gap-4 rounded-xl border bg-card p-5 shadow-xs md:flex-row md:items-center md:justify-between">
        <div className="flex items-center gap-4">
          <Avatar className="size-14">
            <AvatarFallback className="bg-primary text-lg text-primary-foreground">{initials(s.fullName)}</AvatarFallback>
          </Avatar>
          <div>
            <h1 className="text-2xl font-semibold tracking-tight">{s.fullName}</h1>
            <div className="flex flex-wrap gap-x-4 text-sm text-muted-foreground">
              <span>{s.branch}</span>
              <span>@{s.username}</span>
              {s.phone && (
                <a href={`tel:${s.phone}`} className="inline-flex items-center gap-1 hover:text-foreground">
                  <Phone className="size-3.5" /> {s.phone}
                </a>
              )}
            </div>
          </div>
        </div>
        <div className="flex items-center gap-6">
          <div className="text-right">
            <div className="text-xs text-muted-foreground">Recovery score</div>
            <div className={cn("text-4xl font-semibold tabular", scoreTone(s.recoveryScore))}>{s.recoveryScore}</div>
          </div>
          {s.collectionAchievedPercent < 60 && !s.underperformanceDismissedThisMonth && (
            <Button
              variant="outline"
              disabled={action.isPending}
              onClick={() => action.mutate({ path: `/salesmen/${encodeURIComponent(s.id)}/dismiss-underperformance`, success: "Marked reviewed for this month." })}
            >
              <CheckCircle2 /> Mark reviewed this month
            </Button>
          )}
        </div>
      </div>

      {/* Same tiles and formulas as the mobile SalesmanScoreDetailScreen. */}
      <div className="grid grid-cols-2 gap-3 md:grid-cols-3 xl:grid-cols-6">
        <KpiCard label="Total Outstanding" value={formatINR(m.totalOutstanding)} hint={`${portfolio.length} customers`} />
        <KpiCard label="Total Overdue" value={formatINR(m.totalOverdue)} hint={`${m.overdueCustomers} overdue`} tone="danger" />
        <KpiCard label="Total Received" value={formatINR(m.totalCollected)} hint="PTP + Advance + Verified Claims" tone="success" />
        <KpiCard label="Total PTPs" value={m.ownedPtps} hint={`${formatINR(m.scheduledAmt)} active`} />
        <KpiCard label="Broken PTPs" value={m.broken} hint={`${m.brokenRate.toFixed(0)}% of matured`} tone={m.broken ? "danger" : "default"} />
        <KpiCard label="PTP Due Today" value={formatINR(s.dueTodayPtps)} hint={`${m.dueTodayCount} PTPs`} tone="warning" />
      </div>

      <div className="grid gap-4 lg:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle>Process discipline</CardTitle>
          </CardHeader>
          <CardContent className="space-y-3">
            {[
              ["Task completion rate", s.taskCompletionRate],
              ["Valid next action rate", s.validNextActionRate],
              ["PTP kept rate", s.ptpKeptPercent],
            ].map(([k, v]) => (
              <div key={k as string} className="space-y-1">
                <div className="flex justify-between text-sm">
                  <span className="text-muted-foreground">{k}</span>
                  <span className="font-medium tabular">{v}%</span>
                </div>
                <Progress value={v as number} className="h-1.5" />
              </div>
            ))}
            {Object.keys(components).length > 0 && (
              <div className="grid grid-cols-2 gap-x-6 gap-y-1 border-t pt-3 text-xs">
                {Object.entries(components).map(([k, v]) => (
                  <div key={k} className="flex justify-between">
                    <span className="text-muted-foreground capitalize">{k.replace(/([A-Z])/g, " $1").toLowerCase()}</span>
                    <span className="tabular">{v}</span>
                  </div>
                ))}
              </div>
            )}
          </CardContent>
        </Card>
        <Card>
          <CardHeader>
            <CardTitle>Customer difficulty</CardTitle>
          </CardHeader>
          <CardContent className="space-y-2 text-sm">
            <p className="text-muted-foreground">
              Accounts with critical credit health are hard regardless of effort — kept separate from salesperson non-compliance.
            </p>
            <div className="flex justify-between">
              <span>Critical-health accounts with overdue</span>
              <span className="font-semibold tabular">{difficult.length}</span>
            </div>
            <div className="flex justify-between">
              <span>Their overdue</span>
              <span className="font-semibold tabular">{formatINRCompact(difficult.reduce((x, c) => x + c.totalDue, 0))}</span>
            </div>
            <div className="flex justify-between">
              <span>High-risk customers (server)</span>
              <span className="font-semibold tabular">{s.highRiskCustomers}</span>
            </div>
          </CardContent>
        </Card>
      </div>

      <div>
        <h2 className="mb-3 text-sm font-semibold">Portfolio</h2>
        <DataTable
          columns={columns}
          data={portfolio}
          loading={rms.isLoading}
          searchText={(c) => `${c.name} ${c.id}`}
          onRowClick={(c) => router.push(`/customers/${encodeURIComponent(c.id)}`)}
          exportName={`portfolio-${s.username}`}
          initialSorting={[{ id: "totalDue", desc: true }]}
          initialHidden={{ branch: false }}
          toolbar={
            selected.size > 0 && (
              <Button size="sm" onClick={() => reassign.open(true)}>
                <Repeat2 /> Reassign {selected.size} customer{selected.size === 1 ? "" : "s"}
              </Button>
            )
          }
        />
      </div>

      <ActionDialog
        {...reassign.props}
        title={`Reassign ${selected.size} customer${selected.size === 1 ? "" : "s"}`}
        description="Changes the current owner only — each customer's history is kept and never rewritten."
        submitLabel="Reassign"
        fields={[
          {
            name: "toSalesmanId",
            label: "New salesman",
            type: "select",
            required: true,
            options: rms.salesmen.filter((x) => x.id !== id).map((x) => ({ value: x.id, label: `${x.fullName} · ${x.branch}` })),
          },
          { name: "reason", label: "Reason", type: "textarea", required: true },
        ]}
        onSubmit={async (v) => {
          let ok = 0;
          const failed: string[] = [];
          for (const cid of selected) {
            try {
              await rmsPost(`/customers/${encodeURIComponent(cid)}/reassign`, { toSalesmanId: v.toSalesmanId, reason: v.reason });
              ok++;
            } catch {
              failed.push(rms.customerName(cid));
            }
          }
          qc.invalidateQueries();
          setSelected(new Set());
          if (failed.length) toast.error(`Reassigned ${ok}; failed: ${failed.slice(0, 3).join(", ")}${failed.length > 3 ? "…" : ""}`);
          else toast.success(`Reassigned ${ok} customer${ok === 1 ? "" : "s"}.`);
        }}
      />
    </div>
  );
}
