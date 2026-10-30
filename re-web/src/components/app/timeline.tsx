"use client";

import { format, isToday, isYesterday } from "date-fns";
import {
  ArrowRight,
  ClipboardList,
  FileWarning,
  Handshake,
  IndianRupee,
  MapPin,
  Phone,
  RefreshCw,
  ShieldCheck,
  Siren,
  UserRoundCog,
  type LucideIcon,
} from "lucide-react";
import type { AuditEvent } from "@/lib/models";
import { cn } from "@/lib/utils";
import { AttachmentLink } from "./attachment-link";
import { HUE, type Hue } from "./visual";

type Kind = { title: string; icon: LucideIcon; hue: Hue };

/**
 * Turns an audit event into a plain title + icon + colour. Matches on the
 * event type, source and wording, since types are free-form server strings.
 */
function kindOf(e: AuditEvent): Kind {
  const t = `${e.type} ${e.source}`.toUpperCase();
  const d = e.description.toLowerCase();
  if (/ESCALAT/.test(t) || d.includes("escalat")) return { title: "Escalation", icon: Siren, hue: "rose" };
  if (/DISPUTE/.test(t) || d.includes("dispute")) return { title: "Bill dispute", icon: FileWarning, hue: "violet" };
  if (/CLAIM|RECEIPT|PAYMENT_VERIF|PAID/.test(t) || d.includes("payment already made")) return { title: "Payment", icon: IndianRupee, hue: "emerald" };
  if (/PTP|PROMISE/.test(t) || d.includes("ptp") || d.includes("promise")) return { title: "Payment promise", icon: Handshake, hue: "violet" };
  if (/VISIT/.test(t) || d.includes("visit")) return { title: "Visit", icon: MapPin, hue: "amber" };
  if (/OWNER|REASSIGN/.test(t) || d.includes("reassigned")) return { title: "Salesman changed", icon: UserRoundCog, hue: "sky" };
  if (/CONTROL/.test(t)) return { title: "RE control", icon: ShieldCheck, hue: "indigo" };
  if (/OUTCOME|CALL|NO_ANSWER|ANSWER/.test(t) || d.includes("outcome") || d.includes("called")) return { title: "Call result", icon: Phone, hue: "sky" };
  if (/TASK|INSTRUCTION/.test(t) || d.includes("task")) return { title: "Task", icon: ClipboardList, hue: "indigo" };
  if (e.actor === "System" || /SYNC|BUSY/.test(t)) return { title: "System update", icon: RefreshCw, hue: "slate" };
  return { title: "Update", icon: ClipboardList, hue: "slate" };
}

const dayLabel = (d: Date) => (isToday(d) ? "Today" : isYesterday(d) ? "Yesterday" : format(d, "EEEE, d MMMM yyyy"));

/** Vertical, day-grouped customer history. */
export function Timeline({ events }: { events: AuditEvent[] }) {
  const sorted = [...events].sort((a, b) => +b.timestamp - +a.timestamp);
  const days: { label: string; items: AuditEvent[] }[] = [];
  for (const e of sorted) {
    const label = dayLabel(e.timestamp);
    const last = days[days.length - 1];
    if (last && last.label === label) last.items.push(e);
    else days.push({ label, items: [e] });
  }

  return (
    <div className="space-y-8">
      {days.map((day) => (
        <section key={day.label}>
          {/* Day header */}
          <div className="mb-4 flex items-center gap-3">
            <span className="rounded-full bg-primary px-3 py-1 text-sm font-bold text-primary-foreground">{day.label}</span>
            <span className="h-0.5 flex-1 bg-border" />
            <span className="text-sm text-muted-foreground">
              {day.items.length} {day.items.length === 1 ? "event" : "events"}
            </span>
          </div>

          <ol>
            {day.items.map((e, i) => {
              const k = kindOf(e);
              const lastInDay = i === day.items.length - 1;
              const system = e.actor === "System";
              return (
                <li key={e.id ?? `${+e.timestamp}-${i}`} className="grid grid-cols-[4.5rem_2.75rem_1fr] gap-x-3 sm:grid-cols-[5.5rem_3rem_1fr]">
                  {/* Time */}
                  <div className="pt-2.5 text-right text-sm font-semibold text-muted-foreground tabular">{format(e.timestamp, "h:mm a")}</div>

                  {/* Line + icon node */}
                  <div className="relative flex justify-center">
                    {!lastInDay && <span aria-hidden className="absolute top-11 bottom-0 w-0.5 bg-border" />}
                    <span className={cn("relative z-10 flex size-10 items-center justify-center rounded-full ring-4 ring-card", HUE[k.hue].tile)}>
                      <k.icon className="size-5" />
                    </span>
                  </div>

                  {/* Event card */}
                  <div className={cn("mb-4 rounded-xl border-2 bg-card p-4", system && "border-dashed bg-muted/30")}>
                    <div className="flex flex-wrap items-center justify-between gap-2">
                      <span className={cn("text-[15px] font-bold", HUE[k.hue].text)}>{k.title}</span>
                      <span className="text-sm text-muted-foreground">
                        by <span className="font-semibold text-foreground">{system ? "System" : e.actor}</span>
                        {e.source && e.source !== "App" && <> · {e.source}</>}
                      </span>
                    </div>
                    <p className="mt-1.5 text-[15px] leading-relaxed break-words">{e.description}</p>
                    {e.previousState && e.newState && e.previousState !== e.newState && (
                      <div className="mt-3 flex flex-wrap items-center gap-2 text-sm">
                        <span className="rounded-md bg-muted px-2 py-1 font-medium">{e.previousState}</span>
                        <ArrowRight className="size-4 text-muted-foreground" />
                        <span className="rounded-md bg-primary/10 px-2 py-1 font-semibold text-primary">{e.newState}</span>
                      </div>
                    )}
                    {e.attachmentPath && <AttachmentLink path={e.attachmentPath} />}
                  </div>
                </li>
              );
            })}
          </ol>
        </section>
      ))}
    </div>
  );
}
