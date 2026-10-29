import { Badge } from "@/components/ui/badge";
import { cn } from "@/lib/utils";
import { creditHealthBand, PTP_STATUS_LABEL, type PtpStatus } from "@/lib/models";

type Tone = "neutral" | "info" | "success" | "warning" | "danger" | "violet";

const TONE_CLASS: Record<Tone, string> = {
  neutral: "bg-muted text-muted-foreground",
  info: "bg-info/10 text-info",
  success: "bg-success/12 text-success",
  warning: "bg-warning/14 text-warning",
  danger: "bg-destructive/10 text-destructive",
  violet: "bg-violet/10 text-violet",
};

export function Pill({ tone = "neutral", children, className }: { tone?: Tone; children: React.ReactNode; className?: string }) {
  return (
    <Badge variant="secondary" className={cn("rounded-md border-0 font-medium", TONE_CLASS[tone], className)}>
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
  const label = priority.charAt(0).toUpperCase() + priority.slice(1).toLowerCase();
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
