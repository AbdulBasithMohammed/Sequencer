"use client";

import { useEffect, useRef } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { revalidateLobbyAction } from "./actions";

async function flushAndRefresh(router: ReturnType<typeof useRouter>) {
  await revalidateLobbyAction();
  router.refresh();
}

/**
 * Renderless. Subscribes to the `lobby:<roomId>` Broadcast channel —
 * populated by Postgres triggers that fire on every change to rooms,
 * room_players, room_bans. Lighter and faster than postgres_changes (no
 * per-row RLS dispatch), fixes mobile delivery lag.
 *
 * Kept on postgres_changes (because they need event-specific payload
 * the broadcast doesn't carry):
 *   - DELETE on room_players: detect when *I* was the deleted row so we
 *     can show kicked/banned redirect with the right query param
 *   - INSERT on games: redirect to /game/<id> when the host starts
 *
 * Defence in depth:
 *   - subscribe-and-reconcile on SUBSCRIBED status
 *   - focus/visibility refresh
 *   - gap detection via lastSeenVersion
 * The 60s polling backstop is gone — gap detection fires exactly when a
 * message is missed.
 */
export function LobbyRefresher({
  roomId,
  roomCode,
  userId,
}: {
  roomId: string;
  roomCode: string;
  userId: string;
}) {
  const router = useRouter();
  const lastSeenVersionRef = useRef<number>(0);

  useEffect(() => {
    const supabase = createClient();
    const channel = supabase
      .channel(`lobby:${roomId}`)
      .on("broadcast", { event: "update" }, (msg) => {
        const v = (msg.payload as { version?: number } | undefined)?.version;
        if (typeof v === "number") {
          if (v <= lastSeenVersionRef.current) return;
          if (v > lastSeenVersionRef.current + 1) {
            console.warn(
              `[lobby-refresher] gap: lastSeen=${lastSeenVersionRef.current} -> ${v}`,
            );
          }
          lastSeenVersionRef.current = v;
        }
        flushAndRefresh(router);
      })
      .on(
        "postgres_changes",
        {
          event: "DELETE",
          schema: "public",
          table: "room_players",
          filter: `room_id=eq.${roomId}`,
        },
        async (payload) => {
          const deletedUserId = (payload.old as { user_id?: string } | null)
            ?.user_id;
          if (deletedUserId === userId) {
            const voluntary =
              typeof window !== "undefined" &&
              window.sessionStorage.getItem("voluntary-leave") === roomId;
            if (voluntary) {
              window.sessionStorage.removeItem("voluntary-leave");
              return; // server action handles the redirect
            }
            const { data: ban } = await supabase
              .from("room_bans")
              .select("user_id")
              .eq("room_id", roomId)
              .eq("user_id", userId)
              .maybeSingle();
            if (ban) {
              router.push(`/play?banned=${roomCode}`);
            } else {
              router.push(`/play?kicked=${roomCode}`);
            }
            return;
          }
          flushAndRefresh(router);
        },
      )
      .on(
        "postgres_changes",
        {
          event: "INSERT",
          schema: "public",
          table: "games",
          filter: `room_id=eq.${roomId}`,
        },
        (payload) => {
          const gameId = (payload.new as { id?: string } | null)?.id;
          if (gameId) router.push(`/game/${gameId}`);
        },
      )
      .subscribe((status) => {
        if (status === "SUBSCRIBED") {
          flushAndRefresh(router);
        }
      });

    const onVisible = () => {
      if (document.visibilityState === "visible") {
        flushAndRefresh(router);
      }
    };
    document.addEventListener("visibilitychange", onVisible);
    window.addEventListener("focus", onVisible);

    return () => {
      supabase.removeChannel(channel);
      document.removeEventListener("visibilitychange", onVisible);
      window.removeEventListener("focus", onVisible);
    };
  }, [roomId, roomCode, userId, router]);

  return null;
}
