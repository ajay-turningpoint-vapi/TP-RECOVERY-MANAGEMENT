"use client";

import { ActionDialog } from "./action-dialog";
import { deadlineInput, localToIso, useRmsAction } from "@/lib/actions";
import type { Customer } from "@/lib/models";
import { useRms } from "@/lib/queries";

/**
 * "Create call task for salesman" — the RE's one way to give a salesman a
 * task (always a Call customer task). Used on the customer page and in the
 * Follow-up List's "No next step" view.
 */
export function CreateCallTaskDialog({
  customer,
  open,
  onOpenChange,
}: {
  customer: Customer | null;
  open: boolean;
  onOpenChange: (o: boolean) => void;
}) {
  const rms = useRms();
  const action = useRmsAction();
  const salesmanOptions = rms.salesmen.map((s) => ({ value: s.id, label: `${s.fullName} · ${s.branch}` }));
  if (!customer) return null;
  return (
    <ActionDialog
      open={open}
      onOpenChange={onOpenChange}
      title="Create call task for salesman"
      description={`${customer.name} · The salesman must call this customer. It appears in their app immediately.`}
      submitLabel="Create task"
      fields={[
        { name: "salesmanId", label: "Assign to", type: "select", required: true, defaultValue: customer.assignedSalesmanId, options: salesmanOptions },
        { name: "desc", label: "Instruction", type: "textarea", required: true, placeholder: "What exactly should the salesman do?" },
        { name: "deadline", label: "Deadline", type: "datetime", required: true, defaultValue: deadlineInput(1, 18) },
        {
          name: "priority",
          label: "Priority",
          type: "select",
          defaultValue: "High",
          options: ["Low", "Normal", "High", "Critical"].map((p) => ({ value: p, label: p })),
        },
      ]}
      onSubmit={(v) =>
        action.mutateAsync({
          path: `/customers/${encodeURIComponent(customer.id)}/management-instruction`,
          body: { salesmanId: v.salesmanId, desc: v.desc, deadline: localToIso(v.deadline), priority: v.priority, taskType: "customerCall" },
          success: "Done. The task is now in the salesman's app.",
        })
      }
    />
  );
}
