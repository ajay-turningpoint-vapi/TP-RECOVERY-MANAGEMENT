import { Badge } from "@/components/ui/badge";
import { cn } from "@/lib/utils";
import { creditHealthBand, PTP_STATUS_LABEL, type PtpStatus } from "@/lib/models";

type Tone = "neutral" | "info" | "success" | "warning" | "danger" | "violet";

const TONE_CLASS: Record<Tone, string> = {
  neutral: "bg-slate-500/10 text-slate-600 ring-slate-500/15 dark:text-slate-300 [--dot:var(--color-slate-400)]",
  info: "bg-sky-500/10 text-sky-700 ring-sky-500/20 dark:text-sky-300 [--dot:var(--color-sky-500)]",
  success: "bg-emerald-500/10 text-emerald-700 ring-emerald-500/20 dark:text-emerald-300 [--dot:var(--color-emerald-500)]",
  warning: "bg-amber-500/12 text-amber-700 ring-amber-500/25 dark:text-amber-300 [--dot:var(--color-amber-500)]",
  danger: "bg-rose-500/10 text-rose-700 ring-rose-500/20 dark:text-rose-300 [--dot:var(--color-rose-500)]",
  violet: "bg-violet-500/10 text-violet-700 ring-violet-500/20 dark:text-violet-300 [--dot:var(--color-violet-500)]",
};

export function Pill({ tone = "neutral", children, className }: { tone?: Tone; children: React.ReactNode; className?: string }) {
  return (
    <Badge variant="secondary" className={cn("gap-1.5 rounded-full border-0 pr-2.5 pl-2 font-semibold ring-1 ring-inset", TONE_CLASS[tone], className)}>
      <span aria-hidden className="size-1.5 shrink-0 rounded-full bg-(--dot)" />
      {children}
    </Badge>
  );
}

const PTP_TONE: Record<PtpStatus, Tone> = {
  scheduled: "info",
  pendingVerification: "warning",
  kept: "success",
  partiallyKept: "warning",
  broken: "danger",
  financialSyncPending: "neutral",
};

export const PtpStatusBadge = ({ status }: { status: PtpStatus }) => (
  <Pill tone={PTP_TONE[status] ?? "neutral"}>{PTP_STATUS_LABEL[status] ?? status}</Pill>
);

export function PriorityBadge({ priority }: { priority: string }) {
  const p = priority.toUpperCase();
  const tone: Tone = p === "HIGH" || p === "CRITICAL" ? "danger" : p === "MEDIUM" || p === "NORMAL" ? "warning" : "info";
  // Plain words: High/Critical → Urgent, Medium/Normal → Normal, Low → Low.
  const label = p === "HIGH" || p === "CRITICAL" ? "Urgent" : p === "MEDIUM" || p === "NORMAL" ? "Normal" : "Low";
  return <Pill tone={tone}>{label}</Pill>;
}

export function EscalationBadge({ level }: { level: string }) {
  if (!level || level === "none") return <span className="text-muted-foreground">—</span>;
  const tone: Tone = level === "L4" ? "danger" : level === "L3" ? "danger" : level === "L2" ? "warning" : "info";
  return <Pill tone={tone}>{level}</Pill>;
}

export function CreditHealthBadge({ score }: { score: number | null }) {
  const band = creditHealthBand(score);
  const tone: Tone =
    band === "Low Risk" ? "success" : band === "Moderate" ? "info" : band === "High" ? "warning" : band === "Critical" ? "danger" : "neutral";
  return (
    <Pill tone={tone}>
      {band}
      {score != null && <span className="tabular opacity-70">· {score}</span>}
    </Pill>
  );
}

export function DisputeStatusBadge({ status }: { status: string }) {
  const tone: Tone =
    status === "Pending Approval" || status === "Awaiting Verification"
      ? "warning"
      : status === "Resolved" || status === "Auto-Closed"
        ? "success"
        : status === "Rejected" || status === "Returned to Recovery"
          ? "danger"
          : status === "Need More Information"
            ? "violet"
            : "info";
  return <Pill tone={tone}>{status}</Pill>;
}

export function ClaimStatusBadge({ status }: { status: string }) {
  const tone: Tone = status === "Verified" ? "success" : status === "Failed" ? "danger" : "warning";
  return <Pill tone={tone}>{status}</Pill>;
}

export function RecoveryStateBadge({ state }: { state: string }) {
  if (!state) return <span className="text-muted-foreground">—</span>;
  const s = state.toLowerCase();
  const tone: Tone = s.includes("broken") || s.includes("action required")
    ? "danger"
    : s.includes("ptp") || s.includes("promise")
      ? "info"
      : s.includes("dispute")
        ? "violet"
        : s.includes("resolved") || s.includes("paid")
          ? "success"
          : "neutral";
  return <Pill tone={tone}>{state}</Pill>;
}
