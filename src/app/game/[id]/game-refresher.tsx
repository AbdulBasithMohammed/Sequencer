"use client";

import { useEffect, useRef } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";

// Supabase server-side queries on this page don't flow through Next's
// fetch cache, so a pre-emptive revalidatePath() roundtrip is wasted —
// router.refresh() alone re-executes the server component freshly.
// Skipping the extra server action call shaves a full roundtrip per
// realtime update, which is a meaningful win for players far from the
// Supabase region.
function flushAndRefresh(router: ReturnType<typeof useRouter>) {
  router.refresh();
}

// Renderless. Subscribes to the `game:<id>` Broadcast channel — populated
// by a Postgres trigger that fires on every games-row UPDATE (see
// 20260516..._realtime_broadcast_from_db.sql). Lighter and faster than
// postgres_changes (no per-row RLS dispatch on every subscriber), which
// fixes the mobile-delivery lag.
//
// Defence in depth:
//   - subscribe-and-reconcile on SUBSCRIBED status (catches initial race)
//   - focus/visibility refresh (catches dropped events on backgrounded tabs)
//   - gap detection via lastSeenVersion (logs but always refetches anyway)
// The 60s polling backstop is gone — gap detection fires exactly when a
// message is missed.
export function GameRefresher({ gameId }: { gameId: string }) {
  const router = useRouter();
  const lastSeenVersionRef = useRef<number>(0);

  useEffect(() => {
    const supabase = createClient();
    const channel = supabase
      .channel(`game:${gameId}`)
      .on("broadcast", { event: "update" }, (msg) => {
        const v = (msg.payload as { version?: number } | undefined)?.version;
        if (typeof v === "number") {
          if (v <= lastSeenVersionRef.current) return; // dedupe
          if (v > lastSeenVersionRef.current + 1) {
            // Gap — we missed at least one event. We refetch the full state
            // anyway, so this is observability only.
            console.warn(
              `[game-refresher] gap: lastSeen=${lastSeenVersionRef.current} -> ${v}`,
            );
          }
          lastSeenVersionRef.current = v;
        }
        flushAndRefresh(router);
      })
      .subscribe((status) => {
        if (status === "SUBSCRIBED") flushAndRefresh(router);
      });

    const onVisible = () => {
      if (document.visibilityState === "visible") flushAndRefresh(router);
    };
    document.addEventListener("visibilitychange", onVisible);
    window.addEventListener("focus", onVisible);

    return () => {
      supabase.removeChannel(channel);
      document.removeEventListener("visibilitychange", onVisible);
      window.removeEventListener("focus", onVisible);
    };
  }, [gameId, router]);

  return null;
}
