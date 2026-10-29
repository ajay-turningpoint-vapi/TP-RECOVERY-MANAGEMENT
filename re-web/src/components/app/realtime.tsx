"use client";

import { useEffect, useRef } from "react";
import { useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { redirectToLogin, refreshSession } from "@/lib/api";

/**
 * One SSE stream (GET /api/events via the BFF proxy) → TanStack Query
 * invalidations. Same event handling as AppStore._onRealtimeEvent:
 * 'invalidate' re-fetches just the named lists (+ the dashboard when core
 * lists move), 'notification' re-fetches notifications, 'sync' refreshes
 * the freshness pill, 'session-revoked' (web channel only — server
 * migration 040) signs this browser out.
 *
 * Uses fetch + a stream reader rather than EventSource so a 401 on
 * reconnect (expired access token) can refresh the session first.
 */
const CORE = new Set(["customers", "tasks", "ptps", "disputes"]);

export function RealtimeBridge() {
  const qc = useQueryClient();
  const pending = useRef(new Set<string>());
  const timer = useRef<ReturnType<typeof setTimeout> | null>(null);

  useEffect(() => {
    let stopped = false;
    let controller: AbortController | null = null;
    let backoff = 1000;
    let firstConnect = true;

    const flush = () => {
      const keys = [...pending.current];
      pending.current.clear();
      for (const k of keys) {
        if (k.startsWith("customer:")) qc.invalidateQueries({ queryKey: ["customer", k.slice(9)] });
        else qc.invalidateQueries({ queryKey: [k] });
      }
      if (keys.some((k) => CORE.has(k))) qc.invalidateQueries({ queryKey: ["reports"] });
    };

    const queue = (keys: string[]) => {
      keys.forEach((k) => pending.current.add(k));
      if (timer.current) clearTimeout(timer.current);
      timer.current = setTimeout(flush, 250);
    };

    const handle = (type: string, data: Record<string, unknown>) => {
      switch (type) {
        case "invalidate": {
          const resources = (data.resources as string[] | undefined) ?? [];
          const customerId = data.customerId as string | undefined;
          queue(customerId ? [...resources, `customer:${customerId}`] : resources);
          break;
        }
        case "notification":
          queue(["notifications"]);
          break;
        case "sync":
          qc.invalidateQueries({ queryKey: ["sync-status"] });
          if (data.phase === "finished") qc.invalidateQueries();
          break;
        case "session-revoked":
          // The server only sends web-channel revocations to web streams.
          // Our own login's echo can't reach us: this stream opens after login.
          toast.error("This account signed in on another browser, so you were signed out here.");
          setTimeout(() => {
            fetch("/api/auth/logout", { method: "POST" }).finally(() => redirectToLogin("revoked"));
          }, 1500);
          stopped = true;
          controller?.abort();
          break;
        case "maintenance":
          if (data.enabled) toast.warning("TP-RMS is under maintenance. Some actions may be unavailable.");
          break;
      }
    };

    const connect = async () => {
      while (!stopped) {
        controller = new AbortController();
        try {
          const res = await fetch("/api/rms/events", {
            headers: { Accept: "text/event-stream" },
            signal: controller.signal,
            cache: "no-store",
          });
          if (res.status === 401) {
            if (!(await refreshSession())) {
              redirectToLogin("expired");
              return;
            }
            continue;
          }
          if (!res.ok || !res.body) throw new Error(`events ${res.status}`);

          // Reconnected after a gap — catch up on anything missed.
          if (!firstConnect) qc.invalidateQueries();
          firstConnect = false;
          backoff = 1000;

          const reader = res.body.pipeThrough(new TextDecoderStream()).getReader();
          let buf = "";
          for (;;) {
            const { value, done } = await reader.read();
            if (done) break;
            buf += value;
            let idx: number;
            while ((idx = buf.indexOf("\n\n")) >= 0) {
              const block = buf.slice(0, idx);
              buf = buf.slice(idx + 2);
              let type = "message";
              let payload = "";
              for (const line of block.split("\n")) {
                if (line.startsWith("event:")) type = line.slice(6).trim();
                else if (line.startsWith("data:")) payload += line.slice(5).trim();
              }
              if (!payload) continue;
              try {
                handle(type, JSON.parse(payload));
              } catch {
                /* malformed event — ignore */
              }
            }
          }
        } catch {
          if (stopped) return;
        }
        if (stopped) return;
        await new Promise((r) => setTimeout(r, backoff));
        backoff = Math.min(backoff * 2, 30_000);
      }
    };

    connect();
    return () => {
      stopped = true;
      controller?.abort();
      if (timer.current) clearTimeout(timer.current);
    };
  }, [qc]);

  return null;
}
