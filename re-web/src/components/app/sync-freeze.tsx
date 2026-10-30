"use client";

import { useEffect, useRef, useState } from "react";
import { createPortal } from "react-dom";
import { RefreshCw } from "lucide-react";
import { toast } from "sonner";
import { isSyncFrozen, useSyncStatus } from "@/lib/queries";

/**
 * Web copy of the app's SyncFreezeOverlay: while the daily BUSY sync is
 * rewriting customer / PTP / task data on the server, the whole page is
 * locked behind one message. Everything else on the page is made `inert`
 * (no clicks, typing or focus, open dialogs included) and keyboard
 * shortcuts are swallowed, so nothing is read or saved half-way through.
 */
export function SyncFreeze() {
  const { data } = useSyncStatus();
  const [now, setNow] = useState(() => Date.now());
  const frozen = isSyncFrozen(data, now);
  const root = useRef<HTMLDivElement>(null);
  const wasFrozen = useRef(false);

  // Tick for the "started … ago" line and the 20-minute backstop.
  useEffect(() => {
    if (!data?.syncing) return;
    const t = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(t);
  }, [data?.syncing]);

  // Lock everything except this message; unlock when the sync ends.
  useEffect(() => {
    if (!frozen) {
      if (wasFrozen.current) toast.success("Sync with BUSY finished. You can continue working.");
      wasFrozen.current = false;
      return;
    }
    wasFrozen.current = true;
    const others = [...document.body.children].filter((el) => el !== root.current) as HTMLElement[];
    const prev = others.map((el) => el.inert);
    others.forEach((el) => (el.inert = true));
    (document.activeElement as HTMLElement | null)?.blur();
    const swallow = (e: KeyboardEvent) => {
      e.preventDefault();
      e.stopImmediatePropagation();
    };
    window.addEventListener("keydown", swallow, true);
    return () => {
      others.forEach((el, i) => (el.inert = prev[i]));
      window.removeEventListener("keydown", swallow, true);
    };
  }, [frozen]);

  if (!frozen || typeof document === "undefined") return null;

  const since = data?.since ? Date.parse(data.since) : NaN;
  const secs = Number.isNaN(since) ? 0 : Math.max(0, Math.floor((now - since) / 1000));
  const elapsed = secs < 60 ? "Started just now" : `Started ${Math.floor(secs / 60)} min ago`;

  return createPortal(
    <div
      ref={root}
      role="alertdialog"
      aria-modal="true"
      aria-labelledby="sync-freeze-title"
      aria-describedby="sync-freeze-body"
      className="fixed inset-0 z-[1000] flex items-center justify-center bg-slate-950/70 p-4"
    >
      <div className="w-full max-w-md rounded-2xl border-2 bg-card p-8 text-center shadow-xl">
        <div className="mx-auto flex size-16 items-center justify-center rounded-full bg-primary/10">
          <RefreshCw className="size-8 animate-spin text-primary [animation-duration:2s]" />
        </div>
        <h2 id="sync-freeze-title" className="mt-5 text-2xl font-bold">
          Syncing with BUSY
        </h2>
        <p id="sync-freeze-body" className="mt-3 text-base leading-relaxed text-muted-foreground">
          Customer money, payment promises and tasks are being updated from BUSY. Please wait — you cannot do anything until
          this finishes. This page will open again by itself.
        </p>
        <div className="mt-6 h-2 overflow-hidden rounded-full bg-muted">
          <div className="h-full w-2/5 animate-[sync-slide_1.6s_ease-in-out_infinite] rounded-full bg-primary" />
        </div>
        <p className="mt-4 text-sm font-semibold text-muted-foreground tabular">{elapsed}</p>
        <p className="mt-1 text-sm text-muted-foreground">Usually done in a few minutes.</p>
      </div>
    </div>,
    document.body,
  );
}
