"use client";

import { useEffect } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { revalidateLobbyAction } from "./actions";

async function flushAndRefresh(router: ReturnType<typeof useRouter>) {
  await revalidateLobbyAction();
  router.refresh();
}

/**
 * Renderless. Subscribes to Realtime changes on this room and:
 *   - calls router.refresh() on most events
 *   - if the current user is the deleted row, redirects to /play?kicked=CODE
 *     (unless they set the "voluntary-leave" sessionStorage flag before
 *     submitting the Leave form, in which case the server action's redirect
 *     handles navigation)
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

  useEffect(() => {
    const supabase = createClient();
    const channel = supabase
      .channel(`lobby:${roomId}`)
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
            // Distinguish ban from kick by checking if our own ban row exists.
            // RLS lets us see only our own ban; query returns null on simple kick.
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
          table: "room_players",
          filter: `room_id=eq.${roomId}`,
        },
        () => flushAndRefresh(router),
      )
      .on(
        "postgres_changes",
        {
          event: "UPDATE",
          schema: "public",
          table: "room_players",
          filter: `room_id=eq.${roomId}`,
        },
        () => flushAndRefresh(router),
      )
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "rooms",
          filter: `id=eq.${roomId}`,
        },
        async (payload) => {
          const newStatus = (payload.new as { status?: string } | null)?.status;
          if (newStatus === "in_game") {
            const { data: game } = await supabase
              .from("games")
              .select("id")
              .eq("room_id", roomId)
              .maybeSingle();
            if (game?.id) {
              router.push(`/game/${game.id}`);
              return;
            }
          }
          flushAndRefresh(router);
        },
      )
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "room_bans",
          filter: `room_id=eq.${roomId}`,
        },
        () => flushAndRefresh(router),
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
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [roomId, roomCode, userId, router]);

  return null;
}
