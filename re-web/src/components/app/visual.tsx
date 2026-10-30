import type { ReactNode } from "react";
import { cn } from "@/lib/utils";
import { initials } from "@/lib/format";

export type Hue = "indigo" | "rose" | "amber" | "emerald" | "violet" | "sky" | "slate";

/**
 * Matte colour set per hue: a light solid tile with a dark icon/text on
 * it (high contrast, no gradients), plus a solid bar colour.
 */
export const HUE: Record<Hue, { tile: string; wash: string; text: string; ring: string; bar: string; solid: string }> = {
  indigo: { tile: "bg-blue-100 text-blue-800 dark:bg-blue-500/25 dark:text-blue-100", wash: "", text: "text-blue-800 dark:text-blue-200", ring: "#1d4ed8", bar: "bg-blue-600", solid: "bg-blue-700 text-white" },
  rose: { tile: "bg-red-100 text-red-800 dark:bg-red-500/25 dark:text-red-100", wash: "", text: "text-red-700 dark:text-red-300", ring: "#b91c1c", bar: "bg-red-600", solid: "bg-red-700 text-white" },
  amber: { tile: "bg-amber-100 text-amber-900 dark:bg-amber-500/25 dark:text-amber-100", wash: "", text: "text-amber-800 dark:text-amber-300", ring: "#b45309", bar: "bg-amber-500", solid: "bg-amber-600 text-white" },
  emerald: { tile: "bg-green-100 text-green-800 dark:bg-green-500/25 dark:text-green-100", wash: "", text: "text-green-800 dark:text-green-300", ring: "#15803d", bar: "bg-green-600", solid: "bg-green-700 text-white" },
  violet: { tile: "bg-purple-100 text-purple-800 dark:bg-purple-500/25 dark:text-purple-100", wash: "", text: "text-purple-800 dark:text-purple-300", ring: "#7e22ce", bar: "bg-purple-600", solid: "bg-purple-700 text-white" },
  sky: { tile: "bg-sky-100 text-sky-900 dark:bg-sky-500/25 dark:text-sky-100", wash: "", text: "text-sky-800 dark:text-sky-300", ring: "#0369a1", bar: "bg-sky-600", solid: "bg-sky-700 text-white" },
  slate: { tile: "bg-slate-200 text-slate-800 dark:bg-slate-500/25 dark:text-slate-100", wash: "", text: "text-slate-700 dark:text-slate-300", ring: "#475569", bar: "bg-slate-500", solid: "bg-slate-700 text-white" },
};

export function IconTile({ hue = "indigo", size = "md", children, className }: { hue?: Hue; size?: "sm" | "md" | "lg"; children: ReactNode; className?: string }) {
  return (
    <span
      className={cn(
        "flex shrink-0 items-center justify-center",
        size === "sm" && "size-9 rounded-lg [&_svg]:size-[18px]",
        size === "md" && "size-10 rounded-xl [&_svg]:size-5",
        size === "lg" && "size-12 rounded-xl [&_svg]:size-6",
        HUE[hue].tile,
        className,
      )}
    >
      {children}
    </span>
  );
}

const AVATAR_HUES: Hue[] = ["indigo", "violet", "sky", "emerald", "amber", "rose"];
const hash = (s: string) => [...s].reduce((h, c) => (h * 31 + c.charCodeAt(0)) | 0, 7);

/** Name initials on a stable matte colour per person/customer. */
export function ColorAvatar({ name, size = "md", className }: { name: string; size?: "sm" | "md" | "lg"; className?: string }) {
  const hue = AVATAR_HUES[Math.abs(hash(name)) % AVATAR_HUES.length];
  return (
    <span
      aria-hidden
      className={cn(
        "flex shrink-0 items-center justify-center rounded-full font-bold",
        size === "sm" && "size-8 text-xs",
        size === "md" && "size-9 text-[13px]",
        size === "lg" && "size-14 text-lg",
        HUE[hue].tile,
        className,
      )}
    >
      {initials(name) || "?"}
    </span>
  );
}

/** Circular progress ring (0–100+), value clamped for drawing only. */
export function RingGauge({ value, size = 120, stroke = 10, color = "#1d4ed8", track = "#e2e8f0", children }: { value: number; size?: number; stroke?: number; color?: string; track?: string; children?: ReactNode }) {
  const r = (size - stroke) / 2;
  const c = 2 * Math.PI * r;
  const p = Math.max(0, Math.min(100, value));
  return (
    <div className="relative" style={{ width: size, height: size }}>
      <svg width={size} height={size} className="-rotate-90">
        <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke={track} strokeWidth={stroke} />
        <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke={color} strokeWidth={stroke} strokeLinecap="round" strokeDasharray={c} strokeDashoffset={c * (1 - p / 100)} />
      </svg>
      <div className="absolute inset-0 flex flex-col items-center justify-center text-center">{children}</div>
    </div>
  );
}

/** Solid progress bar. */
export function GradientBar({ value, hue = "indigo", className }: { value: number; hue?: Hue; className?: string }) {
  return (
    <div className={cn("h-2.5 overflow-hidden rounded-full bg-slate-200 dark:bg-slate-700", className)}>
      <div className={cn("h-full rounded-full", HUE[hue].bar)} style={{ width: `${Math.max(0, Math.min(100, value))}%` }} />
    </div>
  );
}
