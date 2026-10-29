"use client";

import { useMemo, useState } from "react";
import type { ColumnDef } from "@tanstack/react-table";
import { isToday } from "date-fns";
import { DataTable } from "@/components/app/data-table";
import { PageHeader } from "@/components/app/page-header";
import { useSessionUser } from "@/components/app/providers";
import { SimpleSelect } from "@/components/app/simple-select";
import { Pill, PriorityBadge } from "@/components/app/status";
import { TaskSheet } from "@/components/app/task-sheet";
import { formatINR, formatRelativeDay } from "@/lib/format";
import { useRms } from "@/lib/queries";
import type { ReTaskItem, TaskKind } from "@/lib/selectors";
import { useUrlState } from "@/lib/use-url-state";
import { cn } from "@/lib/utils";

const KIND_LABEL: Record<TaskKind, string> = {
  realTask: "Task",
  visitReview: "Visit review",
  overdueTarget: "Underperformance",
  dispute: "Dispute",
  ptpCorrection: "PTP correction",
  ptpMissed: "PTP missed",
  paymentClaim: "Payment claim",
};

const KIND_TONE: Record<TaskKind, "info" | "violet" | "warning" | "danger" | "success" | "neutral"> = {
  realTask: "neutral",
  visitReview: "violet",
  overdueTarget: "warning",
  dispute: "violet",
  ptpCorrection: "info",
  ptpMissed: "danger",
  paymentClaim: "success",
};

/**
 * The unified RE queue — every item the RE must act on, built by the same
 * rules as the mobile ReTasksScreen (selectors.buildReTaskItems).
 */
export function TasksView() {
  const rms = useRms();
  const user = useSessionUser();
  const [filter, setFilter] = useUrlState("filter", "all");
  const [priority, setPriority] = useUrlState("priority", "any");
  const [kind, setKind] = useUrlState("kind", "any");
  const [selected, setSelected] = useState<string | null>(null);

  const items = useMemo(() => rms.buildReTaskItems(), [rms]);
  const now = new Date();

  const buckets = useMemo(() => {
    const open = items.filter((i) => !i.isDone);
    return {
      all: open,
      today: open.filter((i) => i.date >= now && isToday(i.date)),
      overdue: open.filter((i) => i.date < now),
      upcoming: open.filter((i) => i.date > now && !isToday(i.date)),
      // Mobile's Upcoming stat counts only the next 7 days; its list shows all.
      upcomingWeek: open.filter((i) => i.date > now && !isToday(i.date) && Math.floor((+i.date - +now) / 86_400_000) <= 7),
      completed: items.filter((i) => i.isDone && !i.autoClosed && i.ownerId === user.id),
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [items, user.id]);

  const rows = useMemo(() => {
    let list = buckets[filter as keyof typeof buckets] ?? buckets.all;
    if (priority !== "any") list = list.filter((i) => i.priority === priority);
    if (kind !== "any") list = list.filter((i) => i.kind === kind);
    return [...list].sort((a, b) => +b.createdAt - +a.createdAt);
  }, [buckets, filter, priority, kind]);

  const selectedItem = items.find((i) => i.id === selected) ?? null;

  const columns = useMemo<ColumnDef<ReTaskItem, unknown>[]>(
    () => [
      {
        id: "priority",
        header: "Priority",
        accessorFn: (r) => (r.priority === "HIGH" ? 0 : r.priority === "MEDIUM" ? 1 : 2),
        cell: ({ row }) => <PriorityBadge priority={row.original.priority} />,
        meta: { csv: (r) => r.priority },
      },
      {
        id: "title",
        header: "Item",
        accessorFn: (r) => r.title,
        cell: ({ row }) => (
          <div className="min-w-56">
            <div className="flex items-center gap-2">
              <span className="font-medium">{row.original.title}</span>
              <Pill tone={KIND_TONE[row.original.kind]} className="h-4.5 px-1.5 text-[10px]">
                {KIND_LABEL[row.original.kind]}
              </Pill>
            </div>
            {row.original.detail && <div className="line-clamp-1 max-w-md text-xs text-muted-foreground">{row.original.detail}</div>}
          </div>
        ),
      },
      { id: "customer", header: "Customer", accessorFn: (r) => r.customerName },
      { id: "salesman", header: "Salesman", accessorFn: (r) => rms.salesmanName(r.salesmanId) },
      {
        id: "amount",
        header: "Amount",
        accessorFn: (r) => r.amountValue,
        cell: ({ row }) => (
          <div>
            <div className="font-medium">{formatINR(row.original.amountValue)}</div>
            <div className="text-[11px] text-muted-foreground">{row.original.amountLabel}</div>
          </div>
        ),
        meta: { align: "right" },
      },
      {
        id: "due",
        header: "Due",
        accessorFn: (r) => +r.date,
        cell: ({ row }) => {
          const late = !row.original.isDone && row.original.date < new Date();
          return <span className={cn("whitespace-nowrap", late && "font-medium text-destructive")}>{formatRelativeDay(row.original.date)}</span>;
        },
        meta: { csv: (r) => r.date.toISOString() },
      },
      {
        id: "raised",
        header: "Raised",
        accessorFn: (r) => +r.createdAt,
        cell: ({ row }) => <span className="whitespace-nowrap text-muted-foreground">{formatRelativeDay(row.original.createdAt)}</span>,
        meta: { csv: (r) => r.createdAt.toISOString() },
      },
    ],
    [rms],
  );

  const stats = [
    { key: "all", label: "All open", count: buckets.all.length },
    { key: "today", label: "Due today", count: buckets.today.length },
    { key: "overdue", label: "Overdue", count: buckets.overdue.length, danger: true },
    { key: "upcoming", label: "Upcoming", count: buckets.upcomingWeek.length },
    { key: "completed", label: "Completed by me", count: buckets.completed.length },
  ];

  return (
    <div className="mx-auto max-w-[1600px]">
      <PageHeader
        title="My Tasks"
        description="Everything waiting on you — tasks, visit reviews, disputes, PTP corrections, payment claims and missed PTPs — in one queue, newest first."
      />
      <div className="mb-5 grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-5">
        {stats.map((s) => (
          <button
            key={s.key}
            type="button"
            onClick={() => setFilter(s.key)}
            className={cn(
              "rounded-xl border bg-card p-4 text-left shadow-xs transition-colors hover:border-primary/40",
              filter === s.key && "border-primary ring-2 ring-primary/15",
            )}
          >
            <div className="text-xs text-muted-foreground">{s.label}</div>
            <div className={cn("mt-1 text-2xl font-semibold tabular", s.danger && s.count > 0 && "text-destructive")}>{s.count}</div>
          </button>
        ))}
      </div>
      <DataTable
        columns={columns}
        data={rows}
        loading={rms.isLoading}
        searchText={(r) => `${r.title} ${r.customerName} ${rms.salesmanName(r.salesmanId)} ${r.detail ?? ""}`}
        searchPlaceholder="Search tasks, customers, salesmen…"
        onRowClick={(r) => setSelected(r.id)}
        exportName={`re-tasks-${filter}`}
        emptyText="Nothing in this view."
        rowClassName={(r) => (selected === r.id ? "bg-accent/50" : undefined)}
        toolbar={
          <>
            <SimpleSelect
              value={priority}
              onChange={setPriority}
              size="sm"
              aria-label="Priority"
              options={[
                { value: "any", label: "Any priority" },
                { value: "HIGH", label: "High" },
                { value: "MEDIUM", label: "Medium" },
                { value: "LOW", label: "Low" },
              ]}
            />
            <SimpleSelect
              value={kind}
              onChange={setKind}
              size="sm"
              aria-label="Type"
              options={[{ value: "any", label: "All types" }, ...Object.entries(KIND_LABEL).map(([value, label]) => ({ value, label }))]}
            />
          </>
        }
      />
      <TaskSheet item={selectedItem} rms={rms} onClose={() => setSelected(null)} />
    </div>
  );
}
