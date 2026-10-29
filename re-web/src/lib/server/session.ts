import "server-only";
import { cookies } from "next/headers";
import type { NextResponse } from "next/server";

/**
 * BFF session — the RE's tokens live only in httpOnly cookies on this
 * origin; the browser never sees them. `rms_user` is the one readable
 * cookie (public profile only — name/role/branch) so the shell can render
 * without a round trip.
 */
export const ACCESS_COOKIE = "rms_at";
export const REFRESH_COOKIE = "rms_rt";
export const USER_COOKIE = "rms_user";

import type { PublicUser } from "./session-types";
export type { PublicUser };

export type TokenPair = { accessToken: string; refreshToken: string; user: PublicUser };

const secure = process.env.NODE_ENV === "production";
const REFRESH_MAX_AGE = 30 * 24 * 60 * 60; // matches the server's 30-day refresh TTL

export function rmsApiUrl(path: string) {
  const base = process.env.RMS_API_URL;
  if (!base) throw new Error("RMS_API_URL is not configured");
  return `${base.replace(/\/$/, "")}${path}`;
}

export function setSessionCookies(res: NextResponse, pair: TokenPair) {
  const base = { httpOnly: true, secure, sameSite: "lax" as const, path: "/" };
  res.cookies.set(ACCESS_COOKIE, pair.accessToken, { ...base, maxAge: REFRESH_MAX_AGE });
  res.cookies.set(REFRESH_COOKIE, pair.refreshToken, { ...base, maxAge: REFRESH_MAX_AGE });
  res.cookies.set(USER_COOKIE, JSON.stringify(pair.user), {
    httpOnly: false,
    secure,
    sameSite: "lax",
    path: "/",
    maxAge: REFRESH_MAX_AGE,
  });
}

export function clearSessionCookies(res: NextResponse) {
  for (const name of [ACCESS_COOKIE, REFRESH_COOKIE, USER_COOKIE]) {
    res.cookies.set(name, "", { path: "/", maxAge: 0 });
  }
}

export async function readSessionUser(): Promise<PublicUser | null> {
  const jar = await cookies();
  const raw = jar.get(USER_COOKIE)?.value;
  if (!raw || !jar.get(REFRESH_COOKIE)?.value) return null;
  try {
    return JSON.parse(raw) as PublicUser;
  } catch {
    return null;
  }
}

/** Upstream error body is `{ error: { message } }` or `{ message }` — normalise to one string. */
export async function upstreamMessage(res: Response, fallback: string) {
  try {
    const body = await res.json();
    return body?.error?.message ?? body?.message ?? fallback;
  } catch {
    return fallback;
  }
}
