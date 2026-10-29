"use client";

import { useMemo } from "react";
import { useRouter } from "next/navigation";
import type { ColumnDef } from "@tanstack/react-table";
import { DataTable } from "@/components/app/data-table";
import { PageHeader } from "@/components/app/page-header";
import { Avatar, AvatarFallback } from "@/components/ui/avatar";
import { Progress } from "@/components/ui/progress";
import { formatINRCompact, initials } from "@/lib/format";
import type { Salesman } from "@/lib/models";
import { useRms } from "@/lib/queries";
import { cn } from "@/lib/utils";

export function scoreTone(score: number) {
  return score >= 80 ? "text-success" : score >= 60 ? "text-warning" : "text-destructive";
}

export function SalesmenView() {
  const rms = useRms();
  const router = useRouter();

  const columns = useMemo<ColumnDef<Salesman, unknown>[]>(
    () => [
      {
        id: "name",
        header: "Salesman",
        accessorFn: (s) => s.fullName,
        cell: ({ row }) => (
          <div className="flex items-center gap-2.5">
            <Avatar className="size-8">
              <AvatarFallback className="text-[11px]">{initials(row.original.fullName)}</AvatarFallback>
            </Avatar>
            <div>
              <div className="font-medium">{row.original.fullName}</div>
              <div className="text-xs text-muted-foreground">
                {row.original.branch}
                {row.original.phone && ` · ${row.original.phone}`}
              </div>
            </div>
          </div>
        ),
      },
      {
        id: "score",
        header: "Recovery score",
        accessorFn: (s) => s.recoveryScore,
        cell: ({ getValue }) => <span className={cn("text-base font-semibold", scoreTone(getValue() as number))}>{getValue() as number}</span>,
        meta: { align: "right" },
      },
      { id: "customers", header: "Customers", accessorFn: (s) => s.customers, meta: { align: "right" } },
      { id: "overdue", header: "Overdue", accessorFn: (s) => s.totalOverdue, cell: ({ getValue }) => formatINRCompact(getValue() as number), meta: { align: "right" } },
      {
        id: "collection",
        header: "Collection vs target",
        accessorFn: (s) => s.collectionAchievedPercent,
        cell: ({ row }) => (
          <div className="flex min-w-40 items-center gap-2">
            <Progress value={Math.min(100, row.original.collectionAchievedPercent)} className="h-1.5 flex-1" />
            <span className={cn("w-10 text-right text-xs tabular", row.original.collectionAchievedPercent < 60 && "font-medium text-destructive")}>
              {row.original.collectionAchievedPercent}%
            </span>
          </div>
        ),
      },
      { id: "ptpKept", header: "PTP kept", accessorFn: (s) => s.ptpKeptPercent, cell: ({ getValue }) => `${getValue()}%`, meta: { align: "right" } },
      { id: "broken", header: "Broken PTPs", accessorFn: (s) => s.brokenPtps, cell: ({ getValue }) => <span className={cn((getValue() as number) > 0 && "text-destructive")}>{getValue() as number}</span>, meta: { align: "right" } },
      { id: "overdueTasks", header: "Overdue tasks", accessorFn: (s) => s.overdueTasks, cell: ({ getValue }) => <span className={cn((getValue() as number) > 0 && "text-destructive")}>{getValue() as number}</span>, meta: { align: "right" } },
      { id: "taskRate", header: "Task completion", accessorFn: (s) => s.taskCompletionRate, cell: ({ getValue }) => `${getValue()}%`, meta: { align: "right" } },
      { id: "nextAction", header: "Valid next action", accessorFn: (s) => s.validNextActionRate, cell: ({ getValue }) => `${getValue()}%`, meta: { align: "right" } },
      { id: "escalated", header: "Escalated", accessorFn: (s) => s.escalatedCustomers, meta: { align: "right" } },
      { id: "dueToday", header: "PTP due today", accessorFn: (s) => s.dueTodayPtps, cell: ({ getValue }) => formatINRCompact(getValue() as number), meta: { align: "right" } },
    ],
    [],
  );

  return (
    <div className="mx-auto max-w-[1600px]">
      <PageHeader
        title="Salesmen"
        description="Salesmen carrying overdue exposure, highest overdue first — the same list as the mobile app. Figures are computed server-side."
      />
      <DataTable
        columns={columns}
        data={rms.salesmenWithOverdue}
        loading={rms.isLoading}
        searchText={(s) => `${s.fullName} ${s.username} ${s.branch}`}
        searchPlaceholder="Search salesman or branch…"
        onRowClick={(s) => router.push(`/salesmen/${encodeURIComponent(s.id)}`)}
        exportName="salesmen-performance"
        initialSorting={[{ id: "overdue", desc: true }]}
        initialHidden={{ taskRate: false, nextAction: false, dueToday: false }}
        pageSize={50}
      />
    </div>
  );
}
