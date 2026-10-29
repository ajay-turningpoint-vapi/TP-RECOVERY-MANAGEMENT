import Link from "next/link";
import type { ReactNode } from "react";
import { ArrowUpRight } from "lucide-react";
import { cn } from "@/lib/utils";

const TONES = {
  default: "text-foreground",
  danger: "text-destructive",
  warning: "text-warning",
  success: "text-success",
  info: "text-info",
} as const;

export function KpiCard({
  label,
  value,
  hint,
  icon,
  href,
  tone = "default",
  loading,
}: {
  label: string;
  value: ReactNode;
  hint?: ReactNode;
  icon?: ReactNode;
  href?: string;
  tone?: keyof typeof TONES;
  loading?: boolean;
}) {
  const body = (
    <div
      className={cn(
        "group relative flex h-full flex-col justify-between gap-3 rounded-xl border bg-card p-4 shadow-xs transition-colors",
        href && "hover:border-primary/40 hover:bg-accent/40",
      )}
    >
      <div className="flex items-start justify-between gap-2">
        <span className="text-xs font-medium text-muted-foreground">{label}</span>
        {href ? (
          <ArrowUpRight className="size-3.5 text-muted-foreground/60 transition-colors group-hover:text-primary" />
        ) : (
          icon && <span className="text-muted-foreground/70 [&_svg]:size-4">{icon}</span>
        )}
      </div>
      <div className="space-y-1">
        {loading ? (
          <div className="h-7 w-24 animate-pulse rounded bg-muted" />
        ) : (
          <div className={cn("tabular text-2xl font-semibold tracking-tight", TONES[tone])}>{value}</div>
        )}
        {hint && <div className="text-xs text-muted-foreground">{hint}</div>}
      </div>
    </div>
  );
  return href ? (
    <Link href={href} className="block h-full focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring rounded-xl">
      {body}
    </Link>
  ) : (
    body
  );
}
