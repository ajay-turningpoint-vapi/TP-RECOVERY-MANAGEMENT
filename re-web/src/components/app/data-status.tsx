"use client";

import { useEffect, useState } from "react";
import { CircleAlert, Loader2, RefreshCw, WifiOff } from "lucide-react";
import { Button } from "@/components/ui/button";
import { friendlyError } from "@/lib/api";
import { useRefreshAll, useRms } from "@/lib/queries";

/**
 * One status bar above every page, so data loading is never silent:
 * "Loading…" on the first load, a red alert with "Try again" when the
 * server could not be reached, and an amber bar when the internet drops.
 */
export function DataStatus() {
  const { isLoading, error } = useRms();
  const refresh = useRefreshAll();
  const [retrying, setRetrying] = useState(false);
  const [online, setOnline] = useState(true);

  useEffect(() => {
    const update = () => setOnline(navigator.onLine);
    update();
    window.addEventListener("online", update);
    window.addEventListener("offline", update);
    return () => {
      window.removeEventListener("online", update);
      window.removeEventListener("offline", update);
    };
  }, []);

  if (!online) {
    return (
      <Bar tone="amber" icon={<WifiOff className="size-5" />}>
        <span className="font-semibold">No internet connection.</span> You are seeing the last data that loaded. It will update when the internet is back.
      </Bar>
    );
  }

  if (error) {
    return (
      <Bar tone="red" icon={<CircleAlert className="size-5" />}>
        <span className="flex-1">
          <span className="font-semibold">Some data could not be loaded.</span> {friendlyError(error)}
        </span>
        <Button
          variant="outline"
          className="shrink-0 border-red-300 bg-white text-red-800 hover:bg-red-100"
          disabled={retrying}
          onClick={async () => {
            setRetrying(true);
            await refresh();
            setRetrying(false);
          }}
        >
          {retrying ? <Loader2 className="animate-spin" /> : <RefreshCw />}
          Try again
        </Button>
      </Bar>
    );
  }

  if (isLoading) {
    return (
      <Bar tone="blue" icon={<Loader2 className="size-5 animate-spin" />}>
        <span className="font-semibold">Loading the latest data…</span> This takes a few seconds.
      </Bar>
    );
  }

  return null;
}

const TONES = {
  blue: "border-sky-200 bg-sky-50 text-sky-900 dark:border-sky-500/30 dark:bg-sky-500/10 dark:text-sky-100",
  red: "border-red-300 bg-red-50 text-red-900 dark:border-red-500/30 dark:bg-red-500/10 dark:text-red-100",
  amber: "border-amber-300 bg-amber-50 text-amber-900 dark:border-amber-500/30 dark:bg-amber-500/10 dark:text-amber-100",
};

function Bar({ tone, icon, children }: { tone: keyof typeof TONES; icon: React.ReactNode; children: React.ReactNode }) {
  return (
    <div role={tone === "blue" ? "status" : "alert"} className={`mb-5 flex flex-wrap items-center gap-3 rounded-xl border-2 px-4 py-3 text-[15px] ${TONES[tone]}`}>
      {icon}
      {children}
    </div>
  );
}
