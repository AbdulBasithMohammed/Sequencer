"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

// admin_reply_feedback re-checks is_admin and raises 42501 itself; this
// wrapper adds nothing but the revalidate. An empty body clears the reply.
export async function replyToFeedback(id: string, body: string) {
  const supabase = await createClient();
  const { error } = await supabase.rpc("admin_reply_feedback", {
    p_id: id,
    p_body: body,
  });
  if (!error) revalidatePath("/admin");
  return { error: error?.message ?? null };
}
