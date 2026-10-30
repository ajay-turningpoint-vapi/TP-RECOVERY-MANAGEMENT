"use client";

import { useMemo, useState } from "react";
import { ClipboardList as ClipboardListIcon } from "lucide-react";
import type { ColumnDef } from "@tanstack/react-table";
import { isToday } from "date-fns";
import Link from "next/link";
import { AlertTriangle, CalendarClock, CalendarRange, CheckCircle2, ChevronRight, Inbox, Layers } from "lucide-react";
import { KIND_HUE, KIND_ICON } from "@/components/app/kinds";
import { DataTable } from "@/components/app/data-table";
import { ColorAvatar, HUE, IconTile, type Hue } from "@/components/app/visual";
import { PageHeader } from "@/components/app/page-header";
import { useSessionUser } from "@/components/app/providers";
import { SimpleSelect } from "@/components/app/simple-select";
import { PriorityBadge } from "@/components/app/status";
import { TaskSheet } from "@/components/app/task-sheet";
import { formatINR, formatRelativeDay } from "@/lib/format";
import { useRms } from "@/lib/queries";
import { APPROVAL_KINDS, type ReTaskItem, type TaskKind } from "@/lib/selectors";
import { useUrlState } from "@/lib/use-url-state";
import { cn } from "@/lib/utils";

const KIND_LABEL: Record<TaskKind, string> = {
  realTask: "Tasks",
  visitReview: "Visits with no result",
  overdueTarget: "Salesman behind target",
  dispute: "Bill disputes",
  ptpCorrection: "Promise changes",
  ptpMissed: "Broken promises",
  paymentClaim: "Customer says paid",
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

  const items = useMemo(() => rms.buildWorkItems(), [rms]);
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
        header: "What to do",
        accessorFn: (r) => r.title,
        cell: ({ row }) => (
          <div className="flex items-center gap-3">
            <IconTile hue={KIND_HUE[row.original.kind]} size="sm">
              {KIND_ICON[row.original.kind]}
            </IconTile>
            <div className="min-w-0">
            <div className="flex items-center gap-2">
              <span className="font-semibold">{row.original.title}</span>
            </div>
            {row.original.detail && <div className="line-clamp-2 text-sm text-muted-foreground">{row.original.detail}</div>}
            </div>
          </div>
        ),
        meta: { className: "whitespace-normal min-w-[16rem]" },
      },
      {
        id: "customer",
        header: "Customer",
        accessorFn: (r) => r.customerName,
        cell: ({ getValue }) => (
          <span className="flex items-center gap-2 font-medium">
            <ColorAvatar name={getValue() as string} size="sm" />
            {getValue() as string}
          </span>
        ),
        meta: { className: "whitespace-normal" },
      },
      {
        id: "salesman",
        header: "Salesman",
        accessorFn: (r) => rms.salesmanName(r.salesmanId),
        cell: ({ getValue }) => <span className="text-muted-foreground">{getValue() as string}</span>,
      },
      {
        id: "amount",
        header: "Amount",
        accessorFn: (r) => r.amountValue,
        cell: ({ row }) => (
          <div>
            <div className="font-bold">{formatINR(row.original.amountValue)}</div>
            <div className="text-sm text-muted-foreground">{row.original.amountLabel}</div>
          </div>
        ),
        meta: { align: "right" },
      },
      {
        id: "due",
        header: "Do by",
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

  const stats: { key: string; label: string; count: number; icon: React.ElementType; hue: Hue }[] = [
    { key: "all", label: "All to do", count: buckets.all.length, icon: Layers, hue: "indigo" },
    { key: "today", label: "Due today", count: buckets.today.length, icon: CalendarClock, hue: "sky" },
    { key: "overdue", label: "Late", count: buckets.overdue.length, icon: AlertTriangle, hue: "rose" },
    { key: "upcoming", label: "Coming up", count: buckets.upcomingWeek.length, icon: CalendarRange, hue: "violet" },
    { key: "completed", label: "Done by me", count: buckets.completed.length, icon: CheckCircle2, hue: "emerald" },
  ];

  return (
    <div className="mx-auto max-w-[1600px]">
      <PageHeader icon={<ClipboardListIcon />} hue="indigo"
        title="My Tasks"
        description="Your work: calls, visits and follow-ups. Yes/no requests are in Approvals, bill disputes are in Disputes."
      />
      {(rms.approvalInboxCount > 0 || rms.disputesNeedingAction.length > 0) && (
        <div className="mb-5 grid gap-3 md:grid-cols-2">
          {rms.approvalInboxCount > 0 && (
            <Elsewhere href="/approvals" count={rms.approvalInboxCount} what={["yes/no request", "yes/no requests"]} where="Approvals" />
          )}
          {rms.disputesNeedingAction.length > 0 && (
            <Elsewhere href="/disputes?stage=decide" count={rms.disputesNeedingAction.length} what={["bill dispute", "bill disputes"]} where="Disputes" />
          )}
        </div>
      )}
      <div className="mb-6 grid grid-cols-2 gap-4 sm:grid-cols-3 lg:grid-cols-5">
        {stats.map((st) => {
          const active = filter === st.key;
          return (
            <button
              key={st.key}
              type="button"
              onClick={() => setFilter(st.key)}
              className={cn(
                "group relative flex items-center gap-3 overflow-hidden rounded-2xl border bg-card p-4 text-left shadow-soft transition-all duration-300 hover:-translate-y-0.5 hover:shadow-lg",
                active ? "border-transparent ring-2 ring-primary/60" : "border-border/60",
              )}
            >
              <div aria-hidden className={cn("pointer-events-none absolute inset-0 bg-linear-to-br to-transparent to-70%", HUE[st.hue].wash)} />
              <IconTile hue={st.hue} className="relative">
                <st.icon />
              </IconTile>
              <div className="relative">
                <div className="text-base font-semibold text-muted-foreground">{st.label}</div>
                {rms.isLoading ? (
                  <div className="mt-1 h-7 w-10 animate-pulse rounded bg-muted" />
                ) : (
                  <div className={cn("text-2xl leading-tight font-bold tabular", st.count && st.hue === "rose" ? HUE.rose.text : "")}>{st.count}</div>
                )}
              </div>
            </button>
          );
        })}
      </div>
      <DataTable
        columns={columns}
        data={rows}
        loading={rms.isLoading}
        searchText={(r) => `${r.title} ${r.customerName} ${rms.salesmanName(r.salesmanId)} ${r.detail ?? ""}`}
        searchPlaceholder="Search by name"
        onRowClick={(r) => setSelected(r.id)}
        exportName={`re-tasks-${filter}`}
        initialHidden={{ raised: false, salesman: false }}
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
              options={[{ value: "any", label: "All types" }, ...Object.entries(KIND_LABEL).filter(([k]) => !APPROVAL_KINDS.has(k as TaskKind)).map(([value, label]) => ({ value, label }))]}
            />
          </>
        }
      />
      <TaskSheet item={selectedItem} rms={rms} onClose={() => setSelected(null)} />
    </div>
  );
}

/** Points to work that lives on another page, so nothing is shown twice. */
function Elsewhere({ href, count, what, where }: { href: string; count: number; what: [string, string]; where: string }) {
  return (
    <Link
      href={href}
      className="flex items-center gap-3 rounded-xl border-2 border-red-200 bg-red-50 p-4 transition-colors hover:border-red-400 dark:border-red-500/30 dark:bg-red-500/10"
    >
      <Inbox className="size-5 shrink-0 text-red-700 dark:text-red-300" />
      <span className="flex-1 text-[15px]">
        <span className="font-bold">
          {count} {count === 1 ? what[0] : what[1]}
        </span>{" "}
        {count === 1 ? "is" : "are"} waiting in {where}.
      </span>
      <span className="inline-flex items-center gap-1 text-[15px] font-semibold whitespace-nowrap text-red-700 dark:text-red-300">
        Go to {where} <ChevronRight className="size-4" />
      </span>
    </Link>
  );
}
