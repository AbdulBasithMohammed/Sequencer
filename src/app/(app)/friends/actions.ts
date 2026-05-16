"use server";

import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

async function callRpc(name: string, params: Record<string, unknown>) {
  const supabase = await createClient();
  const { error } = await supabase.rpc(name, params);
  if (error) return { error: error.message };
  revalidatePath("/friends");
  return { error: null as string | null };
}

export async function sendFriendRequest(targetUserId: string) {
  return callRpc("send_friend_request", { p_to_user: targetUserId });
}

export async function acceptFriendRequest(fromUserId: string) {
  return callRpc("accept_friend_request", { p_from_user: fromUserId });
}

export async function ignoreFriendRequest(fromUserId: string) {
  return callRpc("ignore_friend_request", { p_from_user: fromUserId });
}

export async function unignoreUser(userId: string) {
  return callRpc("unignore_user", { p_user_id: userId });
}

export async function cancelFriendRequest(toUserId: string) {
  return callRpc("cancel_friend_request", { p_to_user: toUserId });
}

export async function unfriend(userId: string) {
  return callRpc("unfriend", { p_user_id: userId });
}

export type SearchResult = {
  user_id: string;
  display_name: string;
  tag: string;
  relationship:
    | "friend"
    | "request_sent"
    | "request_received"
    | "ignored"
    | "none";
};

export async function searchUsers(query: string): Promise<SearchResult[]> {
  const trimmed = query.trim();
  if (!trimmed) return [];
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("search_users", {
    p_query: trimmed,
  });
  if (error || !data) return [];
  return data as SearchResult[];
}
