"use client";

import { useMemo } from "react";
import { Users as UsersIcon } from "lucide-react";
import { useRouter } from "next/navigation";
import type { ColumnDef } from "@tanstack/react-table";
import { DataTable } from "@/components/app/data-table";
import { PageHeader } from "@/components/app/page-header";
import { ColorAvatar } from "@/components/app/visual";
import { Progress } from "@/components/ui/progress";
import { formatINRCompact } from "@/lib/format";
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
            <ColorAvatar name={row.original.fullName} />
            <div>
              <div className="font-semibold">{row.original.fullName}</div>
              <div className="text-base text-muted-foreground">
                {row.original.branch}
                {row.original.phone && ` · ${row.original.phone}`}
              </div>
            </div>
          </div>
        ),
      },
      {
        id: "score",
        header: "Score",
        accessorFn: (s) => s.recoveryScore,
        cell: ({ getValue }) => <span className={cn("text-base font-semibold", scoreTone(getValue() as number))}>{getValue() as number}</span>,
        meta: { align: "right" },
      },
      { id: "customers", header: "Customers", accessorFn: (s) => s.customers, meta: { align: "right" } },
      { id: "overdue", header: "Total Overdue", accessorFn: (s) => s.totalOverdue, cell: ({ getValue }) => formatINRCompact(getValue() as number), meta: { align: "right" } },
      {
        id: "collection",
        header: "Collected vs target",
        accessorFn: (s) => s.collectionAchievedPercent,
        cell: ({ row }) => (
          <div className="flex min-w-40 items-center gap-2">
            <Progress value={Math.min(100, row.original.collectionAchievedPercent)} className="h-1.5 flex-1" />
            <span className={cn("w-12 text-right text-base font-semibold tabular", row.original.collectionAchievedPercent < 60 && "text-destructive")}>
              {row.original.collectionAchievedPercent}%
            </span>
          </div>
        ),
      },
      { id: "ptpKept", header: "Promises kept", accessorFn: (s) => s.ptpKeptPercent, cell: ({ getValue }) => `${getValue()}%`, meta: { align: "right" } },
      { id: "broken", header: "Broken promises", accessorFn: (s) => s.brokenPtps, cell: ({ getValue }) => <span className={cn((getValue() as number) > 0 && "text-destructive")}>{getValue() as number}</span>, meta: { align: "right" } },
      { id: "overdueTasks", header: "Late tasks", accessorFn: (s) => s.overdueTasks, cell: ({ getValue }) => <span className={cn((getValue() as number) > 0 && "text-destructive")}>{getValue() as number}</span>, meta: { align: "right" } },
      { id: "taskRate", header: "Task completion", accessorFn: (s) => s.taskCompletionRate, cell: ({ getValue }) => `${getValue()}%`, meta: { align: "right" } },
      { id: "nextAction", header: "Valid next action", accessorFn: (s) => s.validNextActionRate, cell: ({ getValue }) => `${getValue()}%`, meta: { align: "right" } },
      { id: "escalated", header: "Escalated", accessorFn: (s) => s.escalatedCustomers, meta: { align: "right" } },
      { id: "dueToday", header: "PTP due today", accessorFn: (s) => s.dueTodayPtps, cell: ({ getValue }) => formatINRCompact(getValue() as number), meta: { align: "right" } },
    ],
    [],
  );

  return (
    <div className="mx-auto max-w-[1600px]">
      <PageHeader icon={<UsersIcon />} hue="emerald"
        title="Salesmen"
        description="Salesmen whose customers have overdue money. Biggest amount at the top."
      />
      <DataTable
        columns={columns}
        data={rms.salesmenWithOverdue}
        loading={rms.isLoading}
        searchText={(s) => `${s.fullName} ${s.username} ${s.branch}`}
        searchPlaceholder="Type a salesman name"
        onRowClick={(s) => router.push(`/salesmen/${encodeURIComponent(s.id)}`)}
        exportName="salesmen-performance"
        initialSorting={[{ id: "overdue", desc: true }]}
        initialHidden={{ taskRate: false, nextAction: false, dueToday: false, customers: false, overdueTasks: false, escalated: false, broken: false }}
        pageSize={50}
      />
    </div>
  );
}
