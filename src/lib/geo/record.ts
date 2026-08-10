import { headers } from "next/headers";
import { createClient } from "@/lib/supabase/server";

// Vercel resolves geo at the edge and attaches it to every request, so
// the country is already sitting in a header — we only have to persist
// it. Locally the header is absent and this quietly does nothing.
//
// Called from AppShell only when profiles.country is still null, and the
// RPC itself is set-once, so this is a single write per user for the
// lifetime of the account rather than a write per page load. Both guards
// matter: the caller avoids the round trip, the RPC guarantees the
// semantics even if some other caller forgets.
//
// Only the two-letter country is stored. The IP is never persisted —
// coarse geo is low-risk analytics, an IP is personal data with real
// obligations and no use here.
export async function recordCountryOnce() {
  const cc = (await headers()).get("x-vercel-ip-country");
  if (!cc) return;
  const supabase = await createClient();
  await supabase.rpc("set_my_country", { p_country: cc });
}
