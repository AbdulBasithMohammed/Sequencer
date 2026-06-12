"use client";

import { useState, useTransition } from "react";
import { useRouter } from "next/navigation";
import { SoftLinkButton } from "@/components/ui/button";
import { type RosterPlayer } from "@/components/game/turn-banner";
import { setReadyAction } from "@/app/lobby/[code]/actions";

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

// Falling card suits behind the win card — pure CSS, fires once.
// left as %, size in px, fall distance / spin via CSS vars.
const CONFETTI: Array<{
  left: number;
  size: number;
  delay: number;
  dur: number;
  fall: number;
  spin: number;
  glyph: string;
  color: string;
}> = [
  { left: 4, size: 18, delay: 80, dur: 1500, fall: 170, spin: 260, glyph: "♥", color: "var(--color-pink)" },
  { left: 12, size: 14, delay: 320, dur: 1700, fall: 200, spin: -200, glyph: "♣", color: "var(--color-mint)" },
  { left: 20, size: 20, delay: 0, dur: 1400, fall: 150, spin: 180, glyph: "♦", color: "var(--color-blue)" },
  { left: 29, size: 13, delay: 480, dur: 1800, fall: 220, spin: -280, glyph: "♠", color: "var(--color-ink)" },
  { left: 37, size: 17, delay: 160, dur: 1500, fall: 180, spin: 240, glyph: "♥", color: "var(--color-butter)" },
  { left: 46, size: 15, delay: 560, dur: 1600, fall: 160, spin: -180, glyph: "♦", color: "var(--color-pink)" },
  { left: 54, size: 19, delay: 240, dur: 1450, fall: 190, spin: 200, glyph: "♣", color: "var(--color-blue)" },
  { left: 63, size: 14, delay: 640, dur: 1750, fall: 210, spin: -240, glyph: "♥", color: "var(--color-mint)" },
  { left: 71, size: 16, delay: 40, dur: 1550, fall: 170, spin: 220, glyph: "♠", color: "var(--color-butter)" },
  { left: 79, size: 13, delay: 400, dur: 1650, fall: 200, spin: -160, glyph: "♦", color: "var(--color-mint)" },
  { left: 87, size: 18, delay: 200, dur: 1500, fall: 160, spin: 280, glyph: "♣", color: "var(--color-pink)" },
  { left: 94, size: 15, delay: 520, dur: 1700, fall: 190, spin: -220, glyph: "♥", color: "var(--color-blue)" },
];

// Rematch + Exit, shared by the win overlay and the slim in-board result
// strip. Self-contained so either mount works on its own.
export function RematchActions({
  roomId,
  roomCode,
}: {
  roomId: string | null;
  roomCode: string | null;
}) {
  const router = useRouter();
  const [pending, startTransition] = useTransition();
  const [readied, setReadied] = useState(false);

  // One tap: mark yourself ready for the next round and head back to the
  // lobby. Bots stay ready on their own; the host starts when everyone's in.
  function handleRematch() {
    if (!roomId || !roomCode) return;
    startTransition(async () => {
      const f = new FormData();
      f.set("roomId", roomId);
      f.set("ready", "true");
      await setReadyAction(f);
      setReadied(true);
      router.push(`/lobby/${roomCode}`);
    });
  }

  return (
    <div className="flex flex-wrap items-center justify-center gap-2">
      {roomId && roomCode ? (
        <button
          type="button"
          onClick={handleRematch}
          disabled={pending || readied}
          className="inline-flex items-center gap-2 rounded-full bg-ink px-4 py-2 text-[13px] font-semibold text-canvas shadow-sm transition-opacity hover:opacity-90 disabled:opacity-60"
        >
          {pending || readied ? "Readying up…" : "Rematch"}
        </button>
      ) : null}
      <SoftLinkButton href="/play" variant="outline" size="sm">
        Exit to menu
      </SoftLinkButton>
    </div>
  );
}

export function WinScreen({
  winnerTeam,
  players,
  roomId,
  roomCode,
  onViewBoard,
}: {
  winnerTeam: number | null;
  players: RosterPlayer[];
  roomId: string | null;
  roomCode: string | null;
  onViewBoard?: () => void;
}) {
  const me = players.find((p) => p.is_me) ?? null;
  const myTeam = me?.team ?? null;
  const noWinner = winnerTeam == null;
  const iWon = !noWinner && myTeam === winnerTeam;
  const color = winnerTeam != null ? TEAM_COLOR[winnerTeam] : "var(--color-ink-soft)";
  const teamLabel =
    winnerTeam != null ? (TEAM_LABEL[winnerTeam] ?? `Team ${winnerTeam}`) : null;

  const headline = noWinner
    ? "Game ended"
    : iWon
      ? "You won!"
      : `${teamLabel} wins`;

  const subline = noWinner
    ? "The game was ended without a winner."
    : iWon
      ? `Nice run on team ${teamLabel}.`
      : myTeam != null
        ? `Team ${TEAM_LABEL[myTeam] ?? myTeam} fell short — rematch?`
        : "Better luck next time.";

  const winners = winnerTeam != null
    ? players.filter((p) => p.team === winnerTeam)
    : [];

  return (
    <div
      className="win-enter relative mx-auto flex max-w-[520px] flex-col items-center gap-4 rounded-2xl border border-line bg-surface px-6 py-6 text-center shadow-sm"
      style={{
        borderTopWidth: 4,
        borderTopColor: color,
      }}
    >
      {!noWinner && (
        <div aria-hidden className="pointer-events-none absolute inset-x-0 top-0">
          {CONFETTI.map((c, i) => (
            <span
              key={i}
              className="absolute leading-none"
              style={{
                left: `${c.left}%`,
                top: -12,
                fontSize: c.size,
                color: c.color,
                ["--fall" as string]: `${c.fall}px`,
                ["--spin" as string]: `${c.spin}deg`,
                animation: `suit-fall ${c.dur}ms ${c.delay}ms ease-in both`,
              }}
            >
              {c.glyph}
            </span>
          ))}
        </div>
      )}
      <div className="flex items-center gap-2.5">
        <span
          className="inline-block size-3 rounded-full"
          style={{ background: color }}
          aria-hidden
        />
        <span className="text-[11px] font-semibold uppercase tracking-[0.2em] text-ink-soft">
          {noWinner ? "Finished" : "Sequence!"}
        </span>
      </div>

      <div className="font-display text-[28px] font-bold leading-tight text-ink">
        {headline}
      </div>

      <div className="text-[13px] text-ink-soft">{subline}</div>

      {winners.length > 0 ? (
        <div className="flex flex-wrap items-center justify-center gap-1.5">
          {winners.map((p) => (
            <div
              key={p.user_id}
              className="flex items-center gap-1.5 rounded-full border px-2.5 py-[3px] text-[11px] font-semibold"
              style={{
                borderColor: color,
                background: `${color}1A`,
                color: "var(--color-ink)",
              }}
            >
              <span
                className="inline-block size-2 rounded-full"
                style={{ background: color }}
                aria-hidden
              />
              <span>
                {p.display_name ?? `Seat ${p.seat_index}`}
                {p.is_me ? " (you)" : ""}
              </span>
            </div>
          ))}
        </div>
      ) : null}

      <RematchActions roomId={roomId} roomCode={roomCode} />

      {roomId && roomCode ? (
        <div className="text-[10px] uppercase tracking-[0.15em] text-ink-soft">
          Rematch readies you up — the host starts when everyone&apos;s in.
        </div>
      ) : null}

      {onViewBoard ? (
        <button
          type="button"
          onClick={onViewBoard}
          className="text-[11px] font-semibold text-ink-soft underline-offset-4 hover:text-ink hover:underline"
        >
          View the final board
        </button>
      ) : null}
    </div>
  );
}
