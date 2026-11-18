"use server";

import { createClient } from "@/lib/supabase/server";

// Thin wrappers over the RPCs. Every limit (cooldown, hourly/daily caps,
// duplicate and global circuit breaker, parent ownership) is enforced in
// the SQL itself, so these deliberately add no checks of their own — the
// anon key is public and anyone can call the RPCs directly, which makes a
// check here decorative.

export type MyFeedback = {
  id: string;
  body: string;
  created_at: string;
  parent_id: string | null;
  reply_body: string | null;
  replied_at: string | null;
  reply_seen_at: string | null;
};

export async function submitFeedback(
  body: string,
  page: string,
  parentId: string | null = null,
) {
  const supabase = await createClient();
  const { error } = await supabase.rpc("submit_feedback", {
    p_body: body,
    p_page: page,
    ...(parentId ? { p_parent_id: parentId } : {}),
  });
  // The RPC raises human-readable messages on purpose, so they can go
  // straight to the user.
  return { error: error?.message ?? null };
}

export async function getMyFeedback() {
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("my_feedback");
  return {
    items: (data ?? []) as MyFeedback[],
    error: error?.message ?? null,
  };
}

export async function markFeedbackRepliesSeen() {
  const supabase = await createClient();
  const { error } = await supabase.rpc("mark_feedback_replies_seen");
  return { error: error?.message ?? null };
}
