"use client";

import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";

export const NAV_SHORTCUTS: [string, string, string][] = [
  ["d", "/dashboard", "Control Dashboard"],
  ["t", "/tasks", "My Tasks"],
  ["a", "/approvals", "Approval Inbox"],
  ["q", "/queue", "Recovery Queue"],
  ["c", "/customers", "Customers"],
  ["p", "/ptps", "Promises to Pay"],
  ["s", "/salesmen", "Salesmen"],
  ["e", "/escalations", "Escalations"],
  ["i", "/disputes", "Disputes"],
  ["r", "/reports", "Reports"],
  ["n", "/notifications", "Notifications"],
  ["f", "/control", "5 PM Control"],
];

const typing = (el: EventTarget | null) =>
  el instanceof HTMLElement && (el.isContentEditable || ["INPUT", "TEXTAREA", "SELECT"].includes(el.tagName));

/** "g" then a letter jumps to a page; "?" lists the shortcuts. Ignored while typing. */
export function Shortcuts() {
  const router = useRouter();
  const [open, setOpen] = useState(false);
  const pendingG = useRef(0);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.metaKey || e.ctrlKey || e.altKey || typing(e.target)) return;
      if (e.key === "?") {
        e.preventDefault();
        setOpen(true);
        return;
      }
      if (e.key === "g") {
        pendingG.current = Date.now();
        return;
      }
      if (Date.now() - pendingG.current < 1200) {
        const hit = NAV_SHORTCUTS.find(([k]) => k === e.key.toLowerCase());
        pendingG.current = 0;
        if (hit) {
          e.preventDefault();
          router.push(hit[1]);
        }
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [router]);

  return (
    <Dialog open={open} onOpenChange={setOpen}>
      <DialogContent className="sm:max-w-md">
        <DialogHeader>
          <DialogTitle>Keyboard shortcuts</DialogTitle>
          <DialogDescription>Work the queue without leaving the keyboard.</DialogDescription>
        </DialogHeader>
        <div className="grid grid-cols-2 gap-x-6 gap-y-2 text-sm">
          <Row keys={["?"]} label="This help" />
          {NAV_SHORTCUTS.map(([k, , label]) => (
            <Row key={k} keys={["g", k]} label={label} />
          ))}
        </div>
      </DialogContent>
    </Dialog>
  );
}

function Row({ keys, label }: { keys: string[]; label: string }) {
  return (
    <div className="flex items-center justify-between gap-3">
      <span className="text-muted-foreground">{label}</span>
      <span className="flex gap-1">
        {keys.map((k) => (
          <kbd key={k} className="min-w-5 rounded border bg-muted px-1.5 text-center font-mono text-[11px]">
            {k}
          </kbd>
        ))}
      </span>
    </div>
  );
}
