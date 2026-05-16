"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export type RoomInvite = {
  room_id: string;
  room_code: string;
  from_user_id: string;
  from_display_name: string;
  from_tag: string;
  target_players: number;
  created_at: string;
};

export type InvitableFriend = {
  user_id: string;
  display_name: string;
  tag: string;
  state: "in_room" | "invited" | "available";
};

export async function inviteToRoom(roomId: string, toUserId: string) {
  const supabase = await createClient();
  const { error } = await supabase.rpc("invite_to_room", {
    p_room_id: roomId,
    p_to_user: toUserId,
  });
  return { error: error?.message ?? null };
}

export async function acceptInvite(roomId: string, roomCode: string) {
  const supabase = await createClient();
  const { error } = await supabase.rpc("accept_room_invite", {
    p_room_id: roomId,
  });
  if (error) return { error: error.message };
  redirect(`/lobby/${roomCode}`);
}

export async function declineInvite(roomId: string) {
  const supabase = await createClient();
  const { error } = await supabase.rpc("decline_room_invite", {
    p_room_id: roomId,
  });
  return { error: error?.message ?? null };
}

export async function fetchMyInvites(): Promise<RoomInvite[]> {
  const supabase = await createClient();
  const { data } = await supabase.rpc("get_my_room_invites");
  return (data as RoomInvite[]) ?? [];
}

export async function fetchInvitableFriends(
  roomId: string,
): Promise<InvitableFriend[]> {
  const supabase = await createClient();
  const { data } = await supabase.rpc("get_invitable_friends", {
    p_room_id: roomId,
  });
  return (data as InvitableFriend[]) ?? [];
}
