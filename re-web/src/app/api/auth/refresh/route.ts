import { NextResponse, type NextRequest } from "next/server";
import {
  REFRESH_COOKIE,
  clearSessionCookies,
  rmsApiUrl,
  setSessionCookies,
  type TokenPair,
} from "@/lib/server/session";

/**
 * Rotates the session. The refresh token is single-use, so the browser
 * client funnels every concurrent 401 through ONE call to this route
 * (see lib/api.ts) — mirrors ApiClient._authedSend in the Flutter app.
 */
export async function POST(request: NextRequest) {
  const refreshToken = request.cookies.get(REFRESH_COOKIE)?.value;
  if (!refreshToken) {
    const res = NextResponse.json({ message: "Session expired" }, { status: 401 });
    clearSessionCookies(res);
    return res;
  }

  const upstream = await fetch(rmsApiUrl("/api/auth/refresh"), {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ refreshToken }),
    cache: "no-store",
  }).catch(() => null);

  if (!upstream) {
    return NextResponse.json({ message: "Could not reach the TP-RMS server." }, { status: 502 });
  }
  if (!upstream.ok) {
    const res = NextResponse.json({ message: "Session expired" }, { status: 401 });
    clearSessionCookies(res);
    return res;
  }

  const pair = (await upstream.json()) as TokenPair;
  const res = NextResponse.json({ user: pair.user });
  setSessionCookies(res, pair);
  return res;
}
