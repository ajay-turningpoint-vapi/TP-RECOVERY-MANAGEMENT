"use client";

import type { ReactNode } from "react";

/*
 * Calm UI: no page slide-ins, staggered entrances or counting numbers —
 * figures appear immediately and stay still, which is easier to read.
 * These wrappers are kept so pages don't need to change.
 */
export function PageTransition({ children }: { children: ReactNode }) {
  return <>{children}</>;
}

export function Stagger({ children, className }: { children: ReactNode[]; className?: string; step?: number }) {
  return <div className={className}>{children}</div>;
}

export function CountUp({ value, format, className }: { value: number; format: (v: number) => string; className?: string }) {
  return <span className={className ? `tabular ${className}` : "tabular"}>{format(value)}</span>;
}
