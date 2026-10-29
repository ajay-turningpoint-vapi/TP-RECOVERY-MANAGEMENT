"use client";

import Link from "next/link";
import { useState } from "react";
import { ArrowUpRight, Check, HelpCircle, Loader2, Send, ShieldCheck, Undo2, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Textarea } from "@/components/ui/textarea";
import { deadlineInput, localToIso, useRmsAction } from "@/lib/actions";
import { formatDate, formatDateTime, formatINR } from "@/lib/format";
import type { Dispute } from "@/lib/models";
import type { RmsView } from "@/lib/selectors";
import { cn } from "@/lib/utils";
import { ActionDialog, useDialog } from "./action-dialog";
import { AttachmentLink } from "./attachment-link";
import { DisputeStatusBadge, Pill } from "./status";

const DEPARTMENTS = ["Sales / Material Coordination", "Accounts", "Logistics", "Quality Control", "Customer Service"];

/**
 * Full dispute decision surface (spec §40–44): the RE approves with a
 * resolution owner + deadline, rejects, asks for information, and later
 * verifies the owner's resolution against BUSY. Only the disputed amount
 * is shielded — the rest of the overdue stays in recovery.
 */
export function DisputePanel({ dispute: d, rms, compact }: { dispute: Dispute; rms: RmsView; compact?: boolean }) {
  const action = useRmsAction();
  const approve = useDialog();
  const reject = useDialog();
  const info = useDialog();
  const [message, setMessage] = useState("");
  const customer = rms.customerById.get(d.customerId);
  const salesmanId = customer?.assignedSalesmanId ?? "";
  const salesmanOptions = rms.salesmen.map((s) => ({ value: s.id, label: `${s.fullName} · ${s.branch}` }));
  const undisputed = Math.max(0, (d.totalDueAtRaise || customer?.totalDue || 0) - d.amount);
  const base = `/disputes/${d.id}`;

  const pendingApproval = d.status === "Pending Approval";
  const awaitingVerification = d.status === "Awaiting Verification";
  const needsOwner = d.status === "Approved" && !d.resolutionOwner;

  const post = async () => {
    if (!message.trim()) return;
    await action.mutateAsync({ path: `${base}/message`, body: { body: message.trim() }, success: "Message posted." });
    setMessage("");
  };

  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div className="space-y-1">
          <div className="flex flex-wrap items-center gap-2">
            <h2 className="text-lg font-semibold">{customer?.name ?? d.customerId}</h2>
            <DisputeStatusBadge status={d.status} />
            {d.priority && <Pill tone={d.priority === "High" ? "danger" : "neutral"}>{d.priority} priority</Pill>}
          </div>
          <p className="text-sm text-muted-foreground">
            Raised {formatDateTime(d.raisedDate)} by {rms.salesmanName(salesmanId)}
            {d.invoiceNumber && <> · Invoice {d.invoiceNumber}</>}
          </p>
        </div>
        {compact && (
          <Button variant="outline" size="sm" render={<Link href={`/disputes/${d.id}`} />}>
            Open full view <ArrowUpRight />
          </Button>
        )}
      </div>

      <div className="grid grid-cols-3 gap-px overflow-hidden rounded-xl border bg-border text-sm">
        {[
          ["Disputed (shielded)", formatINR(d.amount)],
          ["Overdue at raise", formatINR(d.totalDueAtRaise)],
          ["Still in recovery", formatINR(undisputed)],
        ].map(([k, v]) => (
          <div key={k} className="bg-card px-3 py-2.5">
            <div className="text-xs text-muted-foreground">{k}</div>
            <div className="font-semibold tabular">{v}</div>
          </div>
        ))}
      </div>

      <div className="rounded-lg bg-muted/60 p-3 text-sm">
        <div className="mb-1 text-xs font-medium text-muted-foreground">Reason</div>
        {d.reason}
        {d.statusDetail && <div className="mt-2 text-muted-foreground">{d.statusDetail}</div>}
        {d.attachmentPath && <AttachmentLink path={d.attachmentPath} />}
      </div>

      <dl className="grid grid-cols-2 gap-3 text-sm sm:grid-cols-4">
        <div>
          <dt className="text-xs text-muted-foreground">Resolution owner</dt>
          <dd>{d.resolutionOwner ? rms.salesmanName(d.resolutionOwner) : "—"}</dd>
        </div>
        <div>
          <dt className="text-xs text-muted-foreground">Department</dt>
          <dd>{d.department ?? "—"}</dd>
        </div>
        <div>
          <dt className="text-xs text-muted-foreground">Resolution deadline</dt>
          <dd className={cn(d.deadline && d.deadline < new Date() && "text-destructive")}>{formatDate(d.deadline)}</dd>
        </div>
        <div>
          <dt className="text-xs text-muted-foreground">Last updated</dt>
          <dd>{formatDateTime(d.lastUpdated)}</dd>
        </div>
      </dl>
      {d.rejectionReason && <p className="text-sm text-destructive">Rejected: {d.rejectionReason}</p>}
      {d.infoRequestNote && <p className="text-sm text-violet">Information requested: {d.infoRequestNote}</p>}

      {(pendingApproval || awaitingVerification || needsOwner) && (
        <div className="flex flex-wrap gap-2 rounded-xl border border-primary/25 bg-accent/40 p-3">
          {(pendingApproval || needsOwner) && (
            <Button onClick={() => approve.open(true)}>
              <Check /> {needsOwner ? "Assign owner" : "Approve & assign"}
            </Button>
          )}
          {pendingApproval && (
            <>
              <Button variant="outline" onClick={() => info.open(true)}>
                <HelpCircle /> Request information
              </Button>
              <Button variant="destructive" onClick={() => reject.open(true)}>
                <X /> Reject
              </Button>
            </>
          )}
          {awaitingVerification && (
            <>
              <Button
                disabled={action.isPending}
                onClick={() => action.mutate({ path: `${base}/resolve`, body: { outcome: "Resolved" }, success: "Dispute verified and resolved." })}
              >
                <ShieldCheck /> Verify &amp; resolve
              </Button>
              <Button
                variant="destructive"
                disabled={action.isPending}
                onClick={() =>
                  action.mutate({
                    path: `${base}/resolve`,
                    body: { outcome: "Returned to Recovery" },
                    success: "BUSY still shows it due — returned to recovery.",
                  })
                }
              >
                <Undo2 /> Return to recovery
              </Button>
            </>
          )}
        </div>
      )}

      <Card>
        <CardHeader>
          <CardTitle>Conversation</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          {d.messages.length === 0 ? (
            <p className="text-sm text-muted-foreground">No messages yet.</p>
          ) : (
            <ol className="space-y-3">
              {d.messages.map((m, i) => {
                const mine = m.authorRole === "RECOVERY_EXECUTIVE" || m.authorRole === "MANAGEMENT";
                return (
                  <li key={i} className={cn("flex", mine && "justify-end")}>
                    <div className={cn("max-w-[85%] rounded-xl px-3 py-2 text-sm", mine ? "bg-primary text-primary-foreground" : "bg-muted")}>
                      <div className={cn("mb-0.5 text-[11px]", mine ? "text-primary-foreground/70" : "text-muted-foreground")}>
                        {m.authorName} · {formatDateTime(m.createdAt)}
                        {m.kind && m.kind !== "message" && <> · {m.kind}</>}
                      </div>
                      <div className="whitespace-pre-wrap">{m.body}</div>
                      {m.attachmentPath && <AttachmentLink path={m.attachmentPath} />}
                    </div>
                  </li>
                );
              })}
            </ol>
          )}
          <div className="flex gap-2">
            <Textarea
              rows={2}
              placeholder="Write to the salesman and resolution owner…"
              value={message}
              onChange={(e) => setMessage(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) post();
              }}
            />
            <Button className="self-end" onClick={post} disabled={!message.trim() || action.isPending} aria-label="Send">
              {action.isPending ? <Loader2 className="animate-spin" /> : <Send />}
            </Button>
          </div>
        </CardContent>
      </Card>

      <ActionDialog
        {...approve.props}
        title={needsOwner ? "Assign resolution owner" : "Approve dispute"}
        description={`Only ${formatINR(d.amount)} is shielded from recovery. The owner gets a task with this deadline.`}
        submitLabel={needsOwner ? "Assign" : "Approve"}
        fields={[
          { name: "resolutionOwner", label: "Resolution owner", type: "select", required: true, options: salesmanOptions, defaultValue: salesmanId },
          { name: "department", label: "Internal department", type: "select", options: DEPARTMENTS.map((x) => ({ value: x, label: x })), defaultValue: DEPARTMENTS[0] },
          { name: "description", label: "Resolution instruction", type: "textarea", required: true },
          { name: "note", label: "Note for the owner", type: "textarea", required: true },
          { name: "deadline", label: "Resolution deadline", type: "datetime", required: true, defaultValue: deadlineInput(3, 18) },
          { name: "attachmentPath", label: "Attachment", type: "file" },
        ]}
        onSubmit={(v) =>
          action.mutateAsync({
            path: `${base}/approve`,
            body: {
              resolutionOwner: v.resolutionOwner,
              department: v.department || undefined,
              description: v.description,
              note: v.note,
              deadline: localToIso(v.deadline),
              attachmentPath: v.attachmentPath || undefined,
            },
            success: "Dispute approved and assigned.",
          })
        }
      />
      <ActionDialog
        {...reject.props}
        title="Reject dispute"
        description="The full amount returns to recovery. The salesman sees your reason."
        submitLabel="Reject"
        destructive
        fields={[{ name: "reason", label: "Reason", type: "textarea", required: true }]}
        onSubmit={(v) => action.mutateAsync({ path: `${base}/reject`, body: { reason: v.reason }, success: "Dispute rejected." })}
      />
      <ActionDialog
        {...info.props}
        title="Request more information"
        description="Creates a task for the salesman to answer by the deadline."
        submitLabel="Send request"
        fields={[
          { name: "salesmanId", label: "Ask", type: "select", required: true, options: salesmanOptions, defaultValue: salesmanId },
          { name: "desc", label: "What do you need?", type: "textarea", required: true },
          { name: "deadline", label: "Answer by", type: "datetime", required: true, defaultValue: deadlineInput(1, 18) },
        ]}
        onSubmit={(v) =>
          action.mutateAsync({
            path: `${base}/request-info`,
            body: { salesmanId: v.salesmanId, desc: v.desc, deadline: localToIso(v.deadline) },
            success: "Information requested.",
          })
        }
      />
    </div>
  );
}
