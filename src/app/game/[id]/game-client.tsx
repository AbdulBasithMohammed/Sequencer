"use client";

import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { Board, type BoardState } from "@/components/game/board";
import { BoardPanZoom } from "@/components/game/board-pan-zoom";
import { HandStrip } from "@/components/game/hand-strip";
import { TurnBanner, type RosterPlayer } from "@/components/game/turn-banner";

export function GameClient({
  gameId,
  gameVersion,
  board,
  turnSeat,
  players,
  hand,
}: {
  gameId: string;
  gameVersion: number;
  board: BoardState;
  turnSeat: number | null;
  players: RosterPlayer[];
  hand: string[];
}) {
  const [selectedIdx, setSelectedIdx] = useState<number | null>(null);
  const [burningIdx, setBurningIdx] = useState<number | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const router = useRouter();
  const lastHandSigRef = useRef<string>(hand.join(","));

  // Clear burningIdx only once the server-side hand actually changes —
  // otherwise the burnt card would flash back into the fan for one paint
  // between the animation ending and router.refresh() returning. The
  // card-burn keyframe uses `forwards` so it stays invisible while we
  // wait.
  useEffect(() => {
    const sig = hand.join(",");
    if (sig !== lastHandSigRef.current) {
      lastHandSigRef.current = sig;
      setBurningIdx(null);
    }
  }, [hand]);

  const me = players.find((p) => p.is_me) ?? null;
  const myTurn = me != null && me.seat_index === turnSeat;
  const selectedCard = selectedIdx != null ? (hand[selectedIdx] ?? null) : null;
  const interactable = myTurn && !submitting && burningIdx == null;

  async function handleCellClick(row: number, col: number) {
    if (!interactable || selectedCard == null || selectedIdx == null) return;
    setError(null);
    setSubmitting(true);
    const idxBeingPlayed = selectedIdx;
    const supabase = createClient();
    const { error: rpcError } = await supabase.rpc("play_move", {
      p_game_id: gameId,
      p_client_version: gameVersion,
      p_card: selectedCard,
      p_row: row,
      p_col: col,
    });
    if (rpcError) {
      setSubmitting(false);
      setError(rpcError.message);
      return;
    }
    // Hold the played card on screen long enough for its burn animation,
    // then refresh. We DON'T clear burningIdx here — the useEffect above
    // does that once the new hand prop arrives, so the played card stays
    // invisible (animation's `forwards` fill) until it's removed from the
    // server-side hand array.
    setBurningIdx(idxBeingPlayed);
    setSelectedIdx(null);
    await new Promise((r) => window.setTimeout(r, 540));
    setSubmitting(false);
    router.refresh();
  }

  function handleSelect(idx: number) {
    if (!interactable) return;
    setError(null);
    setSelectedIdx((cur) => (cur === idx ? null : idx));
  }

  return (
    <>
      <div className="mb-3">
        <TurnBanner players={players} turnSeat={turnSeat} />
      </div>
      {/* Landscape rotation wrapper. The Board renders as portrait (50:70),
          and this outer container reserves the landscape footprint (70:50)
          and rotates the portrait child 90° to the right around its center
          so it visually fills the landscape footprint. Cards rotate with
          the board; spatially the relationships are preserved. */}
      <div
        className="relative mx-auto"
        style={{
          aspectRatio: "70 / 50",
          width:
            "min(96vw, calc((100dvh - 280px) * 70 / 50), 1100px)",
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
          <BoardPanZoom>
            <Board
              state={board}
              selectedCard={selectedCard}
              onCellClick={handleCellClick}
            />
          </BoardPanZoom>
        </div>
      </div>
      <div className="mt-1">
        <div className="mb-1 text-center text-[11px] font-semibold uppercase tracking-[0.2em] text-ink-soft">
          Your hand
          {!myTurn ? (
            <span className="ml-2 font-normal normal-case tracking-normal text-ink-soft">
              · waiting on{" "}
              {players.find((p) => p.seat_index === turnSeat)?.display_name ??
                "another player"}
            </span>
          ) : null}
        </div>
        <HandStrip
          cards={hand}
          selectedIdx={selectedIdx}
          onSelect={handleSelect}
          disabled={!myTurn}
          burningIdx={burningIdx}
        />
      </div>
      {error ? (
        <div className="mt-3 text-center text-[12px] font-semibold text-pink">
          {error}
        </div>
      ) : null}
      {myTurn && selectedCard ? (
        <div className="mt-3 text-center text-[11px] text-ink-soft">
          Tap a glowing tile to place your{" "}
          <span className="font-mono font-bold text-ink">{selectedCard}</span>
        </div>
      ) : null}
    </>
  );
}
