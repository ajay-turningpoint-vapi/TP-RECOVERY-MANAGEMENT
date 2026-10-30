"use client";

import Link from "next/link";
import type { ReactNode } from "react";
import { ChevronRight } from "lucide-react";
import { cn } from "@/lib/utils";
import { HUE, IconTile, type Hue } from "./visual";

const TONE_HUE = { default: "indigo", danger: "rose", warning: "amber", success: "emerald", info: "sky" } as const;
const STRIPE: Record<Hue, string> = {
  indigo: "border-l-blue-600",
  rose: "border-l-red-600",
  amber: "border-l-amber-500",
  emerald: "border-l-green-600",
  violet: "border-l-purple-600",
  sky: "border-l-sky-600",
  slate: "border-l-slate-500",
};

/**
 * One big, flat figure card: plain label, large number, a short line
 * underneath and (when it opens a list) a clearly written "See list" link.
 */
export function KpiCard({
  label,
  value,
  format,
  hint,
  icon,
  href,
  tone = "default",
  hue,
  loading,
  linkText = "See list",
}: {
  label: string;
  value: ReactNode | number;
  format?: (v: number) => string;
  hint?: ReactNode;
  icon?: ReactNode;
  href?: string;
  tone?: keyof typeof TONE_HUE;
  hue?: Hue;
  loading?: boolean;
  linkText?: string;
}) {
  const h = hue ?? TONE_HUE[tone];
  const shown = typeof value === "number" && format ? format(value) : value;
  const body = (
    <div
      className={cn(
        "flex h-full flex-col gap-2 rounded-xl border-2 border-l-[6px] bg-card p-4 transition-colors",
        STRIPE[h],
        href && "hover:border-primary hover:bg-accent/40",
      )}
    >
      <div className="flex items-center gap-3">
        {icon && <IconTile hue={h} size="sm">{icon}</IconTile>}
        <span className="text-[15px] leading-snug font-semibold text-foreground">{label}</span>
      </div>
      {loading ? (
        <div className="h-10 w-40 animate-pulse rounded-lg bg-muted" />
      ) : (
        <div className={cn("text-2xl leading-tight font-bold tracking-tight tabular", HUE[h].text)}>{shown}</div>
      )}
      {hint && <div className="text-sm text-muted-foreground">{hint}</div>}
      {href && (
        <span className="mt-auto inline-flex items-center gap-1 pt-1 text-sm font-semibold text-primary">
          {linkText} <ChevronRight className="size-5" />
        </span>
      )}
    </div>
  );
  return href ? (
    <Link href={href} className="block h-full rounded-xl">
      {body}
    </Link>
  ) : (
    body
  );
}
