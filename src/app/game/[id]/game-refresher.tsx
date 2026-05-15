"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { revalidateGameAction } from "./actions";

async function flushAndRefresh(router: ReturnType<typeof useRouter>) {
  await revalidateGameAction();
  router.refresh();
}

// Renderless. Subscribes to UPDATEs on the games row so every connected
// client repaints when a move lands. Uses the same defence-in-depth pattern
// as LobbyRefresher: subscribe-and-reconcile + focus/visibility + 60s poll.
export function GameRefresher({ gameId }: { gameId: string }) {
  const router = useRouter();

  useEffect(() => {
    const supabase = createClient();
    const channel = supabase
      .channel(`game:${gameId}`)
      .on(
        "postgres_changes",
        {
          event: "UPDATE",
          schema: "public",
          table: "games",
          filter: `id=eq.${gameId}`,
        },
        () => flushAndRefresh(router),
      )
      .subscribe((status) => {
        if (status === "SUBSCRIBED") flushAndRefresh(router);
      });

    const onVisible = () => {
      if (document.visibilityState === "visible") flushAndRefresh(router);
    };
    document.addEventListener("visibilitychange", onVisible);
    window.addEventListener("focus", onVisible);

    const pollInterval = window.setInterval(() => {
      if (document.visibilityState === "visible") flushAndRefresh(router);
    }, 60000);

    return () => {
      supabase.removeChannel(channel);
      document.removeEventListener("visibilitychange", onVisible);
      window.removeEventListener("focus", onVisible);
      window.clearInterval(pollInterval);
    };
  }, [gameId, router]);

  return null;
}
