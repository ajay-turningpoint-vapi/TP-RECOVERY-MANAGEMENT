"use client";

import Link from "next/link";
import { useState, type ReactNode } from "react";
import {
  ArrowUpRight,
  CalendarClock,
  Check,
  ClipboardPlus,
  Phone,
  Repeat2,
  ShieldCheck,
  X,
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { Separator } from "@/components/ui/separator";
import { Sheet, SheetContent, SheetDescription, SheetTitle } from "@/components/ui/sheet";
import { AttachmentLink } from "./attachment-link";
import { deadlineInput, localToIso, useRmsAction } from "@/lib/actions";
import { formatDateTime, formatINR } from "@/lib/format";
import { friendlyTaskReason, isTaskOpen, PTP_STATUS_LABEL, type Task } from "@/lib/models";
import type { ReTaskItem, RmsView } from "@/lib/selectors";
import { cn } from "@/lib/utils";
import { ActionDialog, type Field } from "./action-dialog";
import { PriorityBadge } from "./status";

type Cmd = {
  key: string;
  label: string;
  icon: ReactNode;
  variant?: "default" | "outline" | "destructive";
  /** Either a direct POST… */
  path?: string;
  body?: (v: Record<string, string>) => unknown;
  success?: string;
  fields?: Field[];
  title?: string;
  description?: string;
  /** …or a link. */
  href?: string;
};

/**
 * The detail + decision panel for one item in the unified RE queue. The
 * command set per item kind mirrors UnifiedTaskDetailScreen in the mobile
 * app (lib/v3/screens/unified_task_detail_screen.dart).
 */
export function TaskSheet({ item, rms, onClose }: { item: ReTaskItem | null; rms: RmsView; onClose: () => void }) {
  return (
    <Sheet open={!!item} onOpenChange={(o) => !o && onClose()}>
      <SheetContent className="w-full gap-0 sm:max-w-lg">
        {item && <TaskDetail item={item} rms={rms} onDone={onClose} asSheet />}
      </SheetContent>
    </Sheet>
  );
}

export function TaskDetail({
  item,
  rms,
  onDone,
  asSheet,
}: {
  item: ReTaskItem;
  rms: RmsView;
  onDone?: () => void;
  asSheet?: boolean;
}) {
  const action = useRmsAction();
  const [active, setActive] = useState<Cmd | null>(null);

  const task = item.kind === "realTask" || item.kind === "visitReview" ? rms.tasks.find((t) => t.id === item.refId) : undefined;
  const customer = item.customerId ? rms.customerById.get(item.customerId) : undefined;
  const salesmanPhone = rms.salesmanById.get(item.salesmanId)?.phone;
  const salesmanOptions = rms.salesmen.map((s) => ({ value: s.id, label: `${s.fullName} · ${s.branch}` }));
  const commands = commandsFor(item, task, rms, salesmanOptions);

  const run = async (cmd: Cmd, values: Record<string, string> = {}) => {
    await action.mutateAsync({ path: cmd.path!, body: cmd.body?.(values) ?? {}, success: cmd.success });
    onDone?.();
  };

  const Title = asSheet ? SheetTitle : "h2";
  const Desc = asSheet ? SheetDescription : "p";

  return (
    <>
      <div className={cn("space-y-1.5 border-b pb-4", asSheet ? "p-4" : "")}>
        <div className="flex items-center gap-2">
          <PriorityBadge priority={item.priority} />
          {task && <span className="text-xs text-muted-foreground">Source: {task.source}</span>}
        </div>
        <Title className="text-lg font-semibold">{item.title}</Title>
        <Desc className="text-sm text-muted-foreground">
          {item.customerName} · Salesman {rms.salesmanName(item.salesmanId)}
        </Desc>
      </div>

      <div className={cn("flex-1 space-y-5 overflow-y-auto", asSheet ? "p-4" : "pt-4")}>
        <dl className="grid grid-cols-2 gap-x-4 gap-y-3 text-sm">
          <Info label={item.amountLabel} value={formatINR(item.amountValue)} strong />
          {item.secondAmountLabel && <Info label={item.secondAmountLabel} value={formatINR(item.secondAmountValue)} />}
          <Info
            label={item.isDone ? "Completed" : "Due by"}
            value={
              <span className={cn(!item.isDone && item.date < new Date() && "text-destructive")}>
                {formatDateTime(item.isDone ? (task?.completedAt ?? item.date) : item.date)}
              </span>
            }
          />
          <Info label="Raised" value={formatDateTime(item.createdAt)} />
          {customer && <Info label="Customer overdue" value={formatINR(customer.totalDue)} />}
          {customer && <Info label="Recovery state" value={customer.currentRecoveryState || "—"} />}
          {task?.approvalStatus === "Pending" && (
            <Info
              label="Extension requested"
              value={`${task.pendingDeadline ? formatDateTime(task.pendingDeadline) : "—"}${task.pendingPriority ? ` · ${task.pendingPriority}` : ""}`}
            />
          )}
        </dl>

        {(task?.reason || item.detail) && (
          <div className="rounded-lg bg-muted/60 p-3 text-sm">
            <div className="mb-1 text-xs font-medium text-muted-foreground">Details</div>
            {task ? friendlyTaskReason(task.reason) : item.detail}
            {task?.pendingReason && <div className="mt-2 text-muted-foreground">Extension reason: {task.pendingReason}</div>}
            {task?.note && <div className="mt-2 text-muted-foreground">Note: {task.note}</div>}
            {task?.outcome && <div className="mt-2 text-muted-foreground">Outcome: {task.outcome}</div>}
            {task?.attachmentPath && <AttachmentLink path={task.attachmentPath} />}
          </div>
        )}

        {item.kind === "ptpCorrection" && <PtpCorrectionDiff rms={rms} ptpId={item.refId} />}
        {item.kind === "paymentClaim" && <ClaimEvidence rms={rms} claimId={item.refId} />}

        <div className="flex flex-wrap gap-2">
          {customer && (
            <Button variant="outline" size="sm" render={<Link href={`/customers/${encodeURIComponent(customer.id)}`} />}>
              Customer 360 <ArrowUpRight />
            </Button>
          )}
          {salesmanPhone && (
            <Button variant="outline" size="sm" render={<a href={`tel:${salesmanPhone}`} />}>
              <Phone /> Call salesman · {salesmanPhone}
            </Button>
          )}
        </div>

        {commands.length > 0 && (
          <>
            <Separator />
            <div className="space-y-2">
              <div className="text-xs font-medium text-muted-foreground">Decide</div>
              <div className="grid gap-2 sm:grid-cols-2">
                {commands.map((cmd) =>
                  cmd.href ? (
                    <Button key={cmd.key} variant={cmd.variant ?? "outline"} render={<Link href={cmd.href} />}>
                      {cmd.icon}
                      {cmd.label}
                    </Button>
                  ) : (
                    <Button
                      key={cmd.key}
                      variant={cmd.variant ?? "outline"}
                      disabled={action.isPending}
                      onClick={() => (cmd.fields ? setActive(cmd) : run(cmd))}
                    >
                      {cmd.icon}
                      {cmd.label}
                    </Button>
                  ),
                )}
              </div>
            </div>
          </>
        )}
      </div>

      <ActionDialog
        open={!!active}
        onOpenChange={(o) => !o && setActive(null)}
        title={active?.title ?? active?.label ?? ""}
        description={active?.description}
        fields={active?.fields ?? []}
        submitLabel={active?.label}
        destructive={active?.variant === "destructive"}
        onSubmit={(v) => run(active!, v)}
      />
    </>
  );
}

function ClaimEvidence({ rms, claimId }: { rms: RmsView; claimId: string }) {
  const c = rms.paymentClaims.find((x) => x.id === claimId);
  if (!c) return null;
  return (
    <div className="rounded-lg border p-3 text-sm">
      <div className="grid grid-cols-2 gap-2">
        <Info label="Claim date" value={formatDateTime(c.claimDate)} />
        <Info label="Reference" value={c.reference ?? "—"} />
      </div>
      <p className="mt-2 text-xs text-muted-foreground">Check BUSY for a matching receipt before verifying. You cannot mark anything paid — BUSY reconciliation does.</p>
      {c.attachmentPath && <AttachmentLink path={c.attachmentPath} />}
    </div>
  );
}

function Info({ label, value, strong }: { label: string; value: ReactNode; strong?: boolean }) {
  return (
    <div>
      <dt className="text-xs text-muted-foreground">{label}</dt>
      <dd className={cn("tabular", strong && "text-base font-semibold")}>{value}</dd>
    </div>
  );
}

function PtpCorrectionDiff({ rms, ptpId }: { rms: RmsView; ptpId: string }) {
  const p = rms.ptps.find((x) => x.id === ptpId);
  if (!p) return null;
  const rows: [string, string, string][] = [
    ["Amount", formatINR(p.amountPromised), formatINR(p.correctionRequestedAmount ?? p.amountPromised)],
    ["Date", formatDateTime(p.promiseDate), p.correctionRequestedDate ? formatDateTime(p.correctionRequestedDate) : "—"],
    ["Mode", p.paymentMode, p.correctionRequestedPaymentMode ?? p.paymentMode],
  ];
  return (
    <div className="overflow-hidden rounded-lg border text-sm">
      <div className="grid grid-cols-3 bg-muted/60 px-3 py-1.5 text-xs font-medium text-muted-foreground">
        <span />
        <span>Current ({PTP_STATUS_LABEL[p.status]})</span>
        <span>Requested</span>
      </div>
      {rows.map(([k, a, b]) => (
        <div key={k} className="grid grid-cols-3 border-t px-3 py-2">
          <span className="text-muted-foreground">{k}</span>
          <span className="tabular">{a}</span>
          <span className={cn("tabular", a !== b && "font-semibold text-primary")}>{b}</span>
        </div>
      ))}
      {p.correctionReason && <div className="border-t px-3 py-2 text-muted-foreground">Reason: {p.correctionReason}</div>}
    </div>
  );
}

const reasonField = (label = "Reason", required = true): Field => ({ name: "reason", label, type: "textarea", required });

export function commandsFor(
  item: ReTaskItem,
  task: Task | undefined,
  rms: RmsView,
  salesmanOptions: { value: string; label: string }[],
): Cmd[] {
  const followUp = (title: string): Cmd => ({
    key: "followup",
    label: "Create call task",
    icon: <ClipboardPlus />,
    title,
    description: "Adds a call-customer task to the salesman's list.",
    path: `/customers/${encodeURIComponent(item.customerId ?? "")}/management-instruction`,
    fields: [
      { name: "desc", label: "Instruction", type: "textarea", required: true, defaultValue: "Call the customer and record an outcome." },
      { name: "deadline", label: "Deadline", type: "datetime", required: true, defaultValue: deadlineInput(1, 21) },
    ],
    body: (v) => ({ salesmanId: item.salesmanId, desc: v.desc, deadline: localToIso(v.deadline), taskType: "customerCall", priority: "High" }),
    success: "Call task created for the salesman.",
  });

  switch (item.kind) {
    case "realTask": {
      if (!task || !isTaskOpen(task)) return [];
      const t = `/tasks/${task.id}`;
      const cmds: Cmd[] = [];
      if (task.approvalStatus === "Pending") {
        cmds.push(
          { key: "ae", label: "Approve extension", icon: <Check />, variant: "default", path: `${t}/approve-edit`, success: "Extension approved — deadline updated." },
          { key: "re", label: "Reject extension", icon: <X />, variant: "destructive", path: `${t}/reject-edit`, success: "Extension rejected — original deadline stands." },
        );
      }
      if (task.type === "paymentVerification") {
        const claim = rms.pendingPaymentClaims.find((p) => p.customerId === task.customerId);
        if (claim)
          cmds.push(
            { key: "v", label: "Verify deposit", icon: <ShieldCheck />, variant: "default", path: `/payment-claims/${claim.id}/verify`, body: () => ({ success: true }), success: "Payment verified." },
            { key: "f", label: "Fail verification", icon: <X />, variant: "destructive", path: `/payment-claims/${claim.id}/verify`, body: () => ({ success: false }), success: "Claim failed — returned to recovery." },
          );
      } else if (task.type === "physicalVisit" && task.source === "Record Outcome") {
        cmds.push(
          {
            key: "cv",
            label: "Complete visit",
            icon: <Check />,
            variant: "default",
            description: "A photo and notes from the visit are both required.",
            path: `${t}/complete`,
            fields: [
              { name: "attachmentPath", label: "Visit photo", type: "file", required: true },
              { name: "note", label: "Visit notes", type: "textarea", required: true },
            ],
            body: (v) => ({ note: v.note, attachmentPath: v.attachmentPath }),
            success: "Visit completed.",
          },
          { key: "rv", label: "Reject visit", icon: <X />, variant: "destructive", path: `${t}/reject-visit`, fields: [reasonField()], body: (v) => ({ reason: v.reason }), success: "Visit rejected." },
        );
      } else if (task.type === "financialTeamFollowUp" && task.source === "Record Outcome") {
        cmds.push(
          {
            key: "ai",
            label: "Approve",
            icon: <Check />,
            variant: "default",
            description: "The internal dependency is resolved — the salesperson gets a call-customer follow-up.",
            path: `${t}/approve-internal-action`,
            fields: [{ name: "note", label: "Note for the salesperson", type: "textarea" }],
            body: (v) => ({ note: v.note || undefined }),
            success: "Internal action approved.",
          },
          {
            key: "ri",
            label: "Reject",
            icon: <X />,
            variant: "destructive",
            description: "Not valid or not needed — the salesperson still gets a call-customer follow-up.",
            path: `${t}/reject-internal-action`,
            fields: [reasonField("Reason", false)],
            body: (v) => ({ reason: v.reason || undefined }),
            success: "Internal action rejected.",
          },
        );
      } else {
        cmds.push({
          key: "done",
          label: "Mark completed",
          icon: <Check />,
          variant: "default",
          path: `${t}/complete`,
          fields: [{ name: "note", label: "Completion note", type: "textarea" }],
          body: (v) => ({ note: v.note || undefined }),
          success: "Task completed.",
        });
        if (!(task.type === "customerCall" && (task.source === "Missed Deadline" || task.source === "Refused Cycle")))
          cmds.push({
            key: "rs",
            label: "Reschedule",
            icon: <CalendarClock />,
            path: `${t}/reschedule`,
            fields: [
              { name: "newDeadline", label: "New deadline", type: "datetime", required: true, defaultValue: deadlineInput(1, 18) },
              reasonField(),
            ],
            body: (v) => ({ reason: v.reason, newDeadline: localToIso(v.newDeadline) }),
            success: "Deadline updated.",
          });
      }
      cmds.push({
        key: "ra",
        label: "Reassign",
        icon: <Repeat2 />,
        path: `${t}/reassign`,
        fields: [
          { name: "newOwnerId", label: "New owner", type: "select", required: true, options: salesmanOptions.filter((o) => o.value !== task.ownerId) },
          reasonField(),
        ],
        body: (v) => ({ newOwnerId: v.newOwnerId, reason: v.reason }),
        success: "Task reassigned.",
      });
      return cmds;
    }
    case "visitReview":
      return [followUp("Follow up on the visit")];
    case "overdueTarget":
      return [
        {
          key: "dismiss",
          label: "Mark reviewed",
          icon: <Check />,
          variant: "default",
          path: `/salesmen/${encodeURIComponent(item.salesmanId)}/dismiss-underperformance`,
          success: "Cleared for this month. It returns on the 1st if still below target.",
        },
        followUp("Ask the salesman to work this account"),
      ];
    case "dispute":
      return [{ key: "open", label: "Review dispute", icon: <ArrowUpRight />, variant: "default", href: `/disputes/${item.refId}` }];
    case "ptpCorrection":
      return [
        { key: "a", label: "Approve correction", icon: <Check />, variant: "default", path: `/ptps/${item.refId}/approve-correction`, success: "PTP correction approved." },
        { key: "r", label: "Reject correction", icon: <X />, variant: "destructive", path: `/ptps/${item.refId}/reject-correction`, fields: [reasonField()], body: (v) => ({ reason: v.reason }), success: "PTP correction rejected." },
      ];
    case "paymentClaim":
      return [
        { key: "v", label: "Verify deposit", icon: <ShieldCheck />, variant: "default", path: `/payment-claims/${item.refId}/verify`, body: () => ({ success: true }), success: "Payment verified." },
        { key: "f", label: "Fail verification", icon: <X />, variant: "destructive", path: `/payment-claims/${item.refId}/verify`, body: () => ({ success: false }), success: "Claim failed — returned to recovery." },
      ];
    case "ptpMissed":
      return [
        followUp("Follow up on the broken PTP"),
        { key: "esc", label: "Escalate from Customer 360", icon: <ArrowUpRight />, href: `/customers/${encodeURIComponent(item.customerId ?? "")}` },
      ];
  }
}
