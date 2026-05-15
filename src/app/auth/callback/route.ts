import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

// Handles every Supabase email-link redirect (signup verification AND
// password recovery). The link's `next` query param decides where we land
// after a successful exchange — recovery flows continue to /auth/reset.
export async function GET(request: Request) {
  const { searchParams, origin } = new URL(request.url);
  const code = searchParams.get("code");
  const next = searchParams.get("next") ?? "/play";
  const errorCode = searchParams.get("error_code");
  const isRecovery = next === "/auth/reset";

  // Supabase appends ?error=...&error_code=... when the link itself is bad
  // (e.g. otp_expired). Translate to our auth-page banner keys.
  if (errorCode) {
    const expired = errorCode === "otp_expired";
    const errKey = isRecovery
      ? expired
        ? "reset_link_expired"
        : "reset_failed"
      : expired
        ? "link_expired"
        : "verification_failed";
    return NextResponse.redirect(`${origin}/auth?error=${errKey}`);
  }

  if (code) {
    const supabase = await createClient();
    const { error } = await supabase.auth.exchangeCodeForSession(code);
    if (!error) {
      const safeNext =
        next.startsWith("/") && !next.startsWith("//") ? next : "/play";
      return NextResponse.redirect(`${origin}${safeNext}`);
    }
  }

  const fallback = isRecovery ? "reset_failed" : "verification_failed";
  return NextResponse.redirect(`${origin}/auth?error=${fallback}`);
}
