"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import {
  ConnectionPill,
  useBrowserOnline,
} from "@/components/ui/connection-pill";
import {
  LobbyClient,
  type Ban,
  type Player,
  type Room,
} from "./lobby-client";

// Client-state owner for the lobby — same model as the game loop. The
// rooms broadcast trigger ships the full public lobby projection
// ({version, room, players}); we apply it straight to local state, so
// ready toggles, joins and seat changes land in one realtime hop instead
// of a server re-render. LobbyClient's useOptimistic layer sits on top of
// this state, keeping your own clicks instant.
//
// Events on lobby:<roomId>:
//   - "update":         fat payload {version, room, players}. Skinny
//                       {version}-only payloads (pre-migration trigger)
//                       fall back to a snapshot reconcile.
//   - "game_started":   {game_id} — navigate straight into the game.
//   - "player_removed": {user_id} — if it's me, redirect with the right
//                       kicked/banned toast. Roster updates ride the
//                       "update" event.
//
// Self-heal: snapshot reconcile on subscribe, refocus, regained network,
// and version gaps. The reconcile also catches a game start we slept
// through (backgrounded tab) via snapshot.game_id.
//
// Bans are intentionally NOT live here: only the host sees them, and only
// the host's own actions change them — his action response refreshes them.

type LobbyPayload = {
  version?: number;
  room?: Room;
  players?: Player[];
  game_id?: string | null;
};

export function LobbyLive({
  initialVersion,
  initialRoom,
  initialPlayers,
  bans,
  currentUserId,
}: {
  initialVersion: number;
  initialRoom: Room;
  initialPlayers: Player[];
  bans: Ban[];
  currentUserId: string;
}) {
  const supabase = useMemo(() => createClient(), []);
  const router = useRouter();

  const [room, setRoom] = useState(initialRoom);
  const [players, setPlayers] = useState(initialPlayers);
  const [channelDown, setChannelDown] = useState(false);
  const online = useBrowserOnline();
  const versionRef = useRef(initialVersion);
  const reconcileInFlight = useRef(false);

  const roomId = initialRoom.id;
  const roomCode = initialRoom.code;

  // While THIS client's own Start game is in flight, its server action
  // redirects into the game and renders it in the same response. The
  // game_started broadcast lands before that response does; pushing on it
  // too fetched and rendered the game page a second time, competing with
  // the redirect on the host's critical path. So the host defers to the
  // redirect, with a fallback push in case it never lands. The timer dies
  // with the lobby when the redirect succeeds.
  const startingRef = useRef(false);
  const fallbackTimer = useRef<number | null>(null);
  useEffect(
    () => () => {
      if (fallbackTimer.current) window.clearTimeout(fallbackTimer.current);
    },
    [],
  );
  const goToGame = useCallback(
    (gameId: string) => {
      if (!startingRef.current) {
        router.push(`/game/${gameId}`);
        return;
      }
      if (fallbackTimer.current) return;
      fallbackTimer.current = window.setTimeout(
        () => router.push(`/game/${gameId}`),
        4000,
      );
    },
    [router],
  );
  const handleStartPending = useCallback((pending: boolean) => {
    startingRef.current = pending;
  }, []);

  // Broadcasts must be strictly newer. A snapshot is the authoritative
  // read, so it also applies at an EQUAL version: that's what lets the
  // subscribe-time reconcile repair a bad initial render instead of
  // discarding the fix because nothing had changed since.
  const applyIfNewer = useCallback(
    (payload: LobbyPayload, opts?: { allowEqual?: boolean }): boolean => {
      if (
        typeof payload.version !== "number" ||
        payload.version < versionRef.current ||
        (payload.version === versionRef.current && !opts?.allowEqual)
      ) {
        return false;
      }
      if (!payload.room || !Array.isArray(payload.players)) return false;
      versionRef.current = payload.version;
      setRoom(payload.room);
      setPlayers(payload.players);
      return true;
    },
    [],
  );

  const reconcile = useCallback(async () => {
    if (reconcileInFlight.current) return;
    reconcileInFlight.current = true;
    try {
      const { data } = await supabase.rpc("get_lobby_snapshot", {
        p_room_id: roomId,
      });
      if (!data || typeof data !== "object") return;
      const snap = data as LobbyPayload;
      // A game started while we weren't listening — go play it.
      if (snap.room?.status === "in_game" && snap.game_id) {
        goToGame(snap.game_id);
        return;
      }
      applyIfNewer(snap, { allowEqual: true });
    } finally {
      reconcileInFlight.current = false;
    }
  }, [supabase, roomId, goToGame, applyIfNewer]);

  useEffect(() => {
    const channel = supabase
      .channel(`lobby:${roomId}`)
      .on("broadcast", { event: "update" }, (msg) => {
        const payload = msg.payload as LobbyPayload | undefined;
        if (!payload || typeof payload.version !== "number") return;
        if (payload.version <= versionRef.current) return;
        // Skinny {version}-only payload (pre-migration trigger): we know
        // we're behind but weren't handed the state — fetch it instead.
        if (!applyIfNewer(payload)) reconcile();
      })
      .on("broadcast", { event: "game_started" }, (msg) => {
        const gameId = (msg.payload as { game_id?: string } | undefined)
          ?.game_id;
        if (gameId) goToGame(gameId);
      })
      .on("broadcast", { event: "player_removed" }, async (msg) => {
        const removedUserId = (msg.payload as { user_id?: string } | undefined)
          ?.user_id;
        if (removedUserId !== currentUserId) return; // roster rides "update"
        const voluntary =
          window.sessionStorage.getItem("voluntary-leave") === roomId;
        if (voluntary) {
          window.sessionStorage.removeItem("voluntary-leave");
          return; // server action handles the redirect
        }
        // RLS lets a banned user see their own ban row, so this tells
        // kicked and banned apart.
        const { data: ban } = await supabase
          .from("room_bans")
          .select("user_id")
          .eq("room_id", roomId)
          .eq("user_id", currentUserId)
          .maybeSingle();
        router.push(
          ban ? `/play?banned=${roomCode}` : `/play?kicked=${roomCode}`,
        );
      })
      .subscribe((status) => {
        if (status === "SUBSCRIBED") {
          setChannelDown(false);
          reconcile();
        } else if (
          status === "CHANNEL_ERROR" ||
          status === "TIMED_OUT" ||
          status === "CLOSED"
        ) {
          setChannelDown(true);
        }
      });

    const onVisible = () => {
      if (document.visibilityState === "visible") reconcile();
    };
    document.addEventListener("visibilitychange", onVisible);
    window.addEventListener("focus", onVisible);

    return () => {
      supabase.removeChannel(channel);
      document.removeEventListener("visibilitychange", onVisible);
      window.removeEventListener("focus", onVisible);
    };
  }, [supabase, roomId, roomCode, currentUserId, router, applyIfNewer, reconcile, goToGame]);

  // Regained network: the channel rejoins on its own, but the lobby may
  // have moved while we were dark — resync immediately.
  useEffect(() => {
    if (online) reconcile();
  }, [online, reconcile]);

  // Own server actions revalidate the page; if that fresh server render
  // carries a newer version than our last broadcast, we missed an event —
  // resync rather than render stale state.
  useEffect(() => {
    if (initialVersion > versionRef.current) reconcile();
  }, [initialVersion, reconcile]);

  return (
    <>
      <ConnectionPill show={channelDown || !online} />
      <LobbyClient
        room={room}
        players={players}
        bans={bans}
        currentUserId={currentUserId}
        onStartPending={handleStartPending}
      />
    </>
  );
}
