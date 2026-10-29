import { NextResponse, type NextRequest } from "next/server";
import { rmsApiUrl, setSessionCookies, upstreamMessage, type TokenPair } from "@/lib/server/session";

/** Roles allowed into the RE web dashboard — enforced here, server-side, not just by hiding UI (spec §4). */
const ALLOWED_ROLES = new Set(["RECOVERY_EXECUTIVE"]);

export async function POST(request: NextRequest) {
  const { username, password } = (await request.json().catch(() => ({}))) as {
    username?: string;
    password?: string;
  };
  if (!username || !password) {
    return NextResponse.json({ message: "Enter your username and password." }, { status: 400 });
  }

  let upstream: Response;
  try {
    upstream = await fetch(rmsApiUrl("/api/auth/login"), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      // 'web' = separate session channel (server migration 040), so this
      // login never signs the RE out of the mobile app.
      body: JSON.stringify({ username: username.trim(), password, client: "web" }),
      cache: "no-store",
    });
  } catch {
    return NextResponse.json({ message: "Could not reach the TP-RMS server. Try again shortly." }, { status: 502 });
  }

  if (!upstream.ok) {
    const message = await upstreamMessage(upstream, "Invalid username or password");
    return NextResponse.json({ message }, { status: upstream.status });
  }

  const pair = (await upstream.json()) as TokenPair;
  if (!ALLOWED_ROLES.has(pair.user.role)) {
    // Don't leave a live web session behind for a role that can't use it.
    await fetch(rmsApiUrl("/api/auth/logout"), {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ refreshToken: pair.refreshToken }),
    }).catch(() => {});
    return NextResponse.json(
      { message: "This dashboard is for Recovery Executives only. Please use the TP-RMS mobile app." },
      { status: 403 },
    );
  }

  const res = NextResponse.json({ user: pair.user });
  setSessionCookies(res, pair);
  return res;
}
