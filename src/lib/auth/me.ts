import { cache } from "react";
import { createClient } from "@/lib/supabase/server";

// Request-scoped dedup: any number of server components in the same
// render can call these and only one network roundtrip runs per
// request. Without this, AppShell + each page would each fetch the
// user + profile, doubling latency on every tab switch.

export const getCurrentUser = cache(async () => {
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  return user;
});

export const getCurrentProfile = cache(async () => {
  const user = await getCurrentUser();
  if (!user) return null;
  const supabase = await createClient();
  const { data } = await supabase
    .from("profiles")
    .select("display_name, created_at")
    .eq("id", user.id)
    .maybeSingle();
  return data;
});
