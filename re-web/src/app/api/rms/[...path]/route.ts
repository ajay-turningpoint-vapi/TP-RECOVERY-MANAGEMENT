import { type NextRequest } from "next/server";
import { ACCESS_COOKIE, rmsApiUrl } from "@/lib/server/session";

/**
 * Generic pass-through to the TP-RMS Express API: /api/rms/<path> →
 * RMS_API_URL/api/<path>, with the httpOnly access token attached as a
 * Bearer header. Also streams GET /api/rms/events (SSE) unbuffered.
 * A 401 is passed straight back — the browser client refreshes once and
 * retries (lib/api.ts).
 */
export const maxDuration = 300;

// Auth endpoints that mint tokens have dedicated routes (/api/auth/*).
const BLOCKED = new Set(["auth/login", "auth/refresh", "auth/change-password"]);

async function forward(request: NextRequest, ctx: RouteContext<"/api/rms/[...path]">) {
  const { path } = await ctx.params;
  const joined = path.map(encodeURIComponent).join("/");
  if (BLOCKED.has(joined)) return Response.json({ message: "Not found" }, { status: 404 });

  // ?inline=1 on an attachment = show it in the page (PDF viewer) instead
  // of the server's default "download" for PDFs. Not forwarded upstream.
  const params = new URLSearchParams(request.nextUrl.search);
  const inline = path[0] === "attachments" && params.get("inline") === "1";
  params.delete("inline");
  const qs = params.toString();
  const url = rmsApiUrl(`/api/${joined}${qs ? `?${qs}` : ""}`);
  const headers = new Headers();
  const token = request.cookies.get(ACCESS_COOKIE)?.value;
  if (token) headers.set("Authorization", `Bearer ${token}`);
  for (const h of ["content-type", "accept", "x-idempotency-key"]) {
    const v = request.headers.get(h);
    if (v) headers.set(h, v);
  }

  const hasBody = request.method !== "GET" && request.method !== "HEAD";
  let upstream: Response;
  try {
    upstream = await fetch(url, {
      method: request.method,
      headers,
      body: hasBody ? await request.arrayBuffer() : undefined,
      cache: "no-store",
      signal: request.signal,
      redirect: "manual",
    });
  } catch {
    return Response.json({ message: "Could not reach the TP-RMS server." }, { status: 502 });
  }

  const out = new Headers();
  for (const h of ["content-type", "content-disposition", "cache-control"]) {
    const v = upstream.headers.get(h);
    if (v) out.set(h, v);
  }
  if (inline && upstream.ok) out.set("content-disposition", "inline");
  if (path[0] === "attachments" && upstream.ok) out.set("cache-control", "private, max-age=3600");
  if ((upstream.headers.get("content-type") ?? "").includes("text/event-stream")) {
    out.set("Cache-Control", "no-cache, no-transform");
    out.set("X-Accel-Buffering", "no");
  }
  return new Response(upstream.body, { status: upstream.status, headers: out });
}

export const GET = forward;
export const POST = forward;
export const PUT = forward;
export const PATCH = forward;
export const DELETE = forward;
