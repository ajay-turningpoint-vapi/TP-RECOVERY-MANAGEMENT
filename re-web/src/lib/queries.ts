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
import { buildView, EMPTY_DATA, type RmsData } from "./selectors";
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
    return {
      ...EMPTY_DATA,
      customers: parsedCustomers,
      tasks: (tasks ?? []).map((t) => parseTask(t, names.get(t.customerId as string))),
      ptps: (ptps ?? []).map(parsePtp),
      disputes: (disputes ?? []).map(parseDispute),
      paymentClaims: (claims ?? []).map(parsePaymentClaim),
      escalations: (escalations ?? []).map(parseEscalation),
      salesmen: (salesmen ?? []).map(parseSalesman),
      // GET /api/notifications returns { items, unreadCount } (notificationService.listForUser).
      notifications: (((notifications as unknown as { items?: Json[] } | undefined)?.items) ?? []).map(parseNotification),
      dashboard: dashboard ?? {},
    };
  }, [r0, r1, r2, r3, r4, r5, r6, r7, r8]);

  return { data, isLoading, isFetching, error };
}

/** The branch-scoped, derived RE view of everything — the web equivalent of AppStore. */
export function useRms() {
  const { data, isLoading, isFetching, error } = useRmsData();
  const { branch } = useBranch();
  const user = useSessionUser();
  const view = useMemo(() => buildView(data, branch, user.id), [data, branch, user.id]);
  return { ...view, isLoading, isFetching, error };
}

export function useTrends() {
  return useQuery({
    queryKey: ["reports", "trends"],
    queryFn: () => rmsGet<TrendPoint[]>("/reports/trends"),
  });
}

export function useSyncStatus() {
  return useQuery({
    queryKey: ["sync-status"],
    queryFn: () => rmsGet<SyncStatus>("/sync-status"),
    refetchInterval: 5 * 60_000,
  });
}

export function useRefreshAll() {
  const qc = useQueryClient();
  return () => qc.invalidateQueries();
}
