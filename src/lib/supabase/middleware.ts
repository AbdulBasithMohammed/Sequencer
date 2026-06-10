import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";
import { decodeSessionClaims } from "@/lib/auth/claims";

const PROTECTED_PREFIXES = ["/play", "/lobby", "/game", "/me", "/friends"];

function isProtected(pathname: string) {
  return PROTECTED_PREFIXES.some((p) => pathname.startsWith(p));
}

function redirectToSignIn(request: NextRequest) {
  const redirectUrl = request.nextUrl.clone();
  redirectUrl.pathname = "/auth";
  redirectUrl.searchParams.set("mode", "signin");
  redirectUrl.searchParams.set("next", request.nextUrl.pathname);
  return NextResponse.redirect(redirectUrl);
}

export async function updateSession(request: NextRequest) {
  let response = NextResponse.next({ request });

  // No auth cookie → nothing to refresh, nobody to gate. Skip the Supabase
  // client entirely so anonymous traffic (landing page, /rules, /auth)
  // renders with zero auth work.
  const hasAuthCookie = request.cookies
    .getAll()
    .some((c) => c.name.startsWith("sb-") && c.name.includes("-auth-token"));
  if (!hasAuthCookie) {
    return isProtected(request.nextUrl.pathname)
      ? redirectToSignIn(request)
      : response;
  }

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) =>
            request.cookies.set(name, value),
          );
          response = NextResponse.next({ request });
          cookiesToSet.forEach(({ name, value, options }) =>
            response.cookies.set(name, value, options),
          );
        },
      },
    },
  );

  // Reads the session from the cookie and only hits the network when the
  // access token has expired and needs a refresh — unlike getUser(), which
  // is a Supabase Auth round trip on every request. Route gating below uses
  // locally decoded claims; cryptographic verification stays at the data
  // layer, where Supabase checks the JWT on every query/RPC (RLS).
  const {
    data: { session },
  } = await supabase.auth.getSession();
  const claims = session ? decodeSessionClaims(session.access_token) : null;

  if (isProtected(request.nextUrl.pathname)) {
    // Guests (anonymous sessions) get a pass — they don't have an email to
    // verify but they hold a real session.
    const allowed = claims && (claims.isAnonymous || claims.emailVerified);
    if (!allowed) return redirectToSignIn(request);
  }

  return response;
}
