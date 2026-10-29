import { format, formatDistanceToNowStrict, isToday, isTomorrow, isYesterday } from "date-fns";

const inr = new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR", maximumFractionDigits: 0 });
const num = new Intl.NumberFormat("en-IN");

export const formatINR = (v: number | null | undefined) => inr.format(Math.round(v ?? 0));
export const formatNumber = (v: number | null | undefined) => num.format(v ?? 0);

/** ₹12.4 L / ₹1.2 Cr — Indian compact units for KPI tiles and chart axes. */
export function formatINRCompact(v: number | null | undefined) {
  const n = v ?? 0;
  const abs = Math.abs(n);
  if (abs >= 1e7) return `₹${(n / 1e7).toFixed(abs >= 1e8 ? 1 : 2)} Cr`;
  if (abs >= 1e5) return `₹${(n / 1e5).toFixed(abs >= 1e6 ? 1 : 2)} L`;
  if (abs >= 1e3) return `₹${(n / 1e3).toFixed(1)} K`;
  return inr.format(Math.round(n));
}

export function formatDate(d: Date | null | undefined, pattern = "dd MMM yyyy") {
  return d ? format(d, pattern) : "—";
}

export function formatDateTime(d: Date | null | undefined) {
  return d ? format(d, "dd MMM yyyy, h:mm a") : "—";
}

export function formatRelativeDay(d: Date | null | undefined) {
  if (!d) return "—";
  if (isToday(d)) return `Today, ${format(d, "h:mm a")}`;
  if (isTomorrow(d)) return `Tomorrow, ${format(d, "h:mm a")}`;
  if (isYesterday(d)) return `Yesterday, ${format(d, "h:mm a")}`;
  return format(d, "dd MMM, h:mm a");
}

export function timeAgo(d: Date | null | undefined) {
  return d ? `${formatDistanceToNowStrict(d)} ago` : "—";
}

export function initials(name: string) {
  return name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map((p) => p[0]!.toUpperCase())
    .join("");
}
