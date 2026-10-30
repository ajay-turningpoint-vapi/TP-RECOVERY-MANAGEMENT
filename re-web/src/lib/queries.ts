"use client";

import { useMemo } from "react";
import { useQueries, useQuery, useQueryClient } from "@tanstack/react-query";
import { rmsGet } from "./api";
import {
  parseCustomer,
  parseDispute,
  parseEscalation,
  parseNotification,
  parsePaymentClaim,
  parsePtp,
  parseSalesman,
  parseTask,
  type DashboardReport,
  type SyncStatus,
  type TrendPoint,
} from "./models";
import { buildView, EMPTY_DATA, isSystemClosed, type RmsData } from "./selectors";
import { useBranch, useSessionUser } from "@/components/app/providers";

type Json = Record<string, unknown>;

/**
 * Query keys match the resource names the server's SSE 'invalidate'
 * events carry (realtime/eventBus.js), so the realtime bridge can
 * invalidate them 1:1 — same mapping as AppStore._applyInvalidations.
 */
export const RESOURCES = {
  customers: { key: ["customers"], path: "/customers" },
  tasks: { key: ["tasks"], path: "/tasks" },
  ptps: { key: ["ptps"], path: "/ptps" },
  disputes: { key: ["disputes"], path: "/disputes" },
  paymentClaims: { key: ["paymentClaims"], path: "/payment-claims" },
  escalations: { key: ["escalations"], path: "/escalations" },
  salesmen: { key: ["salesmen"], path: "/salesmen" },
  notifications: { key: ["notifications"], path: "/notifications" },
  dashboard: { key: ["reports", "dashboard"], path: "/reports/dashboard" },
} as const;

const ORDER = Object.keys(RESOURCES) as (keyof typeof RESOURCES)[];

export function useRmsData() {
  const results = useQueries({
    queries: ORDER.map((name) => ({
      queryKey: RESOURCES[name].key,
      queryFn: () => rmsGet<unknown>(RESOURCES[name].path),
    })),
  });

  const [r0, r1, r2, r3, r4, r5, r6, r7, r8] = results.map((r) => r.data);
  const isLoading = results.some((r) => r.isPending);
  const error = results.find((r) => r.error)?.error ?? null;
  const isFetching = results.some((r) => r.isFetching);
  // Nothing usable arrived (first load failed) — lists must say "could not
  // load", never "nothing here".
  const loadFailed = !!error && results.some((r) => r.data === undefined);

  const data = useMemo<RmsData>(() => {
    const [customers, tasks, ptps, disputes, claims, escalations, salesmen, notifications, dashboard] = [r0, r1, r2, r3, r4, r5, r6, r7, r8] as [
      Json[] | undefined,
      Json[] | undefined,
      Json[] | undefined,
      Json[] | undefined,
      Json[] | undefined,
      Json[] | undefined,
      Json[] | undefined,
      Json[] | undefined,
      DashboardReport | undefined,
    ];
    const parsedCustomers = (customers ?? []).map(parseCustomer);
    const names = new Map(parsedCustomers.map((c) => [c.id, c.name]));
    // GET /api/customers leaves out customers BUSY no longer has
    // (busy_still_active = 0). Anything still attached to one of them — e.g.
    // a PTP the 12:10 job marked broken after the customer was removed —
    // has nobody to act on it — removed from BUSY means removed from RMS, so
    // all of it is hidden everywhere (the server filters the same way).
    // Only applied once the customer list has loaded, so nothing vanishes mid-load.
    const known = parsedCustomers.length > 0 ? new Set(parsedCustomers.map((c) => c.id)) : null;
    const active = <T extends { customerId: string }>(x: T) => !known || !x.customerId || known.has(x.customerId);
    return {
      ...EMPTY_DATA,
      customers: parsedCustomers,
      // Tasks the server closed by itself (not a person) are hidden everywhere.
      tasks: (tasks ?? [])
        .map((t) => parseTask(t, names.get(t.customerId as string)))
        .filter((t) => !(t.status === "completed" && isSystemClosed(t.outcome)))
        .filter(active),
      ptps: (ptps ?? []).map(parsePtp).filter(active),
      // Same for disputes and payment claims the server auto-closed
      // (customer no longer in BUSY) — nobody has anything to do on them.
      disputes: (disputes ?? []).map(parseDispute).filter((d) => d.status !== "Auto-Closed").filter(active),
      paymentClaims: (claims ?? []).map(parsePaymentClaim).filter((c) => c.status !== "Auto-Closed").filter(active),
      escalations: (escalations ?? []).map(parseEscalation).filter(active),
      salesmen: (salesmen ?? []).map(parseSalesman),
      // GET /api/notifications returns { items, unreadCount } (notificationService.listForUser).
      notifications: (((notifications as unknown as { items?: Json[] } | undefined)?.items) ?? []).map(parseNotification),
      dashboard: dashboard ?? {},
    };
  }, [r0, r1, r2, r3, r4, r5, r6, r7, r8]);

  return { data, isLoading, isFetching, error, loadFailed };
}

/** The branch-scoped, derived RE view of everything — the web equivalent of AppStore. */
export function useRms() {
  const { data, isLoading, isFetching, error, loadFailed } = useRmsData();
  const { branch } = useBranch();
  const user = useSessionUser();
  const view = useMemo(() => buildView(data, branch, user.id), [data, branch, user.id]);
  return { ...view, isLoading, isFetching, error, loadFailed };
}

export function useTrends() {
  return useQuery({
    queryKey: ["reports", "trends"],
    queryFn: () => rmsGet<TrendPoint[]>("/reports/trends"),
  });
}

/**
 * Same backstop as the app (AppStore._maxSyncCurtain): a crashed sync can
 * leave the server's lock set, so never freeze for longer than a real sync
 * could take.
 */
export const MAX_SYNC_FREEZE_MS = 20 * 60_000;

/** True while the BUSY sync runs and the web must stay locked. */
export function isSyncFrozen(s: SyncStatus | undefined, now = Date.now()) {
  if (!s?.syncing) return false;
  const since = s.since ? Date.parse(s.since) : NaN;
  return Number.isNaN(since) || now - since < MAX_SYNC_FREEZE_MS;
}

export function useSyncStatus() {
  return useQuery({
    queryKey: ["sync-status"],
    queryFn: () => rmsGet<SyncStatus>("/sync-status"),
    // While syncing, check often so the lock lifts even if the live
    // "finished" event is missed.
    refetchInterval: (q) => (q.state.data?.syncing ? 15_000 : 5 * 60_000),
  });
}

export function useRefreshAll() {
  const qc = useQueryClient();
  return () => qc.invalidateQueries();
}
