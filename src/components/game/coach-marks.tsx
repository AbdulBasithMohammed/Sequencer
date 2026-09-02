"use client";

import { useEffect, useMemo, useState } from "react";
import { type BoardState } from "@/components/game/board";
import { classifyCard, isDeadCard } from "@/lib/board-layout";

// First-game coaching. The site tour explains where things are; this
// explains the three things that actually confuse a new Sequence player —
// the two jacks doing opposite jobs, and a card that has quietly become
// unplayable.
//
// Rules, deliberately conservative:
//   - Only on your own turn. A hint that pops while a bot is moving reads
//     as part of the bot's move, and the board is already animating.
//   - One at a time, in encounter order. A stack of four tips at once is
//     the thing people close without reading.
//   - Never blocking. This floats over dead space below the board and has
//     pointer events only on its own two buttons, so it can never sit
//     between a player and the square they were about to tap.
//
// Which hints have fired is intentionally NOT persisted. It is per-game
// UI state; only "coaching is finished" outlives the session, as one
// column on the profile.

type HintId = "turn" | "dead" | "one_eyed" | "two_eyed";

const COPY: Record<HintId, { title: string; body: string }> = {
  turn: {
    title: "Your turn",
    body: "Pick a card from your hand, then tap either matching square on the board. Corners are free — they count for everyone.",
  },
  dead: {
    title: "That card is dead",
    body: "Both of its squares are already taken, so it can never be played. Swap it for a new one — one free swap per turn.",
  },
  one_eyed: {
    title: "One-eyed jack — remove",
    body: "Jack of spades or hearts takes an opponent's chip off the board. Chips inside a finished sequence are locked and safe.",
  },
  two_eyed: {
    title: "Two-eyed jack — wild",
    body: "Jack of diamonds or clubs plays on any open square you like. Worth saving for the square that finishes a run.",
  },
};

// Order is encounter order, not importance: whatever is true first gets
// explained first, so the tip always describes the hand in front of them.
const ORDER: HintId[] = ["turn", "dead", "one_eyed", "two_eyed"];

// How long a hint gets before retiring itself. The clock only runs while
// it is on screen — which is only during your own turn — so a hint that
// appears just as you play carries over to your next turn rather than
// being spent on someone else's move.
const HINT_MS = 14_000;

function holds(hand: string[], kind: "two_eyed_jack" | "one_eyed_jack") {
  return hand.some((c) => classifyCard(c) === kind);
}

export function CoachMarks({
  active,
  myTurn,
  hand,
  board,
  onDone,
}: {
  active: boolean;
  myTurn: boolean;
  hand: string[];
  board: BoardState;
  onDone: () => void;
}) {
  // `fired` is the only state. Which hint is showing is derived from it,
  // so nothing has to keep two sources of truth in step as the hand
  // changes underneath — a card played on one turn can make the dead-card
  // tip stop applying, and the derivation just stops offering it.
  const [fired, setFired] = useState<HintId[]>([]);

  const current = useMemo<HintId | null>(() => {
    if (!active || !myTurn) return null;

    const eligible = (id: HintId): boolean => {
      switch (id) {
        case "turn":
          return true;
        case "dead":
          return hand.some((c) => isDeadCard(c, board));
        case "one_eyed":
          return holds(hand, "one_eyed_jack");
        case "two_eyed":
          return holds(hand, "two_eyed_jack");
      }
    };

    return ORDER.find((id) => !fired.includes(id) && eligible(id)) ?? null;
  }, [active, myTurn, hand, board, fired]);

  // Retire a hint that has had its time on screen. A first-timer who is
  // reading the board rather than the tip should not have to dismiss four
  // cards by hand, and a tip that outstays its welcome is worse than none.
  useEffect(() => {
    if (!current) return;
    const t = window.setTimeout(() => {
      setFired((f) => (f.includes(current) ? f : [...f, current]));
    }, HINT_MS);
    return () => window.clearTimeout(t);
  }, [current]);

  if (!current) return null;
  const copy = COPY[current];
  const retire = () =>
    setFired((f) => (f.includes(current) ? f : [...f, current]));

  return (
    <div
      className="pointer-events-none fixed inset-x-0 bottom-4 z-30 flex justify-center px-4"
      role="status"
      aria-live="polite"
    >
      <div className="menu-enter pointer-events-auto w-full max-w-[360px] rounded-2xl border border-line bg-surface px-4 py-3 shadow-xl">
        <div className="flex items-start justify-between gap-3">
          <div className="min-w-0">
            <div className="flex items-center gap-1.5">
              <span
                aria-hidden
                className="inline-block size-2 shrink-0 rounded-full"
                style={{ background: "var(--color-butter)" }}
              />
              <h3 className="font-display text-[13px] font-bold leading-none">
                {copy.title}
              </h3>
            </div>
            <p className="mt-1.5 text-[12px] leading-[1.45] text-ink-soft">
              {copy.body}
            </p>
          </div>
          <button
            type="button"
            onClick={retire}
            aria-label="Dismiss tip"
            className="-mr-1 -mt-1 shrink-0 rounded-full px-2 py-0.5 text-base leading-none text-ink-soft hover:text-ink"
          >
            ×
          </button>
        </div>
        <div className="mt-2 flex items-center justify-between gap-2">
          <button
            type="button"
            onClick={onDone}
            className="text-[11px] font-semibold text-ink-soft underline-offset-4 hover:text-ink hover:underline"
          >
            Hide tips
          </button>
          <button
            type="button"
            onClick={retire}
            className="rounded-lg bg-ink px-3 py-1 text-[11.5px] font-semibold text-canvas transition-opacity hover:opacity-90"
          >
            Got it
          </button>
        </div>
      </div>
    </div>
  );
}
