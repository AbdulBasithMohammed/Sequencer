"use server";

import { redirect } from "next/navigation";
import { revalidatePath } from "next/cache";
import { createClient } from "@/lib/supabase/server";

// Revalidate every /lobby/[code] page after a mutation so the action's
// response carries the fresh tree back to the clicking user. Realtime is
// still used to update OTHER clients.
function revalidateLobby() {
  revalidatePath("/lobby/[code]", "page");
}

// Exposed so the client-side realtime handler can flush the page-level
// data cache before router.refresh() — otherwise router.refresh() can
// re-render against stale Supabase data.
export async function revalidateLobbyAction() {
  revalidatePath("/lobby/[code]", "page");
}

export async function leaveRoomAction(formData: FormData) {
  const roomId = String(formData.get("roomId") ?? "");
  if (!roomId) redirect("/play");

  const supabase = await createClient();
  await supabase.rpc("leave_room", { p_room_id: roomId });
  redirect("/play");
}

export async function setTeamAction(formData: FormData) {
  const roomId = String(formData.get("roomId") ?? "");
  const userId = String(formData.get("userId") ?? "");
  const team = Number(formData.get("team"));
  if (!roomId || !userId || ![1, 2, 3].includes(team)) return;

  const supabase = await createClient();
  await supabase.rpc("set_team", {
    p_room_id: roomId,
    p_user_id: userId,
    p_team: team,
  });
  revalidateLobby();
}

export async function swapTeamsAction(formData: FormData) {
  const roomId = String(formData.get("roomId") ?? "");
  const userA = String(formData.get("userA") ?? "");
  const userB = String(formData.get("userB") ?? "");
  if (!roomId || !userA || !userB || userA === userB) return;

  const supabase = await createClient();
  await supabase.rpc("swap_teams", {
    p_room_id: roomId,
    p_user_a: userA,
    p_user_b: userB,
  });
  revalidateLobby();
}

export async function setReadyAction(formData: FormData) {
  const roomId = String(formData.get("roomId") ?? "");
  const ready = formData.get("ready") === "true";
  if (!roomId) return;

  const supabase = await createClient();
  await supabase.rpc("set_ready", { p_room_id: roomId, p_ready: ready });
  revalidateLobby();
}

export async function kickPlayerAction(formData: FormData) {
  const roomId = String(formData.get("roomId") ?? "");
  const userId = String(formData.get("userId") ?? "");
  if (!roomId || !userId) return;

  const supabase = await createClient();
  await supabase.rpc("kick_player", {
    p_room_id: roomId,
    p_user_id: userId,
  });
  revalidateLobby();
}

export async function banPlayerAction(formData: FormData) {
  const roomId = String(formData.get("roomId") ?? "");
  const userId = String(formData.get("userId") ?? "");
  if (!roomId || !userId) return;

  const supabase = await createClient();
  await supabase.rpc("ban_player", {
    p_room_id: roomId,
    p_user_id: userId,
  });
  revalidateLobby();
}

export async function unbanPlayerAction(formData: FormData) {
  const roomId = String(formData.get("roomId") ?? "");
  const userId = String(formData.get("userId") ?? "");
  if (!roomId || !userId) return;

  const supabase = await createClient();
  await supabase.rpc("unban_player", {
    p_room_id: roomId,
    p_user_id: userId,
  });
  revalidateLobby();
}

export async function transferHostAction(formData: FormData) {
  const roomId = String(formData.get("roomId") ?? "");
  const userId = String(formData.get("userId") ?? "");
  if (!roomId || !userId) return;

  const supabase = await createClient();
  await supabase.rpc("transfer_host", {
    p_room_id: roomId,
    p_new_host_id: userId,
  });
  revalidateLobby();
}

export async function setTeamLayoutAction(formData: FormData) {
  const roomId = String(formData.get("roomId") ?? "");
  const layout = String(formData.get("layout") ?? "");
  if (!roomId || !layout) return;

  const supabase = await createClient();
  await supabase.rpc("set_team_layout", {
    p_room_id: roomId,
    p_layout: layout,
  });
  revalidateLobby();
}

export async function startGameAction(formData: FormData) {
  const code = String(formData.get("code") ?? "");
  if (!code) return;

  const supabase = await createClient();
  const { data, error } = await supabase.rpc("start_game", { p_code: code });
  if (error || !data) {
    revalidateLobby();
    return;
  }
  redirect(`/game/${data}`);
}

export async function setTokenColorAction(formData: FormData) {
  const roomId = String(formData.get("roomId") ?? "");
  const color = String(formData.get("color") ?? "");
  if (!roomId || !color) return;

  const supabase = await createClient();
  await supabase.rpc("set_token_color", {
    p_room_id: roomId,
    p_color: color,
  });
  revalidateLobby();
}
