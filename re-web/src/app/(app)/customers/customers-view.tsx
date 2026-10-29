"use client";

import { useMemo } from "react";
import { useRouter } from "next/navigation";
import type { ColumnDef } from "@tanstack/react-table";
import { customerColumns } from "@/components/app/customer-columns";
import { DataTable } from "@/components/app/data-table";
import { PageHeader } from "@/components/app/page-header";
import { SimpleSelect } from "@/components/app/simple-select";
import type { Customer } from "@/lib/models";
import { useRms } from "@/lib/queries";
import { useUrlState } from "@/lib/use-url-state";

export function CustomersView() {
  const rms = useRms();
  const router = useRouter();
  const [scope, setScope] = useUrlState("scope", "due");
  const [salesman, setSalesman] = useUrlState("salesman", "all");

  const rows = useMemo(() => {
    let list = scope === "due" ? rms.customers.filter((c) => c.totalDue > 0) : rms.customers;
    if (salesman !== "all") list = list.filter((c) => c.assignedSalesmanId === salesman);
    return list;
  }, [rms.customers, scope, salesman]);

  const columns = useMemo<ColumnDef<Customer, unknown>[]>(() => customerColumns<Customer>(rms, (c) => c), [rms]);

  return (
    <div className="mx-auto max-w-[1600px]">
      <PageHeader title="Customers" description="Every active customer in scope. Open one for the full Customer 360." />
      <DataTable
        columns={columns}
        data={rows}
        loading={rms.isLoading}
        searchText={(c) => `${c.name} ${c.id} ${c.branch} ${rms.salesmanName(c.assignedSalesmanId)} ${c.contactNumber}`}
        searchPlaceholder="Search name, code, phone…"
        onRowClick={(c) => router.push(`/customers/${encodeURIComponent(c.id)}`)}
        exportName="customers"
        initialSorting={[{ id: "totalDue", desc: true }]}
        toolbar={
          <>
            <SimpleSelect
              value={scope}
              onChange={setScope}
              options={[
                { value: "due", label: "With overdue" },
                { value: "all", label: "All customers" },
              ]}
              size="sm"
              aria-label="Scope"
            />
            <SimpleSelect
              value={salesman}
              onChange={setSalesman}
              options={[{ value: "all", label: "All salesmen" }, ...rms.salesmen.map((s) => ({ value: s.id, label: s.fullName }))]}
              size="sm"
              aria-label="Salesman"
            />
          </>
        }
      />
    </div>
  );
}
