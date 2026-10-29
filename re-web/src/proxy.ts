import { NextResponse, type NextRequest } from "next/server";

/**
 * Optimistic gate only (the real check is the TP-RMS API rejecting a bad
 * token): no refresh cookie → send to /login; already signed in → skip it.
 */
export function proxy(request: NextRequest) {
  const signedIn = Boolean(request.cookies.get("rms_rt")?.value);
  const { pathname, search } = request.nextUrl;
  const isLogin = pathname === "/login";

  if (!signedIn && !isLogin) {
    const url = new URL("/login", request.url);
    if (pathname !== "/") url.searchParams.set("next", pathname + search);
    return NextResponse.redirect(url);
  }
  if (signedIn && isLogin) {
    return NextResponse.redirect(new URL("/dashboard", request.url));
  }
  return NextResponse.next();
}

export const config = {
  matcher: ["/((?!api|_next/static|_next/image|favicon.ico|logo.png|.*\\.(?:png|jpg|svg|ico)$).*)"],
};
