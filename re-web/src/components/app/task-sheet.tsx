"use client";

import Link from "next/link";
import { useState, type ReactNode } from "react";
import {
  ArrowUpRight,
  Loader2,
  CalendarClock,
  Check,
  ClipboardPlus,
  Phone,
  Repeat2,
  ShieldCheck,
  X,
} from "lucide-react";
import { format } from "date-fns";
import { Button } from "@/components/ui/button";
import { Sheet, SheetContent, SheetDescription, SheetTitle } from "@/components/ui/sheet";
import { AttachmentLink } from "./attachment-link";
import { KIND_HUE, KIND_ICON } from "./kinds";
import { IconTile } from "./visual";
import { deadlineInput, localToIso, useRmsAction } from "@/lib/actions";
import { formatINR } from "@/lib/format";
import { friendlyTaskReason, isTaskOpen, type Task } from "@/lib/models";
import type { ReTaskItem, RmsView } from "@/lib/selectors";
import { cn } from "@/lib/utils";
import { ActionDialog, type Field } from "./action-dialog";
import { Pill, PriorityBadge } from "./status";

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
      <SheetContent
        className="w-full gap-0 p-0 data-[side=right]:w-[min(640px,100vw)] data-[side=right]:sm:max-w-[640px]"
        // Focus the close button (top) so the panel opens scrolled to the top, not to the first button.
        initialFocus={() => document.querySelector<HTMLElement>('[data-slot="sheet-close"]')}
      >
        {item && <TaskDetail item={item} rms={rms} onDone={onClose} asSheet />}
      </SheetContent>
    </Sheet>
  );
}

const shortDate = (d: Date | null | undefined) => (d ? format(d, "d MMM yyyy, h:mm a") : "—");

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
  const [runningKey, setRunningKey] = useState<string | null>(null);

  const task = item.kind === "realTask" || item.kind === "visitReview" ? rms.tasks.find((t) => t.id === item.refId) : undefined;
  const customer = item.customerId ? rms.customerById.get(item.customerId) : undefined;
  const salesmanPhone = rms.salesmanById.get(item.salesmanId)?.phone;
  const salesmanOptions = rms.salesmen.map((s) => ({ value: s.id, label: `${s.fullName} · ${s.branch}` }));
  const commands = commandsFor(item, task, rms, salesmanOptions);
  const late = !item.isDone && item.date < new Date();

  const run = async (cmd: Cmd, values: Record<string, string> = {}) => {
    setRunningKey(cmd.key);
    try {
      await action.mutateAsync({ path: cmd.path!, body: cmd.body?.(values) ?? {}, success: cmd.success });
      onDone?.();
    } finally {
      setRunningKey(null);
    }
  };

  const Title = asSheet ? SheetTitle : "h2";
  const Desc = asSheet ? SheetDescription : "p";

  return (
    <div className={cn("flex min-h-0 flex-col", asSheet ? "h-full" : "")}>
      {/* Header */}
      <div className={cn("border-b-2 bg-muted/40", asSheet ? "px-6 pt-6 pb-5 pr-14" : "-mx-5 -mt-5 mb-0 px-5 pt-5 pb-4")}>
        <div className="flex items-center gap-3">
          <IconTile hue={KIND_HUE[item.kind]} size="md">
            {KIND_ICON[item.kind]}
          </IconTile>
          <div className="min-w-0">
            <Title className="text-xl leading-tight font-bold">{item.title}</Title>
            <div className="mt-1 flex flex-wrap items-center gap-2">
              <PriorityBadge priority={item.priority} />
              {late && <Pill tone="danger">Late</Pill>}
            </div>
          </div>
        </div>
        <Desc className="sr-only">Details and decision</Desc>
        <dl className="mt-4 grid gap-1.5 text-[15px]">
          <div className="flex gap-2">
            <dt className="w-24 shrink-0 text-muted-foreground">Customer</dt>
            <dd className="font-semibold break-words">{item.customerName}</dd>
          </div>
          <div className="flex gap-2">
            <dt className="w-24 shrink-0 text-muted-foreground">Salesman</dt>
            <dd className="font-semibold break-words">{rms.salesmanName(item.salesmanId)}</dd>
          </div>
        </dl>
      </div>

      {/* Body */}
      <div className={cn("min-h-0 flex-1 space-y-5 overflow-y-auto", asSheet ? "px-6 py-5" : "py-5")}>
        {/* The money, big and alone */}
        <div className="rounded-xl border-2 p-4">
          <div className="text-sm font-medium text-muted-foreground">{item.amountLabel}</div>
          <div className="text-3xl font-bold text-primary tabular">{formatINR(item.amountValue)}</div>
          {item.secondAmountLabel && (
            <div className="mt-1 text-[15px]">
              {item.secondAmountLabel}: <span className="font-semibold tabular">{formatINR(item.secondAmountValue)}</span>
            </div>
          )}
        </div>

        {/* Facts as label → value rows */}
        <dl className="divide-y-2 overflow-hidden rounded-xl border-2">
          <Row label={item.isDone ? "Done on" : "Decide by"} value={<span className={cn(late && "font-semibold text-destructive")}>{shortDate(item.isDone ? (task?.completedAt ?? item.date) : item.date)}</span>} />
          <Row label="Asked on" value={shortDate(item.createdAt)} />
          {customer && <Row label="Customer's Total Overdue" value={formatINR(customer.totalDue)} />}
          {customer && <Row label="Customer status" value={customer.currentRecoveryState || "—"} />}
          {task?.approvalStatus === "Pending" && (
            <Row
              label="Asks for new date"
              value={`${task.pendingDeadline ? shortDate(task.pendingDeadline) : "—"}${task.pendingPriority ? ` · ${task.pendingPriority}` : ""}`}
            />
          )}
        </dl>

        {(task?.reason || item.detail) && (
          <div className="rounded-xl border-2 bg-amber-50 p-4 dark:bg-amber-500/10">
            <div className="text-sm font-semibold text-amber-900 dark:text-amber-200">What the salesman wrote</div>
            <p className="mt-1 text-base">{task ? friendlyTaskReason(task.reason) : item.detail}</p>
            {task?.pendingReason && <p className="mt-2 text-[15px]">Reason for new date: {task.pendingReason}</p>}
            {task?.note && <p className="mt-2 text-[15px]">Note: {task.note}</p>}
            {task?.outcome && <p className="mt-2 text-[15px]">Result: {task.outcome}</p>}
            {task?.attachmentPath && <AttachmentLink path={task.attachmentPath} />}
          </div>
        )}

        {item.kind === "ptpCorrection" && <PtpCorrectionDiff rms={rms} ptpId={item.refId} />}
        {item.kind === "paymentClaim" && <ClaimEvidence rms={rms} claimId={item.refId} />}

        <div className="grid gap-2 sm:grid-cols-2">
          {customer && (
            <Button variant="outline" render={<Link href={`/customers/${encodeURIComponent(customer.id)}`} />}>
              Open customer <ArrowUpRight />
            </Button>
          )}
          {salesmanPhone && (
            <Button variant="outline" render={<a href={`tel:${salesmanPhone}`} />}>
              <Phone /> Call {salesmanPhone}
            </Button>
          )}
        </div>
      </div>

      {/* Decision — always visible at the bottom */}
      {commands.length > 0 && (
        <div className={cn("border-t-2 bg-card", asSheet ? "px-6 py-4" : "sticky bottom-0 z-10 -mx-5 px-5 py-4")}>
          <div className="mb-2 text-base font-bold">Your decision</div>
          <div className="grid gap-2 sm:grid-cols-2">
            {commands.map((cmd) =>
              cmd.href ? (
                <Button key={cmd.key} size="lg" variant={cmd.variant ?? "outline"} render={<Link href={cmd.href} />}>
                  {cmd.icon}
                  {cmd.label}
                </Button>
              ) : (
                <Button
                  key={cmd.key}
                  size="lg"
                  variant={cmd.variant === "destructive" ? "outline" : (cmd.variant ?? "outline")}
                  className={cn(cmd.variant === "destructive" && "border-red-300 text-red-700 hover:bg-red-50 dark:text-red-300")}
                  disabled={action.isPending}
                  onClick={() => (cmd.fields ? setActive(cmd) : run(cmd).catch(() => {}))}
                >
                  {runningKey === cmd.key && !cmd.fields ? <Loader2 className="animate-spin" /> : cmd.icon}
                  {runningKey === cmd.key && !cmd.fields ? "Please wait…" : cmd.label}
                </Button>
              ),
            )}
          </div>
        </div>
      )}

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
    </div>
  );
}

function Row({ label, value }: { label: string; value: ReactNode }) {
  return (
    <div className="flex items-center justify-between gap-4 px-4 py-3 text-[15px]">
      <dt className="text-muted-foreground">{label}</dt>
      <dd className="text-right font-semibold tabular">{value}</dd>
    </div>
  );
}

function ClaimEvidence({ rms, claimId }: { rms: RmsView; claimId: string }) {
  const c = rms.paymentClaims.find((x) => x.id === claimId);
  if (!c) return null;
  return (
    <div className="space-y-3">
      <dl className="divide-y-2 overflow-hidden rounded-xl border-2">
        <Row label="Customer says paid on" value={shortDate(c.claimDate)} />
        <Row label="Payment reference" value={c.reference ?? "—"} />
      </dl>
      <p className="rounded-xl border-2 bg-sky-50 p-4 text-[15px] dark:bg-sky-500/10">
        First check in BUSY that this money really arrived. Then choose Yes or No below.
      </p>
      {c.attachmentPath && <AttachmentLink path={c.attachmentPath} label="See payment proof" />}
    </div>
  );
}

function PtpCorrectionDiff({ rms, ptpId }: { rms: RmsView; ptpId: string }) {
  const p = rms.ptps.find((x) => x.id === ptpId);
  if (!p) return null;
  const rows: [string, string, string][] = [
    ["Amount", formatINR(p.amountPromised), formatINR(p.correctionRequestedAmount ?? p.amountPromised)],
    ["Date", shortDate(p.promiseDate), p.correctionRequestedDate ? shortDate(p.correctionRequestedDate) : "—"],
    ["How", p.paymentMode, p.correctionRequestedPaymentMode ?? p.paymentMode],
  ];
  return (
    <div className="overflow-hidden rounded-xl border-2">
      <div className="border-b-2 bg-muted px-4 py-2.5 text-base font-bold">What the salesman wants to change</div>
      <table className="w-full text-[15px]">
        <thead>
          <tr className="border-b-2 text-left text-sm text-muted-foreground">
            <th className="px-4 py-2 font-medium" />
            <th className="px-4 py-2 font-medium">Now</th>
            <th className="px-4 py-2 font-medium">Change to</th>
          </tr>
        </thead>
        <tbody>
          {rows.map(([k, a, b]) => (
            <tr key={k} className="border-b-2 last:border-b-0">
              <td className="px-4 py-3 text-muted-foreground">{k}</td>
              <td className="px-4 py-3 tabular">{a}</td>
              <td className={cn("px-4 py-3 tabular", a !== b ? "font-bold text-primary" : "text-muted-foreground")}>{a !== b ? b : "Same"}</td>
            </tr>
          ))}
        </tbody>
      </table>
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
    label: "Ask salesman to call",
    icon: <ClipboardPlus />,
    title,
    description: "Adds a call-customer task to the salesman's list.",
    path: `/customers/${encodeURIComponent(item.customerId ?? "")}/management-instruction`,
    fields: [
      { name: "desc", label: "Instruction", type: "textarea", required: true, defaultValue: "Call the customer and record an outcome." },
      { name: "deadline", label: "Deadline", type: "datetime", required: true, defaultValue: deadlineInput(1, 21) },
    ],
    body: (v) => ({ salesmanId: item.salesmanId, desc: v.desc, deadline: localToIso(v.deadline), taskType: "customerCall", priority: "High" }),
    success: "Done. The salesman has a new call task.",
  });

  switch (item.kind) {
    case "realTask": {
      if (!task || !isTaskOpen(task)) return [];
      const t = `/tasks/${task.id}`;
      const cmds: Cmd[] = [];
      if (task.approvalStatus === "Pending") {
        cmds.push(
          { key: "ae", label: "Yes, give more time", icon: <Check />, variant: "default", path: `${t}/approve-edit`, success: "New date approved." },
          { key: "re", label: "No, keep the old date", icon: <X />, variant: "destructive", path: `${t}/reject-edit`, success: "Kept the old date." },
        );
      }
      if (task.type === "paymentVerification") {
        const claim = rms.pendingPaymentClaims.find((p) => p.customerId === task.customerId);
        if (claim)
          cmds.push(
            { key: "v", label: "Yes, money received", icon: <ShieldCheck />, variant: "default", path: `/payment-claims/${claim.id}/verify`, body: () => ({ success: true }), success: "Marked as money received." },
            { key: "f", label: "No, money not received", icon: <X />, variant: "destructive", path: `/payment-claims/${claim.id}/verify`, body: () => ({ success: false }), success: "Marked as not received. The money will be chased again." },
          );
      } else if (task.type === "physicalVisit" && task.source === "Record Outcome") {
        cmds.push(
          {
            key: "cv",
            label: "Mark visit done",
            icon: <Check />,
            variant: "default",
            description: "A photo and notes from the visit are both required.",
            path: `${t}/complete`,
            fields: [
              { name: "attachmentPath", label: "Visit photo", type: "file", required: true },
              { name: "note", label: "Visit notes", type: "textarea", required: true },
            ],
            body: (v) => ({ note: v.note, attachmentPath: v.attachmentPath }),
            success: "Visit marked as done.",
          },
          { key: "rv", label: "Visit could not happen", icon: <X />, variant: "destructive", path: `${t}/reject-visit`, fields: [reasonField()], body: (v) => ({ reason: v.reason }), success: "Saved: the visit could not happen." },
        );
      } else if (task.type === "financialTeamFollowUp" && task.source === "Record Outcome") {
        cmds.push(
          {
            key: "ai",
            label: "Yes, approve",
            icon: <Check />,
            variant: "default",
            description: "The internal dependency is resolved — the salesperson gets a call-customer follow-up.",
            path: `${t}/approve-internal-action`,
            fields: [{ name: "note", label: "Note for the salesperson", type: "textarea" }],
            body: (v) => ({ note: v.note || undefined }),
            success: "Approved. The salesman will call the customer.",
          },
          {
            key: "ri",
            label: "No, reject",
            icon: <X />,
            variant: "destructive",
            description: "Not valid or not needed — the salesperson still gets a call-customer follow-up.",
            path: `${t}/reject-internal-action`,
            fields: [reasonField("Reason", false)],
            body: (v) => ({ reason: v.reason || undefined }),
            success: "Rejected. The salesman will still call the customer.",
          },
        );
      } else {
        cmds.push({
          key: "done",
          label: "Mark as done",
          icon: <Check />,
          variant: "default",
          path: `${t}/complete`,
          fields: [{ name: "note", label: "Completion note", type: "textarea" }],
          body: (v) => ({ note: v.note || undefined }),
          success: "Marked as done.",
        });
        if (!(task.type === "customerCall" && (task.source === "Missed Deadline" || task.source === "Refused Cycle")))
          cmds.push({
            key: "rs",
            label: "Change the date",
            icon: <CalendarClock />,
            path: `${t}/reschedule`,
            fields: [
              { name: "newDeadline", label: "New deadline", type: "datetime", required: true, defaultValue: deadlineInput(1, 18) },
              reasonField(),
            ],
            body: (v) => ({ reason: v.reason, newDeadline: localToIso(v.newDeadline) }),
            success: "Date changed.",
          });
      }
      cmds.push({
        key: "ra",
        label: "Give to another salesman",
        icon: <Repeat2 />,
        path: `${t}/reassign`,
        fields: [
          { name: "newOwnerId", label: "New owner", type: "select", required: true, options: salesmanOptions.filter((o) => o.value !== task.ownerId) },
          reasonField(),
        ],
        body: (v) => ({ newOwnerId: v.newOwnerId, reason: v.reason }),
        success: "Task given to the other salesman.",
      });
      return cmds;
    }
    case "visitReview":
      return [followUp("Follow up on the visit")];
    case "overdueTarget":
      return [
        {
          key: "dismiss",
          label: "Mark as checked",
          icon: <Check />,
          variant: "default",
          path: `/salesmen/${encodeURIComponent(item.salesmanId)}/dismiss-underperformance`,
          success: "Marked as checked for this month.",
        },
        followUp("Ask the salesman to work this account"),
      ];
    case "dispute":
      return [{ key: "open", label: "Open the dispute", icon: <ArrowUpRight />, variant: "default", href: `/disputes/${item.refId}` }];
    case "ptpCorrection":
      return [
        { key: "a", label: "Yes, approve change", icon: <Check />, variant: "default", path: `/ptps/${item.refId}/approve-correction`, success: "Promise change approved." },
        { key: "r", label: "No, reject change", icon: <X />, variant: "destructive", path: `/ptps/${item.refId}/reject-correction`, fields: [reasonField()], body: (v) => ({ reason: v.reason }), success: "Promise change rejected." },
      ];
    case "paymentClaim":
      return [
        { key: "v", label: "Yes, money received", icon: <ShieldCheck />, variant: "default", path: `/payment-claims/${item.refId}/verify`, body: () => ({ success: true }), success: "Marked as money received." },
        { key: "f", label: "No, money not received", icon: <X />, variant: "destructive", path: `/payment-claims/${item.refId}/verify`, body: () => ({ success: false }), success: "Marked as not received. The money will be chased again." },
      ];
    case "ptpMissed":
      return [
        followUp("Follow up on the broken PTP"),
        { key: "esc", label: "Open customer to escalate", icon: <ArrowUpRight />, href: `/customers/${encodeURIComponent(item.customerId ?? "")}` },
      ];
  }
}
