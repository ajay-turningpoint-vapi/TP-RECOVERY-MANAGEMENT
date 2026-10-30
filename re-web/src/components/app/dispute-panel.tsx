"use client";

import Link from "next/link";
import { useState, type ReactNode } from "react";
import { format } from "date-fns";
import { ArrowUpRight, Check, CircleCheck, FileWarning, HelpCircle, Loader2, Phone, Send, ShieldCheck, Undo2, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { deadlineInput, localToIso, useRmsAction } from "@/lib/actions";
import { formatINR } from "@/lib/format";
import type { Dispute } from "@/lib/models";
import type { RmsView } from "@/lib/selectors";
import { cn } from "@/lib/utils";
import { ActionDialog, useDialog } from "./action-dialog";
import { AttachmentLink } from "./attachment-link";
import { DisputeStatusBadge, Pill } from "./status";
import { IconTile } from "./visual";

const DEPARTMENTS = ["Sales / Material Coordination", "Accounts", "Logistics", "Quality Control", "Customer Service"];
const when = (d: Date | null | undefined) => (d ? format(d, "d MMM yyyy, h:mm a") : "—");

/**
 * Full dispute page (spec §40–44): the RE approves with a resolution owner
 * + deadline, rejects, asks for information, and later verifies the
 * owner's resolution against BUSY. Only the disputed amount is put on
 * hold — the rest of the late money stays in recovery.
 *
 * Laid out for easy reading: facts on the left, the decision pinned on
 * the right with a plain explanation under every button.
 */
export function DisputePanel({ dispute: d, rms }: { dispute: Dispute; rms: RmsView; compact?: boolean }) {
  const action = useRmsAction();
  const approve = useDialog();
  const reject = useDialog();
  const info = useDialog();
  const [message, setMessage] = useState("");
  const [running, setRunning] = useState<string | null>(null);
  const resolve = (outcome: "Resolved" | "Returned to Recovery", success: string) => {
    setRunning(outcome);
    action.mutate({ path: `${base}/resolve`, body: { outcome }, success }, { onSettled: () => setRunning(null) });
  };
  const customer = rms.customerById.get(d.customerId);
  const salesmanId = customer?.assignedSalesmanId ?? "";
  const salesmanPhone = rms.salesmanById.get(salesmanId)?.phone;
  const salesmanOptions = rms.salesmen.map((s) => ({ value: s.id, label: `${s.fullName} · ${s.branch}` }));
  const undisputed = Math.max(0, (d.totalDueAtRaise || customer?.totalDue || 0) - d.amount);
  const base = `/disputes/${d.id}`;

  const pendingApproval = d.status === "Pending Approval";
  const awaitingVerification = d.status === "Awaiting Verification";
  const needsOwner = d.status === "Approved" && !d.resolutionOwner;
  const needsMe = pendingApproval || awaitingVerification || needsOwner;
  const late = !!d.deadline && d.deadline < new Date() && !["Resolved", "Rejected", "Returned to Recovery", "Auto-Closed"].includes(d.status);

  const [sending, setSending] = useState(false);
  const post = async () => {
    if (!message.trim()) return;
    setSending(true);
    try {
      await action.mutateAsync({ path: `${base}/message`, body: { body: message.trim() }, success: "Message sent.", pending: "Sending message…" });
      setMessage("");
    } catch {
      /* alert already shown; the typed message is kept so nothing is lost */
    } finally {
      setSending(false);
    }
  };

  return (
    <div className="grid gap-6 xl:grid-cols-[1fr_380px]">
      {/* ── Left: the facts ─────────────────────────────────────────── */}
      <div className="min-w-0 space-y-5">
        {/* Who */}
        <section className="rounded-xl border-2 bg-card p-5">
          <div className="flex flex-wrap items-start gap-4">
            <IconTile hue="violet" size="lg">
              <FileWarning />
            </IconTile>
            <div className="min-w-0 flex-1">
              <p className="text-sm font-semibold text-purple-800 dark:text-purple-300">Bill dispute</p>
              <h1 className="text-2xl leading-tight font-bold break-words">{customer?.name ?? d.customerId}</h1>
              <div className="mt-2 flex flex-wrap items-center gap-2">
                <DisputeStatusBadge status={d.status} />
                {d.priority === "High" && <Pill tone="danger">Urgent</Pill>}
                {late && <Pill tone="danger">Late</Pill>}
              </div>
            </div>
            {customer && (
              <Button variant="outline" render={<Link href={`/customers/${encodeURIComponent(customer.id)}`} />}>
                Open customer <ArrowUpRight />
              </Button>
            )}
          </div>
          <dl className="mt-4 grid gap-x-8 gap-y-2 text-[15px] sm:grid-cols-2">
            <Fact label="Raised by">{rms.salesmanName(salesmanId)}</Fact>
            <Fact label="Raised on">{when(d.raisedDate)}</Fact>
            <Fact label="Invoice">{d.invoiceNumber ?? "—"}</Fact>
            {salesmanPhone && (
              <Fact label="Salesman phone">
                <a href={`tel:${salesmanPhone}`} className="inline-flex items-center gap-1 text-primary hover:underline">
                  <Phone className="size-4" /> {salesmanPhone}
                </a>
              </Fact>
            )}
          </dl>
        </section>

        {/* How much */}
        <section className="grid gap-3 sm:grid-cols-3">
          <Money label="Customer disputes" note="Put on hold" value={d.amount} tone="text-purple-800 dark:text-purple-300" />
          <Money label="Total Overdue when raised" value={d.totalDueAtRaise} tone="text-foreground" />
          <Money label="Still to collect" note="Keep chasing this" value={undisputed} tone="text-red-700 dark:text-red-300" />
        </section>

        {/* What the salesman wrote */}
        <section className="rounded-xl border-2 bg-amber-50 p-5 dark:bg-amber-500/10">
          <p className="text-sm font-semibold text-amber-900 dark:text-amber-200">Why the customer disputes the bill</p>
          <p className="mt-1 text-lg">{d.reason}</p>
          {d.statusDetail && <p className="mt-2 text-[15px] text-muted-foreground">{d.statusDetail}</p>}
          {d.attachmentPath && <AttachmentLink path={d.attachmentPath} label="See attached proof" />}
        </section>

        {/* Who is fixing it */}
        <section className="overflow-hidden rounded-xl border-2 bg-card">
          <h2 className="border-b-2 bg-muted/50 px-5 py-3 text-base font-bold">Who is fixing it</h2>
          <dl className="divide-y-2">
            <Row label="Person fixing it">{d.resolutionOwner ? rms.salesmanName(d.resolutionOwner) : "Not given yet"}</Row>
            <Row label="Department">{d.department ?? "Not given yet"}</Row>
            <Row label="Fix by">
              <span className={cn(late && "text-destructive")}>{d.deadline ? when(d.deadline) : "Not given yet"}</span>
            </Row>
            <Row label="Last change">{when(d.lastUpdated)}</Row>
          </dl>
          {d.rejectionReason && <p className="border-t-2 px-5 py-3 text-[15px] text-red-700 dark:text-red-300">Rejected because: {d.rejectionReason}</p>}
          {d.infoRequestNote && <p className="border-t-2 px-5 py-3 text-[15px]">You asked for: {d.infoRequestNote}</p>}
        </section>

        {/* Conversation */}
        <section className="overflow-hidden rounded-xl border-2 bg-card">
          <h2 className="border-b-2 bg-muted/50 px-5 py-3 text-base font-bold">Messages</h2>
          <div className="space-y-3 p-5">
            {d.messages.length === 0 ? (
              <p className="text-[15px] text-muted-foreground">No messages yet. Write below to talk to the salesman.</p>
            ) : (
              <ol className="space-y-3">
                {d.messages.map((m, i) => {
                  const mine = m.authorRole === "RECOVERY_EXECUTIVE" || m.authorRole === "MANAGEMENT";
                  return (
                    <li key={i} className={cn("flex", mine && "justify-end")}>
                      <div className={cn("max-w-[80%] rounded-xl px-4 py-3", mine ? "bg-primary text-primary-foreground" : "border-2 bg-muted/50")}>
                        <div className={cn("mb-1 text-sm", mine ? "text-primary-foreground/80" : "text-muted-foreground")}>
                          <span className="font-semibold">{mine ? "You" : m.authorName}</span> · {when(m.createdAt)}
                        </div>
                        <div className="text-[15px] whitespace-pre-wrap">{m.body}</div>
                        {m.attachmentPath && <AttachmentLink path={m.attachmentPath} />}
                      </div>
                    </li>
                  );
                })}
              </ol>
            )}
            <div className="space-y-2 pt-2">
              <Textarea
                rows={3}
                placeholder="Write a message to the salesman…"
                value={message}
                onChange={(e) => setMessage(e.target.value)}
                className="text-[15px]"
              />
              <Button onClick={post} disabled={!message.trim() || sending}>
                {sending ? <Loader2 className="animate-spin" /> : <Send />}
                {sending ? "Sending…" : "Send message"}
              </Button>
            </div>
          </div>
        </section>
      </div>

      {/* ── Right: the decision, always in view ────────────────────── */}
      <aside className="xl:sticky xl:top-20 xl:self-start">
        <div className="overflow-hidden rounded-xl border-2 bg-card">
          <h2 className="border-b-2 bg-muted/50 px-5 py-3 text-lg font-bold">Your decision</h2>
          <div className="space-y-4 p-5">
            {!needsMe ? (
              <div className="flex items-start gap-3 rounded-lg bg-green-50 p-4 text-[15px] dark:bg-green-500/10">
                <CircleCheck className="mt-0.5 size-5 shrink-0 text-green-700 dark:text-green-300" />
                <span>Nothing to decide right now. You can still send a message.</span>
              </div>
            ) : (
              <>
                {(pendingApproval || needsOwner) && (
                  <Choice
                    onClick={() => approve.open(true)}
                    variant="default"
                    icon={<Check />}
                    label={needsOwner ? "Choose who fixes it" : "Yes, the customer may be right"}
                    help={`Puts ${formatINR(d.amount)} on hold and gives the problem to someone to fix by a date.`}
                  />
                )}
                {pendingApproval && (
                  <>
                    <Choice
                      onClick={() => info.open(true)}
                      icon={<HelpCircle />}
                      label="Ask the salesman for more details"
                      help="The salesman gets a task to answer you."
                    />
                    <Choice
                      onClick={() => reject.open(true)}
                      danger
                      icon={<X />}
                      label="No, the bill is correct"
                      help="The full amount goes back to being chased."
                    />
                  </>
                )}
                {awaitingVerification && (
                  <>
                    <p className="text-[15px]">The problem is reported fixed. Check BUSY, then choose:</p>
                    <Choice
                      variant="default"
                      disabled={action.isPending}
                      loading={running === "Resolved"}
                      onClick={() => resolve("Resolved", "Dispute closed as fixed.")}
                      icon={<ShieldCheck />}
                      label="Yes, it is fixed — close it"
                      help="The dispute is closed."
                    />
                    <Choice
                      danger
                      disabled={action.isPending}
                      loading={running === "Returned to Recovery"}
                      onClick={() => resolve("Returned to Recovery", "Sent back to be chased.")}
                      icon={<Undo2 />}
                      label="No, money is still owed"
                      help="BUSY still shows it due, so it goes back to being chased."
                    />
                  </>
                )}
              </>
            )}
          </div>
        </div>
      </aside>

      <ActionDialog
        {...approve.props}
        title={needsOwner ? "Who should fix this?" : "Accept the dispute"}
        description={`${formatINR(d.amount)} will be put on hold. Choose who fixes the problem and by when.`}
        submitLabel={needsOwner ? "Save" : "Accept and assign"}
        fields={[
          { name: "resolutionOwner", label: "Person fixing it", type: "select", required: true, options: salesmanOptions, defaultValue: salesmanId },
          { name: "department", label: "Department", type: "select", options: DEPARTMENTS.map((x) => ({ value: x, label: x })), defaultValue: DEPARTMENTS[0] },
          { name: "description", label: "What needs to be done", type: "textarea", required: true },
          { name: "note", label: "Note for that person", type: "textarea", required: true },
          { name: "deadline", label: "Fix by", type: "datetime", required: true, defaultValue: deadlineInput(3, 18) },
          { name: "attachmentPath", label: "Attach a file (optional)", type: "file" },
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
            success: "Dispute accepted and assigned.",
          })
        }
      />
      <ActionDialog
        {...reject.props}
        title="The bill is correct"
        description="The full amount goes back to being chased. The salesman will see your reason."
        submitLabel="Reject dispute"
        destructive
        fields={[{ name: "reason", label: "Why the bill is correct", type: "textarea", required: true }]}
        onSubmit={(v) => action.mutateAsync({ path: `${base}/reject`, body: { reason: v.reason }, success: "Dispute rejected." })}
      />
      <ActionDialog
        {...info.props}
        title="Ask for more details"
        description="The salesman gets a task to answer by the date you choose."
        submitLabel="Send question"
        fields={[
          { name: "salesmanId", label: "Ask", type: "select", required: true, options: salesmanOptions, defaultValue: salesmanId },
          { name: "desc", label: "What do you want to know?", type: "textarea", required: true },
          { name: "deadline", label: "Answer by", type: "datetime", required: true, defaultValue: deadlineInput(1, 18) },
        ]}
        onSubmit={(v) =>
          action.mutateAsync({
            path: `${base}/request-info`,
            body: { salesmanId: v.salesmanId, desc: v.desc, deadline: localToIso(v.deadline) },
            success: "Question sent to the salesman.",
          })
        }
      />
    </div>
  );
}

function Fact({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="flex gap-2">
      <dt className="w-32 shrink-0 text-muted-foreground">{label}</dt>
      <dd className="font-semibold break-words">{children}</dd>
    </div>
  );
}

function Row({ label, children }: { label: string; children: ReactNode }) {
  return (
    <div className="flex items-center justify-between gap-4 px-5 py-3 text-[15px]">
      <dt className="text-muted-foreground">{label}</dt>
      <dd className="text-right font-semibold">{children}</dd>
    </div>
  );
}

function Money({ label, note, value, tone }: { label: string; note?: string; value: number; tone: string }) {
  return (
    <div className="rounded-xl border-2 bg-card p-4">
      <div className="text-[15px] font-medium text-muted-foreground">{label}</div>
      <div className={cn("text-2xl font-bold tabular", tone)}>{formatINR(value)}</div>
      {note && <div className="text-sm text-muted-foreground">{note}</div>}
    </div>
  );
}

function Choice({
  label,
  help,
  icon,
  onClick,
  variant = "outline",
  danger,
  disabled,
  loading,
}: {
  loading?: boolean;
  label: string;
  help: string;
  icon: ReactNode;
  onClick: () => void;
  variant?: "default" | "outline";
  danger?: boolean;
  disabled?: boolean;
}) {
  return (
    <div className="space-y-1.5">
      <Button
        size="lg"
        variant={variant}
        disabled={disabled}
        onClick={onClick}
        className={cn("w-full justify-start", danger && "border-red-300 text-red-700 hover:bg-red-50 dark:text-red-300")}
      >
        {loading ? <Loader2 className="animate-spin" /> : icon}
        {loading ? "Please wait…" : label}
      </Button>
      <p className="px-1 text-sm text-muted-foreground">{help}</p>
    </div>
  );
}
