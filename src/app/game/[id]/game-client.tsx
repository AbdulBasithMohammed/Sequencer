"use client";

import { useEffect, useRef, useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { Board, type BoardState } from "@/components/game/board";
import { BoardPanZoom } from "@/components/game/board-pan-zoom";
import { HandStrip } from "@/components/game/hand-strip";
import { TurnBanner, type RosterPlayer } from "@/components/game/turn-banner";
import { classifyCard, isDeadCard } from "@/lib/board-layout";

const TEAM_COLOR: Record<number, string> = {
  1: "var(--color-pink)",
  2: "var(--color-blue)",
  3: "var(--color-mint)",
};

const TEAM_LABEL: Record<number, string> = {
  1: "Pink",
  2: "Blue",
  3: "Mint",
};

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

  async function handleSwapDead() {
    if (!interactable || selectedCard == null || selectedIdx == null) return;
    if (!selectedIsDead) {
      setError("Only dead cards can be swapped.");
      return;
    }
    setError(null);
    setSubmitting(true);
    const idxBeingSwapped = selectedIdx;
    const supabase = createClient();
    const { error: rpcError } = await supabase.rpc("swap_dead_card", {
      p_game_id: gameId,
      p_client_version: gameVersion,
      p_card: selectedCard,
    });
    if (rpcError) {
      setSubmitting(false);
      setError(rpcError.message);
      return;
    }
    setBurningIdx(idxBeingSwapped);
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
      {gameFinished ? (
        <div className="mb-3">
          <WinnerBanner winnerTeam={winnerTeam} myTeam={me?.team ?? null} />
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
          <BoardPanZoom>
            <Board
              state={board}
              selectedCard={selectedCard}
              selectedKind={selectedKind}
              myTeam={me?.team ?? null}
              onCellClick={handleCellClick}
            />
          </BoardPanZoom>
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
      {myTurn && selectedCard && selectedIsDead ? (
        <div className="mt-3 flex flex-col items-center gap-2 text-[11px] text-ink-soft">
          <span>
            <span className="font-mono font-bold text-ink">{selectedCard}</span>{" "}
            is dead — both board positions are claimed.
          </span>
          <button
            type="button"
            onClick={handleSwapDead}
            disabled={submitting}
            className="rounded-full border border-line/70 bg-canvas px-3 py-1 text-[12px] font-semibold text-ink shadow-sm transition-colors hover:bg-surface disabled:opacity-50"
          >
            Swap dead card
          </button>
        </div>
      ) : myTurn && selectedCard ? (
        <div className="mt-3 text-center text-[11px] text-ink-soft">
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
      ) : null}
    </>
  );
}

function WinnerBanner({
  winnerTeam,
  myTeam,
}: {
  winnerTeam: number | null;
  myTeam: number | null;
}) {
  if (winnerTeam == null) {
    return (
      <div className="text-center text-[14px] font-semibold text-ink">
        Game finished.
      </div>
    );
  }
  const isMe = myTeam === winnerTeam;
  return (
    <div className="flex flex-col items-center gap-1">
      <div className="flex items-center gap-2 text-[16px] font-bold text-ink">
        <span
          className="inline-block size-3 rounded-full"
          style={{ background: TEAM_COLOR[winnerTeam] }}
          aria-hidden
        />
        <span>
          {TEAM_LABEL[winnerTeam] ?? `Team ${winnerTeam}`} wins
          {isMe ? " — that's you!" : ""}
        </span>
      </div>
      <div className="text-[11px] text-ink-soft">
        Rematch flow ships in 7.A.
      </div>
    </div>
  );
}
