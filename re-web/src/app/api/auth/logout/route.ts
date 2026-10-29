import { NextResponse, type NextRequest } from "next/server";
import { REFRESH_COOKIE, clearSessionCookies, rmsApiUrl } from "@/lib/server/session";

export async function POST(request: NextRequest) {
  const refreshToken = request.cookies.get(REFRESH_COOKIE)?.value;
  if (refreshToken) {
    // Real server-side revoke, not just dropping cookies.
    await fetch(rmsApiUrl("/api/auth/logout"), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ refreshToken }),
    }).catch(() => {});
  }
  const res = NextResponse.json({ ok: true });
  clearSessionCookies(res);
  return res;
}
