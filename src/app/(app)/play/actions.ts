"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";

export type FormState = { error: string | null };

const VALID_COUNTS = [2, 3, 4, 6, 8, 10, 12];

export async function createRoomAction(
  _prev: FormState,
  formData: FormData,
): Promise<FormState> {
  const target = Number(formData.get("targetPlayers"));
  if (!VALID_COUNTS.includes(target)) {
    return { error: "Pick a valid player count." };
  }

  const supabase = await createClient();
  const { data: code, error } = await supabase.rpc("create_room", {
    p_target_players: target,
  });

  if (error) return { error: error.message };
  if (!code) return { error: "Failed to create room. Try again." };

  redirect(`/lobby/${code}`);
}

export async function joinRoomAction(
  _prev: FormState,
  formData: FormData,
): Promise<FormState> {
  const code = String(formData.get("code") ?? "")
    .trim()
    .toUpperCase();

  if (!code) return { error: "Enter a code." };
  if (!/^[A-Z0-9]{6}$/.test(code)) {
    return { error: "Codes are 6 letters/numbers." };
  }

  const supabase = await createClient();
  const { error } = await supabase.rpc("join_room", { p_code: code });

  if (error) {
    const msg = error.message;
    if (msg.includes("Room not found"))
      return { error: "No room with that code." };
    if (msg.includes("Room is full"))
      return { error: "That room is full." };
    if (msg.includes("not accepting"))
      return { error: "That room already started." };
    return { error: msg };
  }

  redirect(`/lobby/${code}`);
}
