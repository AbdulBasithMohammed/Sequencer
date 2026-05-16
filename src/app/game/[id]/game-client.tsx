"use client";

import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { Board, type BoardState } from "@/components/game/board";
import { HandStrip } from "@/components/game/hand-strip";
import { TurnBanner, type RosterPlayer } from "@/components/game/turn-banner";
import { WinScreen } from "@/components/game/win-screen";
import { classifyCard, isDeadCard } from "@/lib/board-layout";

export function GameClient({
  gameId,
  gameVersion,
  status,
  winnerTeam,
  board,
  turnSeat,
  turnDeadline,
  players,
  hand,
  roomCode,
}: {
  gameId: string;
  gameVersion: number;
  status: string;
  winnerTeam: number | null;
  board: BoardState;
  turnSeat: number | null;
  turnDeadline: string | null;
  players: RosterPlayer[];
  hand: string[];
  roomCode: string | null;
}) {
  const [selectedIdx, setSelectedIdx] = useState<number | null>(null);
  const [burningIdx, setBurningIdx] = useState<number | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const router = useRouter();
  const lastHandSigRef = useRef<string>(hand.join(","));

  useEffect(() => {
    const sig = hand.join(",");
    if (sig !== lastHandSigRef.current) {
      lastHandSigRef.current = sig;
      setBurningIdx(null);
    }
  }, [hand]);

  const me = players.find((p) => p.is_me) ?? null;
  const gameFinished = status === "finished";
  const myTurn = !gameFinished && me != null && me.seat_index === turnSeat;
  const selectedCard = selectedIdx != null ? (hand[selectedIdx] ?? null) : null;
  const selectedKind = selectedCard ? classifyCard(selectedCard) : null;
  const selectedIsDead =
    selectedCard != null && isDeadCard(selectedCard, board);
  const interactable =
    myTurn && !submitting && burningIdx == null && !gameFinished;

  // Every normal-card in the hand whose two board positions are both
  // taken. Surfaced as a dedicated swap panel so a stuck player can
  // always find the discard action on their turn.
  const deadCardsInHand = hand
    .map((card, idx) => ({ card, idx }))
    .filter(
      ({ card }) =>
        classifyCard(card) === "normal" && isDeadCard(card, board),
    );

  async function handleCellClick(row: number, col: number) {
    if (!interactable || selectedCard == null || selectedIdx == null) return;
    if (selectedIsDead) {
      setError("That card is dead — use the swap button instead.");
      return;
    }
    setError(null);
    setSubmitting(true);
    const idxBeingPlayed = selectedIdx;
    const supabase = createClient();
    const rpcName =
      selectedKind === "two_eyed_jack"
        ? "play_wild"
        : selectedKind === "one_eyed_jack"
          ? "play_remove"
          : "play_move";
    const { error: rpcError } = await supabase.rpc(rpcName, {
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
    setBurningIdx(idxBeingPlayed);
    setSelectedIdx(null);
    await new Promise((r) => window.setTimeout(r, 540));
    setSubmitting(false);
    router.refresh();
  }

  async function handleSwapDead(card: string, idx: number) {
    if (!interactable) return;
    if (classifyCard(card) !== "normal" || !isDeadCard(card, board)) {
      setError("Only dead cards can be swapped.");
      return;
    }
    setError(null);
    setSubmitting(true);
    const supabase = createClient();
    const { error: rpcError } = await supabase.rpc("swap_dead_card", {
      p_game_id: gameId,
      p_client_version: gameVersion,
      p_card: card,
    });
    if (rpcError) {
      setSubmitting(false);
      setError(rpcError.message);
      return;
    }
    setBurningIdx(idx);
    if (selectedIdx === idx) setSelectedIdx(null);
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
      {gameFinished ? (
        <div className="mb-4">
          <WinScreen
            winnerTeam={winnerTeam}
            players={players}
            roomCode={roomCode}
          />
        </div>
      ) : (
        <div className="mb-3">
          <TurnBanner
            players={players}
            turnSeat={turnSeat}
            turnDeadline={turnDeadline}
          />
        </div>
      )}
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
          <Board
            state={board}
            selectedCard={selectedCard}
            selectedKind={selectedKind}
            myTeam={me?.team ?? null}
            onCellClick={handleCellClick}
          />
        </div>
      </div>
      <div className="mt-1">
        <div className="mb-1 text-center text-[11px] font-semibold uppercase tracking-[0.2em] text-ink-soft">
          Your hand
          {gameFinished ? null : !myTurn ? (
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
      {myTurn && deadCardsInHand.length > 0 ? (
        <div className="mt-3 flex flex-col items-center gap-2">
          <span className="text-[11px] font-semibold uppercase tracking-[0.18em] text-ink-soft">
            Dead cards · discard for a fresh draw
          </span>
          <div className="flex flex-wrap items-center justify-center gap-2">
            {deadCardsInHand.map(({ card, idx }) => (
              <button
                key={`${card}-${idx}`}
                type="button"
                onClick={() => handleSwapDead(card, idx)}
                disabled={!interactable}
                className="inline-flex items-center gap-1.5 rounded-full border border-line bg-canvas px-3 py-1 text-[12px] font-semibold text-ink shadow-sm transition-colors hover:bg-surface disabled:opacity-50"
              >
                <span className="font-mono font-bold">{card}</span>
                <span className="text-ink-soft">Swap</span>
              </button>
            ))}
          </div>
        </div>
      ) : null}
      {myTurn && selectedCard ? (
        <div className="mt-3 text-center text-[11px] text-ink-soft">
          {selectedIsDead ? (
            <>
              <span className="font-mono font-bold text-ink">
                {selectedCard}
              </span>{" "}
              is dead — tap its Swap button below.
            </>
          ) : selectedKind === "two_eyed_jack" ? (
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
      ) : null}
    </>
  );
}

