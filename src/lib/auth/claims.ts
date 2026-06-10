// Server-side identity without a per-request network round trip.
//
// The Next layer (middleware + server components) only needs identity for
// routing and rendering decisions — the real security boundary is Postgres:
// every query/RPC ships the access token to Supabase, which verifies its
// signature and enforces RLS. So instead of supabase.auth.getUser() (a
// network call to Supabase Auth on every request), we read the session from
// the cookie (refreshed by middleware only when expired) and decode the JWT
// payload locally. A forged cookie can render a shell of a page but can
// never read or mutate data, because Supabase rejects the bad token.

export type SessionClaims = {
  id: string;
  email: string | null;
  isAnonymous: boolean;
  emailVerified: boolean;
};

function base64UrlToUtf8(input: string): string {
  const base64 = input.replace(/-/g, "+").replace(/_/g, "/");
  const binary = atob(base64);
  const bytes = Uint8Array.from(binary, (c) => c.charCodeAt(0));
  return new TextDecoder().decode(bytes);
}

export function decodeSessionClaims(
  accessToken: string,
): SessionClaims | null {
  try {
    const payload = accessToken.split(".")[1];
    if (!payload) return null;
    const claims = JSON.parse(base64UrlToUtf8(payload)) as {
      sub?: string;
      email?: string;
      exp?: number;
      is_anonymous?: boolean;
      user_metadata?: { email_verified?: boolean };
    };
    if (!claims.sub) return null;
    if (typeof claims.exp === "number" && claims.exp * 1000 < Date.now()) {
      return null;
    }
    return {
      id: claims.sub,
      email: claims.email ?? null,
      isAnonymous: claims.is_anonymous === true,
      // A missing claim counts as verified: Supabase blocks sign-in for
      // unconfirmed emails, so holding a live session already implies a
      // confirmed address.
      emailVerified: claims.user_metadata?.email_verified !== false,
    };
  } catch {
    return null;
  }
}
