"use client";

import type { ColumnDef } from "@tanstack/react-table";
import type { Customer } from "@/lib/models";
import { formatINR, formatINRCompact } from "@/lib/format";
import type { RmsView } from "@/lib/selectors";
import { ColorAvatar } from "./visual";
import { CreditHealthBadge, EscalationBadge, Pill, RecoveryStateBadge } from "./status";

/** Shared customer columns for the queue, customer list and salesman portfolio. */
export function customerColumns<T>(rms: RmsView, get: (row: T) => Customer): ColumnDef<T, unknown>[] {
  return [
    {
      id: "name",
      header: "Customer",
      accessorFn: (r) => get(r).name,
      cell: ({ row }) => {
        const c = get(row.original);
        return (
          <div className="flex min-w-52 items-center gap-3">
            <ColorAvatar name={c.name} />
            <div className="min-w-0">
              <div className="truncate font-semibold">{c.name}</div>
              <div className="text-xs text-muted-foreground">
                {c.id} · {c.branch}
              </div>
            </div>
          </div>
        );
      },
    },
    {
      id: "salesman",
      header: "Salesman",
      accessorFn: (r) => rms.salesmanName(get(r).assignedSalesmanId),
      cell: ({ row }) => {
        const c = get(row.original);
        return c.ownerMappingRequired || !c.assignedSalesmanId ? (
          <Pill tone="danger">Unmapped</Pill>
        ) : (
          <span className="flex items-center gap-2 whitespace-nowrap">
            <ColorAvatar name={rms.salesmanName(c.assignedSalesmanId)} size="sm" />
            {rms.salesmanName(c.assignedSalesmanId)}
          </span>
        );
      },
    },
    {
      id: "totalDue",
      header: "Total Overdue",
      accessorFn: (r) => get(r).totalDue,
      cell: ({ getValue }) => <span className="font-bold text-rose-600 dark:text-rose-300">{formatINR(getValue() as number)}</span>,
      meta: { align: "right" },
    },
    {
      id: "totalOutstanding",
      header: "Total Outstanding",
      accessorFn: (r) => get(r).totalOutstanding,
      cell: ({ getValue }) => formatINRCompact(getValue() as number),
      meta: { align: "right" },
    },
    {
      id: "days",
      header: "Days late",
      accessorFn: (r) => get(r).oldestOverdueDays,
      cell: ({ getValue }) => {
        const d = getValue() as number;
        return <span className={d >= 90 ? "font-medium text-destructive" : d >= 60 ? "text-warning" : ""}>{d}</span>;
      },
      meta: { align: "right" },
    },
    {
      id: "state",
      header: "Status",
      accessorFn: (r) => get(r).currentRecoveryState,
      cell: ({ row }) => {
        const c = get(row.original);
        return (
          <div className="min-w-40 space-y-0.5">
            <RecoveryStateBadge state={c.currentRecoveryState} />
            {(() => {
              const step = rms.nextStepFor(c);
              return step.what ? (
                <div className="max-w-64 text-xs text-muted-foreground">
                  Next: <span className="font-medium text-foreground">{step.what}</span>
                  {step.task && step.why && <div className="line-clamp-2">{step.why}</div>}
                </div>
              ) : null;
            })()}
          </div>
        );
      },
    },
    {
      id: "escalation",
      header: "Escalation",
      accessorFn: (r) => get(r).escalationLevel,
      cell: ({ getValue }) => <EscalationBadge level={getValue() as string} />,
      meta: { align: "center" },
    },
    {
      id: "credit",
      header: "Credit health",
      accessorFn: (r) => get(r).creditHealthScore ?? -1,
      cell: ({ row }) => <CreditHealthBadge score={get(row.original).creditHealthScore} />,
      meta: { csv: (r) => get(r).creditHealthScore },
    },
    {
      id: "branch",
      header: "Branch",
      accessorFn: (r) => get(r).branch,
    },
  ];
}
