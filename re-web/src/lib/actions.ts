"use client";

import { useMutation, useQueryClient } from "@tanstack/react-query";
import { toast } from "sonner";
import { ApiError, friendlyError, rmsPost } from "./api";
import type { SyncStatus } from "./models";
import { isSyncFrozen } from "./queries";

type ActionVars = {
  path: string;
  body?: unknown;
  success?: string;
  /** Shown while the request runs (default "Saving…"). */
  pending?: string;
  /** Small background actions (e.g. mark one message read): no "Saving…" or success alert, errors only. */
  quiet?: boolean;
};

/**
 * Every RE command goes through here: POST with an idempotency key, toast
 * the outcome, then invalidate everything (one command can move several
 * lists server-side — record-outcome style fan-out). SSE will also push
 * the same invalidation to every other open client.
 */
export function useRmsAction() {
  const qc = useQueryClient();
  return useMutation({
    mutationFn: ({ path, body }: ActionVars) => {
      // Nothing is saved while BUSY data is being replaced (see SyncFreeze).
      if (isSyncFrozen(qc.getQueryData<SyncStatus>(["sync-status"]))) {
        return Promise.reject(new ApiError("TP-RMS is syncing with BUSY. Please wait until it finishes.", 423));
      }
      return rmsPost(path, body ?? {});
    },
    // Every command shows "Saving…" while it runs, then turns into a
    // green success or red error alert in the same place.
    onMutate: (v) => ({ toastId: v.quiet ? undefined : toast.loading(v.pending ?? "Saving…") }),
    onSuccess: (_d, v, ctx) => {
      if (ctx?.toastId !== undefined) {
        if (v.success) toast.success(v.success, { id: ctx.toastId });
        else toast.dismiss(ctx.toastId);
      }
      qc.invalidateQueries();
    },
    onError: (e, _v, ctx) => {
      toast.error(friendlyError(e), { id: ctx?.toastId, duration: 10_000, description: "Nothing was changed. Please try again." });
    },
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
