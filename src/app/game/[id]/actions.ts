"use server";

import { revalidatePath } from "next/cache";

// Exposed so the client-side realtime handler can flush the page-level
// data cache before router.refresh() — otherwise router.refresh() can
// re-render against stale Supabase data.
export async function revalidateGameAction() {
  revalidatePath("/game/[id]", "page");
}
