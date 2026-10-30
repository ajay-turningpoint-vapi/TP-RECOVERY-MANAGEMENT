"use client";

import { useMemo } from "react";
import { ColorAvatar } from "@/components/app/visual";
import { FileWarning as FileWarningIcon } from "lucide-react";
import { useRouter } from "next/navigation";
import type { ColumnDef } from "@tanstack/react-table";
import { DataTable } from "@/components/app/data-table";
import { PageHeader } from "@/components/app/page-header";
import { DisputeStatusBadge, Pill } from "@/components/app/status";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { formatDate, formatINR } from "@/lib/format";
import { DISPUTE_NEEDS_RE_ACTION, type Dispute } from "@/lib/models";
import { useRms } from "@/lib/queries";
import { useUrlState } from "@/lib/use-url-state";
import { cn } from "@/lib/utils";

/** DisputesListView._bucketOf — same bucket for every status as the mobile app. */
function bucketOf(status: string) {
  switch (status) {
    case "Approved":
    case "In Resolution":
    case "Awaiting Verification":
    case "Need More Information":
      return "IN PROGRESS";
    case "Resolved":
    case "Auto-Closed":
      return "RESOLVED";
    case "Rejected":
    case "Returned to Recovery":
      return "REJECTED";
    default:
      return "OPEN";
  }
}

const STAGES: { value: string; label: string; match: (d: Dispute) => boolean }[] = [
  { value: "decide", label: "Needs your decision", match: (d) => DISPUTE_NEEDS_RE_ACTION.has(d.status) },
  { value: "all", label: "All", match: () => true },
  { value: "open", label: "Open", match: (d) => bucketOf(d.status) === "OPEN" },
  { value: "progress", label: "In progress", match: (d) => bucketOf(d.status) === "IN PROGRESS" },
  { value: "resolved", label: "Resolved", match: (d) => bucketOf(d.status) === "RESOLVED" },
  { value: "rejected", label: "Rejected", match: (d) => bucketOf(d.status) === "REJECTED" },
];

export function DisputesView() {
  const rms = useRms();
  const router = useRouter();
  const [stage, setStage] = useUrlState("stage", "all");
  const current = STAGES.find((s) => s.value === stage) ?? STAGES[0];
  const rows = useMemo(() => rms.disputes.filter(current.match).sort((a, b) => +b.raisedDate - +a.raisedDate), [rms.disputes, current]);

  const columns = useMemo<ColumnDef<Dispute, unknown>[]>(
    () => [
      {
        id: "customer",
        header: "Customer",
        accessorFn: (d) => rms.customerName(d.customerId),
        cell: ({ row }) => (
          <div className="flex items-center gap-3">
            <ColorAvatar name={rms.customerName(row.original.customerId)} />
            <div>
            <div className="font-semibold">{rms.customerName(row.original.customerId)}</div>
            <div className="text-xs text-muted-foreground">{row.original.invoiceNumber ? `Invoice ${row.original.invoiceNumber}` : "No invoice"}</div>
            </div>
          </div>
        ),
      },
      { id: "amount", header: "Disputed", accessorFn: (d) => d.amount, cell: ({ getValue }) => <span className="font-semibold">{formatINR(getValue() as number)}</span>, meta: { align: "right" } },
      { id: "reason", header: "Reason", accessorFn: (d) => d.reason, cell: ({ getValue }) => <span className="line-clamp-2">{getValue() as string}</span>, meta: { className: "whitespace-normal min-w-[14rem]" } },
      { id: "status", header: "Status", accessorFn: (d) => d.status, cell: ({ getValue }) => <DisputeStatusBadge status={getValue() as string} /> },
      { id: "priority", header: "Priority", accessorFn: (d) => d.priority ?? "", cell: ({ getValue }) => (getValue() ? <Pill tone={getValue() === "High" ? "danger" : "neutral"}>{getValue() as string}</Pill> : "—") },
      { id: "owner", header: "Owner", accessorFn: (d) => (d.resolutionOwner ? rms.salesmanName(d.resolutionOwner) : "—") },
      {
        id: "deadline",
        header: "Deadline",
        accessorFn: (d) => (d.deadline ? +d.deadline : 0),
        cell: ({ row }) => <span className={cn(row.original.deadline && row.original.deadline < new Date() && current.value !== "resolved" && current.value !== "rejected" && "text-destructive")}>{formatDate(row.original.deadline)}</span>,
        meta: { csv: (d) => d.deadline?.toISOString() },
      },
      { id: "raised", header: "Raised", accessorFn: (d) => +d.raisedDate, cell: ({ row }) => formatDate(row.original.raisedDate), meta: { csv: (d) => d.raisedDate.toISOString() } },
    ],
    [rms, current.value],
  );


  return (
    <div className="mx-auto max-w-[1600px]">
      <PageHeader icon={<FileWarningIcon />} hue="violet"
        title="Disputes"
        description="Customers who say the bill is wrong. Every dispute is handled here — open one to approve, reject, ask for details or close it."
      />
      <Tabs value={stage} onValueChange={(v) => setStage(String(v))} className="mb-4">
        <TabsList>
          {STAGES.map((s) => (
            <TabsTrigger key={s.value} value={s.value}>
              {s.label}
              <span className="ml-1 text-xs text-muted-foreground tabular">{rms.disputes.filter(s.match).length}</span>
            </TabsTrigger>
          ))}
        </TabsList>
      </Tabs>
      <DataTable
        columns={columns}
        data={rows}
        loading={rms.isLoading}
        searchText={(d) => `${rms.customerName(d.customerId)} ${d.invoiceNumber ?? ""} ${d.reason}`}
        onRowClick={(d) => router.push(`/disputes/${d.id}`)}
        exportName={`disputes-${stage}`}
        initialHidden={{ priority: false, owner: false, deadline: false }}
        emptyText="No disputes in this stage."
      />
    </div>
  );
}
