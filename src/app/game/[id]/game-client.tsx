"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { Board } from "@/components/game/board";
import { HandStrip } from "@/components/game/hand-strip";
import { TurnBanner } from "@/components/game/turn-banner";
import { WinScreen } from "@/components/game/win-screen";
import { classifyCard, isDeadCard } from "@/lib/board-layout";
import { playTurnBlip } from "@/lib/sound/turn-blip";
import { isMuted } from "@/components/game/mute-toggle";
import {
  ConnectionPill,
  useBrowserOnline,
} from "@/components/ui/connection-pill";
import {
  diffBoards,
  liveGameFromRaw,
  parseSnapshot,
  type GameSnapshot,
  type LastMove,
  type LiveGame,
} from "./snapshot";

// The live game loop is fully client-driven: the Postgres broadcast trigger
// ships the whole public games projection on every version bump, and we
// apply it straight to local state. No router.refresh(), no server
// re-render — a turn lands in one realtime hop.
//
// Private data (my hand) is never broadcast. We refetch it via get_my_hand
// exactly when it could have changed: the version bump consumed *my* turn
// (every hand mutation — play, jack, dead-card swap, AFK auto-discard —
// happens on the holder's turn).
//
// Self-healing, in order of how fast they catch a missed broadcast:
//   - gap detection (payload version skipped ahead) → snapshot reconcile
//   - stale-version RPC rejection → snapshot reconcile
//   - turn-deadline + grace timer → snapshot reconcile. The server's
//     pg_cron tick always advances an expired turn, so if the deadline
//     passes without a broadcast we know we're out of sync. This is what
//     un-freezes a game whose "your turn" broadcast got dropped.
//   - tab refocus / channel resubscribe → snapshot reconcile

// pg_cron ticks every 5s; give the server that plus delivery slack before
// concluding we missed the deadline broadcast.
const DEADLINE_GRACE_MS = 8_000;

const WIN_TEAM_COLOR: Record<number, string> = {
  1: "var(--color-pink)",
  2: "var(--color-blue)",
  3: "var(--color-mint)",
};
const WIN_TEAM_LABEL: Record<number, string> = {
  1: "Pink",
  2: "Blue",
  3: "Mint",
};

export function GameClient({
  gameId,
  initialSnapshot,
  myUserId,
}: {
  gameId: string;
  initialSnapshot: GameSnapshot;
  myUserId: string;
}) {
  const supabase = useMemo(() => createClient(), []);

  const [game, setGame] = useState<LiveGame>(initialSnapshot.live);
  const [players, setPlayers] = useState(initialSnapshot.players);
  const [hand, setHand] = useState<string[]>(initialSnapshot.hand);
  const [lastMove, setLastMove] = useState<LastMove | null>(
    initialSnapshot.lastMove,
  );

  const [selectedIdx, setSelectedIdx] = useState<number | null>(null);
  const [burningIdx, setBurningIdx] = useState<number | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [channelDown, setChannelDown] = useState(false);
  // Results overlay can be dismissed to inspect the final board.
  const [resultsDismissed, setResultsDismissed] = useState(false);
  const online = useBrowserOnline();

  // Callbacks (broadcast handler, timers) need the freshest state without
  // resubscribing the channel on every turn.
  const gameRef = useRef(game);
  const handFetchSeq = useRef(0);
  const reconcileInFlight = useRef(false);
  const lastTurnSeatRef = useRef<number | null>(initialSnapshot.live.turnSeat);

  // The card-burn animation must play out even though the broadcast (and
  // with it the refreshed hand) lands much faster than 540ms. Any hand
  // update that arrives mid-burn is parked here and flushed by
  // finishBurn(), so the burning card isn't yanked out from under the
  // animation.
  const burningRef = useRef(false);
  const pendingHandRef = useRef<string[] | null>(null);

  const setHandDeferred = useCallback((next: string[]) => {
    if (burningRef.current) {
      pendingHandRef.current = next;
    } else {
      setHand(next);
    }
  }, []);

  const me = players.find((p) => p.is_me) ?? null;
  const mySeat = me?.seat_index ?? null;
  const mySeatRef = useRef(mySeat);
  useEffect(() => {
    mySeatRef.current = mySeat;
  }, [mySeat]);

  const applyLive = useCallback((next: LiveGame, nextLastMove?: LastMove | null) => {
    const prev = gameRef.current;
    if (next.version < prev.version) return false;
    if (next.version === prev.version && next.status === prev.status) {
      return false;
    }
    gameRef.current = next;
    setGame(next);
    if (nextLastMove !== undefined) {
      setLastMove(nextLastMove);
    } else {
      const lm = diffBoards(prev.board, next.board);
      if (lm) setLastMove(lm);
    }
    return true;
  }, []);

  const refetchHand = useCallback(async () => {
    const seq = ++handFetchSeq.current;
    const { data } = await supabase.rpc("get_my_hand", { p_game_id: gameId });
    if (seq !== handFetchSeq.current) return; // a newer fetch superseded us
    if (Array.isArray(data)) setHandDeferred(data as string[]);
  }, [supabase, gameId, setHandDeferred]);

  // Full resync straight from Supabase (one hop) — game, roster, hand,
  // last move. Used by every self-heal path.
  const reconcile = useCallback(async () => {
    if (reconcileInFlight.current) return;
    reconcileInFlight.current = true;
    try {
      const { data } = await supabase.rpc("get_game_snapshot", {
        p_game_id: gameId,
      });
      const snap = parseSnapshot(data, myUserId);
      if (!snap) return;
      if (snap.live.version >= gameRef.current.version) {
        gameRef.current = snap.live;
        setGame(snap.live);
        setPlayers(snap.players);
        setLastMove(snap.lastMove);
        handFetchSeq.current++;
        setHandDeferred(snap.hand);
      }
    } finally {
      reconcileInFlight.current = false;
    }
  }, [supabase, gameId, myUserId, setHandDeferred]);

  // Broadcast subscription — the hot path of every turn. `reconcile` and
  // `refetchHand` are stable callbacks (their deps are fixed for a mounted
  // game), so listing them as deps never resubscribes the channel.
  useEffect(() => {
    const channel = supabase
      .channel(`game:${gameId}`)
      .on("broadcast", { event: "update" }, (msg) => {
        const payload = msg.payload as
          | Parameters<typeof liveGameFromRaw>[0]
          | undefined;
        if (!payload || typeof payload.version !== "number") return;
        const prev = gameRef.current;
        if (payload.version <= prev.version) return; // dedupe / out-of-order
        // Skinny {version}-only payload (pre-migration trigger): we know
        // we're behind but weren't handed the state — fetch it instead.
        if (!Array.isArray(payload.board)) {
          reconcile();
          return;
        }
        const next = liveGameFromRaw(payload);
        const prevTurnSeat = prev.turnSeat;
        const gap = payload.version > prev.version + 1;
        applyLive(next);
        // Any move that touched my hand happened while I held the turn.
        if (prevTurnSeat != null && prevTurnSeat === mySeatRef.current) {
          refetchHand();
        }
        // Missed at least one event — board is already current (payload is
        // the full state) but the hand might not be; resync everything.
        if (gap) reconcile();
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
          // supabase-js rejoins with backoff; we just make the gap visible.
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
  }, [supabase, gameId, applyLive, reconcile, refetchHand]);

  // Coming back online: the channel will rejoin on its own, but the state
  // may have moved while we were dark — resync immediately.
  useEffect(() => {
    if (online) reconcile();
  }, [online, reconcile]);

  // Freeze-proof backstop: the server always advances an expired turn (cron
  // tick), so a deadline that passes silently means we missed a broadcast.
  // Reschedules itself on every applied update.
  useEffect(() => {
    if (game.status !== "in_game" || !game.turnDeadline) return;
    const due =
      new Date(game.turnDeadline).getTime() - Date.now() + DEADLINE_GRACE_MS;
    const timer = window.setTimeout(
      () => reconcile(),
      Math.max(due, 1_000),
    );
    return () => window.clearTimeout(timer);
  }, [game.status, game.turnDeadline, game.version, reconcile]);

  // Subtle audio cue on any turn change. Skipped on initial mount
  // (ref starts equal to the prop) and when muted.
  useEffect(() => {
    if (lastTurnSeatRef.current === game.turnSeat) return;
    lastTurnSeatRef.current = game.turnSeat;
    if (game.status !== "in_game") return;
    if (isMuted()) return;
    playTurnBlip();
  }, [game.turnSeat, game.status]);

  const gameFinished = game.status === "finished";
  const myTurn = !gameFinished && me != null && me.seat_index === game.turnSeat;
  const selectedCard = selectedIdx != null ? (hand[selectedIdx] ?? null) : null;
  const selectedKind = selectedCard ? classifyCard(selectedCard) : null;
  const selectedIsDead =
    selectedCard != null && isDeadCard(selectedCard, game.board);
  const interactable =
    myTurn && !submitting && burningIdx == null && !gameFinished;

  function handleRpcError(rpcError: { code?: string; message: string }) {
    setSubmitting(false);
    if (rpcError.code === "40001") {
      // Stale optimistic-concurrency version — resync and let them retry.
      reconcile();
      setError("The board moved on — try again.");
      return;
    }
    setError(rpcError.message);
  }

  // Burn lifecycle. The animation gets its full duration even though the
  // confirming broadcast lands much sooner; hand updates queued during the
  // burn are flushed at the end so the drawn card appears exactly when the
  // played card finishes burning out.
  function beginBurn(idx: number) {
    burningRef.current = true;
    setBurningIdx(idx);
    return new Promise<void>((r) => window.setTimeout(r, 540));
  }

  function finishBurn() {
    burningRef.current = false;
    setBurningIdx(null);
    if (pendingHandRef.current) {
      setHand(pendingHandRef.current);
      pendingHandRef.current = null;
    }
  }

  // Optimistic board mutation: the chip lands the instant you tap; the
  // broadcast (a strictly newer version) confirms it moments later. The
  // returned restore function rolls back if the server rejects — but only
  // while no newer authoritative state has arrived in the meantime.
  function applyOptimisticCell(
    row: number,
    col: number,
    team: number | null,
    action: "place" | "remove",
  ) {
    const prev = gameRef.current;
    const prevLastMove = lastMove;
    const board = prev.board.map((r) => r.slice());
    const cell = board[row]?.[col] ?? { team: null, sequence_ids: [] };
    board[row][col] = { team, sequence_ids: cell.sequence_ids ?? [] };
    const next = { ...prev, board };
    gameRef.current = next;
    setGame(next);
    setLastMove({ row, col, action });
    return () => {
      if (gameRef.current.version === prev.version) {
        gameRef.current = prev;
        setGame(prev);
        setLastMove(prevLastMove);
      }
    };
  }

  async function handleCellClick(row: number, col: number) {
    if (!interactable || selectedCard == null || selectedIdx == null) return;
    if (selectedIsDead) {
      setError("That card is dead — use the swap button instead.");
      return;
    }
    setError(null);
    setSubmitting(true);
    const idxBeingPlayed = selectedIdx;
    const rpcName =
      selectedKind === "two_eyed_jack"
        ? "play_wild"
        : selectedKind === "one_eyed_jack"
          ? "play_remove"
          : "play_move";
    const clientVersion = gameRef.current.version;
    const rollback =
      rpcName === "play_remove"
        ? applyOptimisticCell(row, col, null, "remove")
        : me?.team != null
          ? applyOptimisticCell(row, col, me.team, "place")
          : null;
    const burnDone = beginBurn(idxBeingPlayed);
    setSelectedIdx(null);
    const { data: newVersion, error: rpcError } = await supabase.rpc(rpcName, {
      p_game_id: gameId,
      p_client_version: clientVersion,
      p_card: selectedCard,
      p_row: row,
      p_col: col,
    });
    if (rpcError) {
      rollback?.();
      finishBurn();
      handleRpcError(rpcError);
      return;
    }
    awaitOwnBroadcast(newVersion);
    await burnDone;
    finishBurn();
    setSubmitting(false);
  }

  async function handleSwapDead(card: string, idx: number) {
    if (!interactable) return;
    if (classifyCard(card) !== "normal" || !isDeadCard(card, game.board)) {
      setError("Only dead cards can be swapped.");
      return;
    }
    setError(null);
    setSubmitting(true);
    const burnDone = beginBurn(idx);
    if (selectedIdx === idx) setSelectedIdx(null);
    const { data: newVersion, error: rpcError } = await supabase.rpc(
      "swap_dead_card",
      {
        p_game_id: gameId,
        p_client_version: gameRef.current.version,
        p_card: card,
      },
    );
    if (rpcError) {
      finishBurn();
      handleRpcError(rpcError);
      return;
    }
    awaitOwnBroadcast(newVersion);
    await burnDone;
    finishBurn();
    setSubmitting(false);
  }

  // The mutation RPCs return the version they produced. The broadcast for
  // it normally lands within the burn animation; if it hasn't after a
  // beat, pull the state ourselves instead of leaving the UI behind.
  function awaitOwnBroadcast(newVersion: unknown) {
    if (typeof newVersion !== "number") return;
    window.setTimeout(() => {
      if (gameRef.current.version < newVersion) reconcile();
    }, 1_500);
  }

  function handleSelect(idx: number) {
    // Allow selecting cards off-turn so the player can preview placement
    // spots. Submission paths (handleCellClick / handleSwapDead) still
    // gate on `interactable`, so the preview is read-only.
    if (gameFinished || burningIdx != null) return;
    setError(null);
    setSelectedIdx((cur) => (cur === idx ? null : idx));
  }

  return (
    <>
      <ConnectionPill show={channelDown || !online} />

      {/* Results overlay: floats above the dimmed board so the layout
          never reflows. Click outside (or "view final board") to peek at
          the finished board; the strip's button brings it back. Inline
          animation so the page-level stagger rules can't delay it. */}
      {gameFinished && !resultsDismissed && (
        <div
          role="dialog"
          aria-modal="true"
          aria-label="Game results"
          className="fixed inset-0 z-40 flex items-start justify-center overflow-y-auto bg-ink/40 px-4 py-10 backdrop-blur-[2px] sm:items-center"
          style={{ animation: "overlay-fade 250ms ease-out backwards" }}
          onClick={() => setResultsDismissed(true)}
        >
          <div
            className="w-full max-w-[520px]"
            onClick={(e) => e.stopPropagation()}
          >
            <WinScreen
              winnerTeam={game.winnerTeam}
              players={players}
              roomId={initialSnapshot.roomId}
              roomCode={initialSnapshot.roomCode}
              onViewBoard={() => setResultsDismissed(true)}
            />
          </div>
        </div>
      )}
      <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
        <div>
          <div className="text-[11px] font-semibold uppercase tracking-[0.2em] text-ink-soft">
            Room
          </div>
          <div
            className="font-mono font-bold leading-none text-ink"
            style={{ fontSize: 28, letterSpacing: "0.06em" }}
          >
            {initialSnapshot.roomCode ?? "?"}
          </div>
        </div>
        <div className="text-[12px] text-ink-soft">
          v<span className="font-mono font-bold text-ink">{game.version}</span>
        </div>
      </div>

      {gameFinished ? (
        // Slim result strip where the turn banner was — the win card itself
        // floats in an overlay so the board never gets pushed down.
        <div className="mb-3 flex min-h-[34px] items-center justify-center gap-3">
          <span className="inline-flex items-center gap-2 text-[14px] font-semibold text-ink">
            <span
              aria-hidden
              className="inline-block size-2.5 rounded-full"
              style={{
                background:
                  game.winnerTeam != null
                    ? WIN_TEAM_COLOR[game.winnerTeam]
                    : "var(--color-ink-soft)",
              }}
            />
            {game.winnerTeam == null
              ? "Game ended"
              : me?.team === game.winnerTeam
                ? "You won!"
                : `${WIN_TEAM_LABEL[game.winnerTeam] ?? `Team ${game.winnerTeam}`} wins`}
          </span>
          {resultsDismissed && (
            <button
              type="button"
              onClick={() => setResultsDismissed(false)}
              className="rounded-full border border-line bg-surface px-3 py-1 text-[12px] font-semibold text-ink transition-colors hover:bg-canvas"
            >
              Show results
            </button>
          )}
        </div>
      ) : (
        <div className="mb-3">
          <TurnBanner
            players={players}
            turnSeat={game.turnSeat}
            turnDeadline={game.turnDeadline}
          />
          <DeckIndicator
            deckCount={game.deckCount}
            discardCount={game.discardCount}
          />
        </div>
      )}
      <div
        // The board is up to 96vw wide — wider than the page's padded
        // column on phones. Break out of the padding so mx-auto centers
        // it on the viewport like every other centered block (turn
        // banner, win card); inside the padded column it overflowed
        // right and sat visibly off-center.
        className="-mx-6 lg:-mx-10"
      >
        <div
          className="relative mx-auto"
          style={{
            aspectRatio: "70 / 50",
            width: "min(96vw, calc((100dvh - 280px) * 70 / 50), 1100px)",
          }}
        >
          <div
            className="absolute top-1/2 left-1/2"
            style={{
              width: "calc(100% * 5 / 7)",
              aspectRatio: "5 / 7",
              transform: "translate(-50%, -50%) rotate(90deg)",
            }}
          >
            <Board
              state={game.board}
              selectedCard={selectedCard}
              selectedKind={selectedKind}
              myTeam={me?.team ?? null}
              onCellClick={handleCellClick}
              lastMove={lastMove}
              preview={!myTurn}
            />
          </div>
        </div>
      </div>
      <div className="mt-1">
        <div className="mb-1 text-center text-[11px] font-semibold uppercase tracking-[0.2em] text-ink-soft">
          Your hand
          {gameFinished ? null : !myTurn ? (
            <span className="ml-2 font-normal normal-case tracking-normal text-ink-soft">
              · waiting on{" "}
              {players.find((p) => p.seat_index === game.turnSeat)
                ?.display_name ?? "another player"}
            </span>
          ) : null}
        </div>
        <HandStrip
          cards={hand}
          selectedIdx={selectedIdx}
          onSelect={handleSelect}
          burningIdx={burningIdx}
        />
      </div>
      {/* Fixed-height hint slot: reserves vertical space so toggling
          selection doesn't shift the hand + board above it. */}
      <div className="mt-3 flex h-[64px] items-start justify-center">
        {error ? (
          <div className="text-center text-[12px] font-semibold text-pink">
            {error}
          </div>
        ) : myTurn && selectedCard && selectedIsDead && selectedIdx != null ? (
          <div className="flex flex-col items-center gap-2 text-[11px] text-ink-soft">
            <span>
              <span className="font-mono font-bold text-ink">
                {selectedCard}
              </span>{" "}
              is dead — no open tile remains.
            </span>
            <button
              type="button"
              onClick={() => handleSwapDead(selectedCard, selectedIdx)}
              disabled={!interactable}
              className="rounded-full border border-line bg-canvas px-3 py-1 text-[12px] font-semibold text-ink shadow-sm transition-colors hover:bg-surface disabled:opacity-50"
            >
              Swap dead card
            </button>
          </div>
        ) : myTurn && selectedCard ? (
          <div className="text-center text-[11px] text-ink-soft">
            {selectedKind === "two_eyed_jack" ? (
              <>
                <span className="font-mono font-bold text-ink">
                  {selectedCard}
                </span>{" "}
                is wild — tap any glowing tile.
              </>
            ) : selectedKind === "one_eyed_jack" ? (
              <>
                <span className="font-mono font-bold text-ink">
                  {selectedCard}
                </span>{" "}
                removes an opponent chip — tap a glowing one.
              </>
            ) : (
              <>
                Tap a glowing tile to place your{" "}
                <span className="font-mono font-bold text-ink">
                  {selectedCard}
                </span>
              </>
            )}
          </div>
        ) : !myTurn && selectedCard ? (
          <div className="text-center text-[11px] text-ink-soft">
            Previewing{" "}
            <span className="font-mono font-bold text-ink">{selectedCard}</span>{" "}
            · wait for your turn to play.
          </div>
        ) : null}
      </div>
    </>
  );
}

function DeckIndicator({
  deckCount,
  discardCount,
}: {
  deckCount: number;
  discardCount: number;
}) {
  const total = 104;
  const used = total - deckCount - discardCount; // chips on the board + in hands
  return (
    <div className="mt-2 flex items-center justify-center gap-2 text-[10px] font-semibold uppercase tracking-[0.15em] text-ink-soft">
      <span className="inline-flex items-center gap-1">
        <span aria-hidden>🂠</span>
        <span className="text-ink">{deckCount}</span>
        <span>deck</span>
      </span>
      <span aria-hidden>·</span>
      <span className="inline-flex items-center gap-1">
        <span aria-hidden>♺</span>
        <span className="text-ink">{discardCount}</span>
        <span>discard</span>
      </span>
      <span aria-hidden>·</span>
      <span className="inline-flex items-center gap-1">
        <span className="text-ink">{Math.max(0, used)}</span>
        <span>in play</span>
      </span>
    </div>
  );
}
