"use client";

import { useMemo } from "react";
import { ColorAvatar } from "@/components/app/visual";
import { Handshake as HandshakeIcon } from "lucide-react";
import { useRouter } from "next/navigation";
import type { ColumnDef } from "@tanstack/react-table";
import { DataTable } from "@/components/app/data-table";
import { KpiCard } from "@/components/app/kpi-card";
import { PageHeader } from "@/components/app/page-header";
import { Pill, PtpStatusBadge } from "@/components/app/status";
import { Tabs, TabsList, TabsTrigger } from "@/components/ui/tabs";
import { formatDate, formatINR } from "@/lib/format";
import type { Ptp } from "@/lib/models";
import { useRms } from "@/lib/queries";
import { useUrlState } from "@/lib/use-url-state";

type Rms = ReturnType<typeof useRms>;

// The PTP lists the mobile dashboard cards open (PtpListScreen), same populations.
const FILTERS: { value: string; label: string; list: (r: Rms) => Ptp[] }[] = [
  { value: "today", label: "Promised for today", list: (r) => r.dueTodayPtps },
  { value: "scheduled", label: "All open promises", list: (r) => r.scheduledPtps },
  { value: "broken", label: "Broken promises", list: (r) => r.brokenPtps },
  { value: "overdue", label: "Late promises", list: (r) => r.overduePtps },
  { value: "all", label: "All", list: (r) => r.ptps },
];

export function PtpsView() {
  const rms = useRms();
  const router = useRouter();
  const [status, setStatus] = useUrlState("status", "scheduled");
  const f = FILTERS.find((x) => x.value === status) ?? FILTERS[1];
  const rows = f.list(rms);

  const columns = useMemo<ColumnDef<Ptp, unknown>[]>(
    () => [
      {
        id: "customer",
        header: "Customer",
        accessorFn: (p) => rms.customerName(p.customerId),
        cell: ({ row }) => (
          <span className="flex items-center gap-3 font-semibold">
            <ColorAvatar name={rms.customerName(row.original.customerId)} />
            {rms.customerName(row.original.customerId)}
          </span>
        ),
      },
      { id: "salesman", header: "Salesman", accessorFn: (p) => rms.salesmanName(rms.customerById.get(p.customerId)?.assignedSalesmanId ?? "") },
      { id: "amount", header: "Promised", accessorFn: (p) => p.amountPromised, cell: ({ getValue }) => <span className="font-bold">{formatINR(getValue() as number)}</span>, meta: { align: "right" } },
      { id: "advance", header: "Advance", accessorFn: (p) => p.advanceAmount ?? 0, cell: ({ getValue }) => ((getValue() as number) ? formatINR(getValue() as number) : "—"), meta: { align: "right" } },
      { id: "date", header: "Promise date", accessorFn: (p) => +p.promiseDate, cell: ({ row }) => formatDate(row.original.promiseDate), meta: { csv: (p) => p.promiseDate.toISOString().slice(0, 10) } },
      { id: "mode", header: "Mode", accessorFn: (p) => p.paymentMode },
      { id: "status", header: "Status", accessorFn: (p) => p.status, cell: ({ row }) => <PtpStatusBadge status={row.original.status} /> },
      { id: "received", header: "Received", accessorFn: (p) => p.amountReceived ?? 0, cell: ({ row }) => (row.original.amountReceived != null ? formatINR(row.original.amountReceived) : "—"), meta: { align: "right" } },
      {
        id: "correction",
        header: "Correction",
        accessorFn: (p) => p.correctionStatus,
        cell: ({ getValue }) => (getValue() === "none" ? "—" : <Pill tone={getValue() === "Pending" ? "warning" : "neutral"}>{getValue() as string}</Pill>),
      },
    ],
    [rms],
  );

  return (
    <div className="mx-auto max-w-[1600px]">
      <PageHeader icon={<HandshakeIcon />} hue="violet"
        title="Payment Promises"
        description="Dates when customers promised to pay. The system marks a promise kept or broken by itself."
      />
      <div className="mb-5 grid grid-cols-2 gap-3 md:grid-cols-4">
        <KpiCard label="Promised for today" value={formatINR(rms.dueTodayPtpAmount)} hint={`${rms.dueTodayPtpCount} PTPs Active Today`} tone="info" />
        <KpiCard label="All open promises" value={formatINR(rms.scheduledPtpAmount)} hint={`${rms.scheduledPtps.length} PTPs`} />
        <KpiCard label="Broken promises" value={formatINR(rms.brokenPtpAmount)} hint={`${rms.brokenPtps.length} Broken`} tone="danger" />
        <KpiCard label="Late promises" value={formatINR(rms.overduePtpAmount)} hint={`${rms.overduePtps.length} Overdue`} tone="warning" />
      </div>
      <Tabs value={status} onValueChange={(v) => setStatus(String(v))} className="mb-4">
        <TabsList className="h-auto flex-wrap">
          {FILTERS.map((x) => (
            <TabsTrigger key={x.value} value={x.value}>
              {x.label}
              <span className="ml-1 text-xs text-muted-foreground tabular">{x.list(rms).length}</span>
            </TabsTrigger>
          ))}
        </TabsList>
      </Tabs>
      <DataTable
        columns={columns}
        data={rows}
        loading={rms.isLoading}
        searchText={(p) => `${rms.customerName(p.customerId)} ${p.paymentMode}`}
        onRowClick={(p) => router.push(`/customers/${encodeURIComponent(p.customerId)}`)}
        exportName={`ptps-${status}`}
      />
    </div>
  );
}
