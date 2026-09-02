import { cache } from "react";
import { createClient } from "@/lib/supabase/server";
import { decodeSessionClaims } from "@/lib/auth/claims";

// Request-scoped dedup: any number of server components in the same
// render can call these and only one fetch runs per request.

// Identity from the session cookie — zero network. getSession() only goes
// to the network if the access token expired (middleware normally refreshes
// it first). See lib/auth/claims.ts for why this is safe: data access is
// independently verified by Supabase via RLS on every query.
export const getCurrentUser = cache(async () => {
  const supabase = await createClient();
  const {
    data: { session },
  } = await supabase.auth.getSession();
  if (!session) return null;
  return decodeSessionClaims(session.access_token);
});

export const getCurrentProfile = cache(async () => {
  const user = await getCurrentUser();
  if (!user) return null;
  const supabase = await createClient();
  const { data } = await supabase
    .from("profiles")
    .select(
      "display_name, tag, created_at, is_guest, country, tour_seen_at, coach_marks_done_at, feedback_nudge_seen_at",
    )
    .eq("id", user.id)
    .maybeSingle();
  return data;
});
