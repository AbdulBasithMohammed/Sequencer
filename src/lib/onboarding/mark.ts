"use client";

import { createClient } from "@/lib/supabase/client";

export type OnboardingStep =
  | "tour_done"
  | "tour_skipped"
  | "coach_done"
  | "nudge_seen";

type Flag = "tour" | "coach" | "nudge";

const FLAG_OF: Record<OnboardingStep, Flag> = {
  tour_done: "tour",
  tour_skipped: "tour",
  coach_done: "coach",
  nudge_seen: "nudge",
};

// Namespaced by user id on purpose. The flag is a per-account fact, and
// localStorage is per-browser — a shared machine would otherwise have the
// first account's tour suppress the second account's.
function key(userId: string, flag: Flag) {
  return `sq:onb:${userId}:${flag}`;
}

// The profile row is the source of truth; this is only a latency patch.
// The flags arrive with the server render, but a client-side replay or a
// second tab within the same session would otherwise re-show the tour
// before the next render carries the updated row.
export function seenLocally(userId: string, flag: Flag): boolean {
  try {
    return window.localStorage.getItem(key(userId, flag)) === "1";
  } catch {
    return false; // private mode, or site data blocked
  }
}

export async function markOnboarding(userId: string, step: OnboardingStep) {
  try {
    window.localStorage.setItem(key(userId, FLAG_OF[step]), "1");
  } catch {
    // Non-fatal: the RPC below is what actually persists this.
  }
  const supabase = createClient();
  // Fire and forget. Nothing on screen depends on the result, and the RPC
  // is set-once server-side, so a failed write costs the user one repeat
  // of the tour rather than anything broken.
  await supabase.rpc("mark_onboarding", { p_step: step });
}
