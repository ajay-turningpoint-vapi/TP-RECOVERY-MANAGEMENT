"use client";

import { createContext, useCallback, useContext, useEffect, useState, type ReactNode } from "react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { ApiError } from "@/lib/api";
import { ALL_BRANCHES } from "@/lib/selectors";
import type { PublicUser } from "@/lib/server/session-types";
import { RealtimeBridge } from "./realtime";

const UserContext = createContext<PublicUser | null>(null);
const BranchContext = createContext<{ branch: string; setBranch: (b: string) => void }>({
  branch: ALL_BRANCHES,
  setBranch: () => {},
});

const BRANCH_KEY = "re_branch_filter";

export function useSessionUser() {
  const u = useContext(UserContext);
  if (!u) throw new Error("useSessionUser outside AppProviders");
  return u;
}

export function useBranch() {
  return useContext(BranchContext);
}

export function AppProviders({ user, children }: { user: PublicUser; children: ReactNode }) {
  const [client] = useState(
    () =>
      new QueryClient({
        defaultOptions: {
          queries: {
            // Live updates come over SSE; this is only the safety net.
            staleTime: 60_000,
            refetchOnWindowFocus: true,
            retry: (count, err) => !(err instanceof ApiError && err.status < 500) && count < 2,
          },
        },
      }),
  );
  const [branch, setBranchState] = useState(ALL_BRANCHES);

  useEffect(() => {
    try {
      const saved = localStorage.getItem(BRANCH_KEY);
      // eslint-disable-next-line react-hooks/set-state-in-effect
      if (saved) setBranchState(saved);
    } catch {
      /* preference only */
    }
  }, []);

  const setBranch = useCallback((b: string) => {
    setBranchState(b);
    try {
      localStorage.setItem(BRANCH_KEY, b);
    } catch {
      /* preference only */
    }
  }, []);

  return (
    <QueryClientProvider client={client}>
      <UserContext.Provider value={user}>
        <BranchContext.Provider value={{ branch, setBranch }}>
          <RealtimeBridge />
          {children}
        </BranchContext.Provider>
      </UserContext.Provider>
    </QueryClientProvider>
  );
}
