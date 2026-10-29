import { NextResponse, type NextRequest } from "next/server";
import { ACCESS_COOKIE, rmsApiUrl, setSessionCookies, upstreamMessage, type TokenPair } from "@/lib/server/session";

/** Change password returns a fresh token pair (every other session is revoked), so it can't go through the generic proxy. */
export async function POST(request: NextRequest) {
  const accessToken = request.cookies.get(ACCESS_COOKIE)?.value;
  const { newPassword } = (await request.json().catch(() => ({}))) as { newPassword?: string };
  const upstream = await fetch(rmsApiUrl("/api/auth/change-password"), {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${accessToken ?? ""}` },
    body: JSON.stringify({ newPassword }),
    cache: "no-store",
  }).catch(() => null);
  if (!upstream) return NextResponse.json({ message: "Could not reach the TP-RMS server." }, { status: 502 });
  if (!upstream.ok) {
    const message = await upstreamMessage(upstream, "Could not change password");
    return NextResponse.json({ message }, { status: upstream.status });
  }
  const pair = (await upstream.json()) as TokenPair;
  const res = NextResponse.json({ user: pair.user });
  setSessionCookies(res, pair);
  return res;
}
