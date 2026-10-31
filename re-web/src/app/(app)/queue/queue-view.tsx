"use client";

import { useMemo } from "react";
import { ClipboardPlus, ListOrdered as ListOrderedIcon } from "lucide-react";
import { useRouter } from "next/navigation";
import type { ColumnDef } from "@tanstack/react-table";
import { useDialog } from "@/components/app/action-dialog";
import { CreateCallTaskDialog } from "@/components/app/create-call-task-dialog";
import { customerColumns } from "@/components/app/customer-columns";
import { DataTable } from "@/components/app/data-table";
import { PageHeader } from "@/components/app/page-header";
import { SimpleSelect } from "@/components/app/simple-select";
import { Pill } from "@/components/app/status";
import { Button } from "@/components/ui/button";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { formatINRCompact } from "@/lib/format";
import { useRms } from "@/lib/queries";
import type { Customer } from "@/lib/models";
import type { QueueRow } from "@/lib/selectors";
import { useUrlState } from "@/lib/use-url-state";

// Mobile chips (All / Broken PTP / Escalated) first; the rest are the
// dashboard exception drill-downs, built from the same AppStore getters.
const VIEWS = [
  { value: "all", label: "All" },
  { value: "broken", label: "Broke a promise" },
  { value: "escalated", label: "Escalated" },
  { value: "no-follow-up", label: "Not followed up" },
  { value: "no-next-action", label: "No next step" },
  { value: "ownerless", label: "No salesman" },
  { value: "at-risk", label: "Money at risk" },
] as const;

const SORTS = [
  { value: "priority", label: "Priority" },
  { value: "name-asc", label: "Name A–Z" },
  { value: "name-desc", label: "Name Z–A" },
  { value: "amount-desc", label: "Amount high–low" },
  { value: "amount-asc", label: "Amount low–high" },
];

const RANK_TONE: Record<number, "danger" | "warning" | "info" | "neutral" | "violet"> = {
  0: "danger",
  1: "danger",
  2: "violet",
  3: "warning",
  4: "warning",
  5: "info",
  6: "warning",
  7: "neutral",
};

export function QueueView() {
  const rms = useRms();
  const router = useRouter();
  const createTask = useDialog<Customer>();
  const [view, setView] = useUrlState("view", "all");
  const [salesman, setSalesman] = useUrlState("salesman", "all");
  const [sort, setSort] = useUrlState("sort", "priority");
  const [mode] = useUrlState("mode", "overdue");
  const outstanding = mode === "outstanding";
  const amountOf = (r: QueueRow) => (outstanding ? r.customer.totalOutstanding : r.customer.totalDue);

  const { rows, counts } = useMemo(() => {
    let base: QueueRow[] = rms.recoveryQueue(outstanding ? "outstanding" : "overdue");
    if (salesman !== "all") base = base.filter((r) => r.customer.assignedSalesmanId === salesman);
    const brokenIds = new Set(rms.brokenPtps.map((p) => p.customerId));
    const idSet = (list: { id: string }[]) => new Set(list.map((c) => c.id));
    const sets: Record<string, (r: QueueRow) => boolean> = {
      all: () => true,
      broken: (r) => brokenIds.has(r.customer.id),
      escalated: (r) => r.customer.escalationLevel !== "none",
      "no-follow-up": ((s) => (r: QueueRow) => s.has(r.customer.id))(idSet(rms.noFollowUpAccounts)),
      "no-next-action": ((s) => (r: QueueRow) => s.has(r.customer.id))(idSet(rms.noValidNextAction)),
      ownerless: ((s) => (r: QueueRow) => s.has(r.customer.id))(idSet(rms.ownerMappingRequired)),
      "at-risk": ((s) => (r: QueueRow) => s.has(r.customer.id))(idSet(rms.atRiskAccounts)),
    };
    const counts = Object.fromEntries(Object.entries(sets).map(([k, f]) => [k, base.filter(f).length]));
    const out = base.filter(sets[view] ?? sets.all);
    const sorted = [...out];
    if (sort === "name-asc") sorted.sort((a, b) => a.customer.name.toLowerCase().localeCompare(b.customer.name.toLowerCase()));
    else if (sort === "name-desc") sorted.sort((a, b) => b.customer.name.toLowerCase().localeCompare(a.customer.name.toLowerCase()));
    else if (sort === "amount-desc") sorted.sort((a, b) => amountOf(b) - amountOf(a));
    else if (sort === "amount-asc") sorted.sort((a, b) => amountOf(a) - amountOf(b));
    return { rows: sorted, counts };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [rms, view, salesman, sort, outstanding]);

  const exposure = rows.reduce((s, r) => s + amountOf(r), 0);

  const columns = useMemo<ColumnDef<QueueRow, unknown>[]>(
    () => [
      {
        id: "rank",
        header: "Why at the top",
        accessorFn: (r) => r.rank,
        cell: ({ row }) => <Pill tone={RANK_TONE[row.original.rank]}>{row.original.reason}</Pill>,
        meta: { csv: (r) => r.reason },
      },
      ...customerColumns<QueueRow>(rms, (r) => r.customer),
      {
        id: "tasks",
        header: "Open tasks",
        accessorFn: (r) => r.openTasks,
        cell: ({ row }) =>
          row.original.overdueTasks > 0 ? (
            <span className="text-destructive">
              {row.original.openTasks} <span className="text-xs">({row.original.overdueTasks} overdue)</span>
            </span>
          ) : (
            row.original.openTasks
          ),
        meta: { align: "right" },
      },
      ...(view === "no-next-action"
        ? [
            {
              id: "createTask",
              header: "",
              enableSorting: false,
              cell: ({ row }) => {
                const c = row.original.customer;
                const given = rms.openSalesmanTaskFor(c.id);
                const locked = !rms.canCreateTaskFor(c);
                return (
                  <Button
                    size="sm"
                    variant={locked ? "outline" : "default"}
                    disabled={locked}
                    title={given ? "The salesman already has a task for this customer" : c.outcomeWaitText ?? undefined}
                    onClick={(e) => {
                      e.stopPropagation();
                      createTask.open(c);
                    }}
                  >
                    <ClipboardPlus /> {given ? "Task given" : "Create task"}
                  </Button>
                );
              },
              meta: { csv: () => "" },
            } as ColumnDef<QueueRow, unknown>,
          ]
        : []),
    ],
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [rms, view],
  );

  return (
    <div className="mx-auto max-w-[1600px]">
      <PageHeader icon={<ListOrderedIcon />} hue="indigo"
        title={outstanding ? "Total Outstanding" : "Follow-up List"}
        description="Customers to chase, most urgent at the top (same order as the mobile app). Click Open to see a customer."
        actions={
          <div className="flex gap-6 text-right">
            <div>
              <div className="text-xs text-muted-foreground">Customers</div>
              <div className="text-lg font-semibold tabular">{rows.length.toLocaleString("en-IN")}</div>
            </div>
            <div>
              <div className="text-xs text-muted-foreground">{outstanding ? "Total Outstanding" : "Total Overdue"}</div>
              <div className="text-lg font-semibold tabular">{formatINRCompact(exposure)}</div>
            </div>
          </div>
        }
      />
      <Tabs value={view} onValueChange={(v) => setView(String(v))} className="mb-4">
        <TabsList className="h-auto flex-wrap">
          {VIEWS.map((v) => (
            <TabsTrigger key={v.value} value={v.value}>
              {v.label}
              <span className="ml-1 text-xs text-muted-foreground tabular">{counts[v.value] ?? 0}</span>
            </TabsTrigger>
          ))}
        </TabsList>
      </Tabs>
      <CreateCallTaskDialog customer={createTask.target} {...createTask.props} />
      <DataTable
        columns={columns}
        data={rows}
        loading={rms.isLoading}
        searchText={(r) => `${r.customer.name} ${r.customer.id} ${rms.salesmanName(r.customer.assignedSalesmanId)}`}
        searchPlaceholder="Search by name"
        onRowClick={(r) => router.push(`/customers/${encodeURIComponent(r.customer.id)}`)}
        exportName={`recovery-queue-${view}`}
        emptyText="No customers in this view."
        initialHidden={{ branch: false, credit: false, escalation: false, tasks: false, state: false, ...(outstanding ? {} : { totalOutstanding: false }) }}
        toolbar={
          <>
            <SimpleSelect
              value={salesman}
              onChange={setSalesman}
              options={[{ value: "all", label: "All salesmen" }, ...rms.salesmen.map((s) => ({ value: s.id, label: s.fullName }))]}
              size="sm"
              aria-label="Salesman"
            />
            <SimpleSelect value={sort} onChange={setSort} options={SORTS} size="sm" aria-label="Sort" />
          </>
        }
      />
    </div>
  );
}
