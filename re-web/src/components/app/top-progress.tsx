"use client";

import { cn } from "@/lib/utils";

/** Thin indeterminate bar under the top bar while any data is re-fetching. */
export function TopProgress({ active }: { active: boolean }) {
  return (
    <div
      aria-hidden
      className={cn(
        "pointer-events-none absolute inset-x-0 bottom-0 h-0.5 overflow-hidden transition-opacity duration-300",
        active ? "opacity-100" : "opacity-0",
      )}
    >
      <div className="h-full w-1/3 animate-[progress_1.1s_ease-in-out_infinite] rounded-full bg-primary/70" />
    </div>
  );
}
