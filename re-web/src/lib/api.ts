"use client";

/**
 * Browser-side client for the BFF proxy (/api/rms/*). Mirrors the Flutter
 * ApiClient: on a 401 it refreshes the session ONCE (shared by every
 * request waiting on it — the refresh token is single-use) and retries;
 * if the refresh fails the user is sent back to /login.
 */
export class ApiError extends Error {
  constructor(
    message: string,
    public status: number,
  ) {
    super(message);
  }
}

let refreshing: Promise<boolean> | null = null;

const REFRESHED_AT = "rms_refreshed_at";
const readRefreshedAt = () => {
  try {
    return Number(localStorage.getItem(REFRESHED_AT)) || 0;
  } catch {
    return 0;
  }
};

/**
 * Renews the session once for every request that hit a 401. The refresh
 * token is single-use, so two tabs renewing together would make the
 * second one fail and sign every tab out. A browser-wide lock lets one
 * tab renew; a tab that waited on it sees the newer renewal time and
 * simply reuses the fresh cookies.
 */
export function refreshSession(): Promise<boolean> {
  if (!refreshing) {
    const failedAt = Date.now();
    const renew = async () => {
      if (readRefreshedAt() >= failedAt) return true; // another tab already did it
      const ok = await fetch("/api/auth/refresh", { method: "POST" })
        .then((r) => r.ok)
        .catch(() => false);
      if (ok) {
        try {
          localStorage.setItem(REFRESHED_AT, String(Date.now()));
        } catch {}
      }
      return ok;
    };
    const locks = typeof navigator !== "undefined" ? navigator.locks : undefined;
    const run = (locks ? locks.request("rms-refresh", renew) : renew()) as Promise<boolean>;
    refreshing = run
      .catch(() => false)
      .finally(() => {
        // Let a later expiry trigger a fresh refresh.
        setTimeout(() => (refreshing = null), 0);
      });
  }
  return refreshing!;
}

export function redirectToLogin(reason?: string) {
  if (typeof window === "undefined") return;
  const next = encodeURIComponent(window.location.pathname + window.location.search);
  const r = reason ? `&reason=${encodeURIComponent(reason)}` : "";
  // Full reload on purpose — the session is gone, so drop every cached query too.
  // eslint-disable-next-line @next/next/no-location-assign-relative-destination
  window.location.href = `/login?next=${next}${r}`;
}

async function readError(res: Response) {
  try {
    const body = await res.json();
    return (body?.error?.message ?? body?.message) as string | undefined;
  } catch {
    return undefined;
  }
}

/**
 * Plain-language message for any failed request — what the person sees in
 * alerts. Server messages for 400/409/422 are already written for people
 * (e.g. "Reason is required"), so those are kept.
 */
export function friendlyStatusMessage(status: number, serverMessage?: string) {
  if (status === 0) return "Cannot reach the server. Check your internet connection and try again.";
  if (status === 403) return "You are not allowed to do this.";
  if (status === 404) return "This item no longer exists. Please refresh the page.";
  if (status === 408 || status === 504) return "The server took too long to answer. Please try again.";
  if (status === 502) return "Cannot reach the TP-RMS server right now. Please try again in a moment.";
  if (status === 429) return "Too many tries. Please wait a minute and try again.";
  if (status === 503) return serverMessage || "TP-RMS is under maintenance. Please try again later.";
  if (status >= 500) return "Something went wrong on the server. Please try again in a moment.";
  return serverMessage || "That did not work. Please try again.";
}

export function friendlyError(e: unknown) {
  if (e instanceof ApiError) return e.message;
  return friendlyStatusMessage(0);
}

export async function rmsFetch<T = unknown>(path: string, init: RequestInit = {}, retried = false): Promise<T> {
  let res: Response;
  try {
    res = await fetch(`/api/rms${path}`, { ...init, cache: "no-store" });
  } catch {
    throw new ApiError(friendlyStatusMessage(0), 0);
  }
  if (res.status === 401 && !retried) {
    if (await refreshSession()) return rmsFetch<T>(path, init, true);
    redirectToLogin("expired");
    throw new ApiError("Session expired", 401);
  }
  if (!res.ok) throw new ApiError(friendlyStatusMessage(res.status, await readError(res)), res.status);
  if (res.status === 204) return undefined as T;
  return (await res.json()) as T;
}

export const rmsGet = <T,>(path: string) => rmsFetch<T>(path);

/** Every write carries an idempotency key — a double-click or retry produces one result (spec §64). */
export function rmsPost<T = unknown>(path: string, body: unknown = {}) {
  return rmsFetch<T>(path, {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-Idempotency-Key": crypto.randomUUID() },
    body: JSON.stringify(body),
  });
}

/** Uploads evidence to POST /api/attachments; returns the server filename to send as `attachmentPath`. */
export async function rmsUpload(file: File, retried = false): Promise<string> {
  const form = new FormData();
  form.append("file", file);
  let res: Response;
  try {
    res = await fetch("/api/rms/attachments", { method: "POST", body: form });
  } catch {
    throw new ApiError(friendlyStatusMessage(0), 0);
  }
  if (res.status === 401 && !retried && (await refreshSession())) return rmsUpload(file, true);
  if (res.status === 413) throw new ApiError("This file is too big. Please choose a smaller file (under 4 MB).", 413);
  if (!res.ok) throw new ApiError(friendlyStatusMessage(res.status, await readError(res)), res.status);
  return ((await res.json()) as { path: string }).path;
}

/**
 * Our own password change bumps the server's session version and pushes a
 * 'session-revoked' echo to this browser mid-request. The realtime bridge
 * ignores revocations until this deadline so we don't sign ourselves out.
 */
let ownSessionChangeUntil = 0;
export const expectOwnSessionChange = (ms = 15_000) => {
  ownSessionChangeUntil = Date.now() + ms;
};
export const isOwnSessionChange = () => Date.now() < ownSessionChangeUntil;
