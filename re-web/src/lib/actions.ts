"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { rmsPost } from "./api";

type ActionVars = { path: string; body?: unknown; success?: string };

/**
 * Every RE command goes through here: POST with an idempotency key, toast
 * the outcome, then invalidate everything (one command can move several
 * lists server-side — record-outcome style fan-out). SSE will also push
 * the same invalidation to every other open client.
 */
export function useRmsAction() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ path, body }: ActionVars) => rmsPost(path, body ?? {}),
    onSuccess: (_d, v) => {
      if (v.success) toast.success(v.success);
      qc.invalidateQueries();
    },
    onError: (e) => toast.error(e instanceof Error ? e.message : "Action failed"),
  });
}

/** `datetime-local` value → ISO string the API's z.coerce.date() accepts. */
export const localToIso = (v: string) => new Date(v).toISOString();

/** Default deadline helper: today/tomorrow at a given hour, formatted for a datetime-local input. */
export function deadlineInput(daysFromNow: number, hour: number) {
  const d = new Date();
  d.setDate(d.getDate() + daysFromNow);
  d.setHours(hour, 0, 0, 0);
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}
