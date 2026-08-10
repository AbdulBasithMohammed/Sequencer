"use server";

import { createClient } from "@/lib/supabase/server";

// Thin wrapper over the RPC. Every limit (cooldown, hourly/daily caps,
// duplicate and global circuit breaker) is enforced in submit_feedback
// itself, so this deliberately adds no checks of its own — the anon key
// is public and anyone can call the RPC directly, which makes a check
// here decorative.
export async function submitFeedback(body: string, page: string) {
  const supabase = await createClient();
  const { error } = await supabase.rpc("submit_feedback", {
    p_body: body,
    p_page: page,
  });
  // The RPC raises human-readable messages on purpose, so they can go
  // straight to the user.
  return { error: error?.message ?? null };
}
