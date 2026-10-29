"use client";

import type { ColumnDef } from "@tanstack/react-table";
import type { Customer } from "@/lib/models";
import { formatINR, formatINRCompact } from "@/lib/format";
import type { RmsView } from "@/lib/selectors";
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
          <div className="min-w-48">
            <div className="font-medium">{c.name}</div>
            <div className="text-xs text-muted-foreground">
              {c.id} · {c.branch}
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
          <span className="whitespace-nowrap">{rms.salesmanName(c.assignedSalesmanId)}</span>
        );
      },
    },
    {
      id: "totalDue",
      header: "Overdue",
      accessorFn: (r) => get(r).totalDue,
      cell: ({ getValue }) => <span className="font-semibold">{formatINR(getValue() as number)}</span>,
      meta: { align: "right" },
    },
    {
      id: "totalOutstanding",
      header: "Outstanding",
      accessorFn: (r) => get(r).totalOutstanding,
      cell: ({ getValue }) => formatINRCompact(getValue() as number),
      meta: { align: "right" },
    },
    {
      id: "days",
      header: "Days",
      accessorFn: (r) => get(r).oldestOverdueDays,
      cell: ({ getValue }) => {
        const d = getValue() as number;
        return <span className={d >= 90 ? "font-medium text-destructive" : d >= 60 ? "text-warning" : ""}>{d}</span>;
      },
      meta: { align: "right" },
    },
    {
      id: "state",
      header: "Recovery state",
      accessorFn: (r) => get(r).currentRecoveryState,
      cell: ({ row }) => {
        const c = get(row.original);
        return (
          <div className="min-w-40 space-y-0.5">
            <RecoveryStateBadge state={c.currentRecoveryState} />
            {c.primaryNextAction && <div className="text-xs text-muted-foreground">Next: {c.primaryNextAction}</div>}
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
