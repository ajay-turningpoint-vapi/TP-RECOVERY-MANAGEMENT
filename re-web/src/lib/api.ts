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

export function refreshSession(): Promise<boolean> {
  if (!refreshing) {
    refreshing = fetch("/api/auth/refresh", { method: "POST" })
      .then((r) => r.ok)
      .catch(() => false)
      .finally(() => {
        // Let a later expiry trigger a fresh refresh.
        setTimeout(() => (refreshing = null), 0);
      });
  }
  return refreshing;
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
    return (body?.error?.message ?? body?.message ?? `Request failed (${res.status})`) as string;
  } catch {
    return `Request failed (${res.status})`;
  }
}

export async function rmsFetch<T = unknown>(path: string, init: RequestInit = {}, retried = false): Promise<T> {
  const res = await fetch(`/api/rms${path}`, { ...init, cache: "no-store" });
  if (res.status === 401 && !retried) {
    if (await refreshSession()) return rmsFetch<T>(path, init, true);
    redirectToLogin("expired");
    throw new ApiError("Session expired", 401);
  }
  if (!res.ok) throw new ApiError(await readError(res), res.status);
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
  const res = await fetch("/api/rms/attachments", { method: "POST", body: form });
  if (res.status === 401 && !retried && (await refreshSession())) return rmsUpload(file, true);
  if (!res.ok) throw new ApiError(await readError(res), res.status);
  return ((await res.json()) as { path: string }).path;
}
