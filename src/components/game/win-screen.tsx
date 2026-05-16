"use client";

import { SoftLinkButton } from "@/components/ui/button";
import { type RosterPlayer } from "@/components/game/turn-banner";

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

export function WinScreen({
  winnerTeam,
  players,
  roomCode,
}: {
  winnerTeam: number | null;
  players: RosterPlayer[];
  roomCode: string | null;
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
      className="mx-auto flex max-w-[520px] flex-col items-center gap-4 rounded-2xl border border-line bg-surface px-6 py-6 text-center shadow-sm"
      style={{
        borderTopWidth: 4,
        borderTopColor: color,
      }}
    >
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

      {roomCode ? (
        <SoftLinkButton href={`/lobby/${roomCode}`} variant="primary" size="sm">
          Back to lobby
        </SoftLinkButton>
      ) : (
        <SoftLinkButton href="/play" variant="primary" size="sm">
          Back to play
        </SoftLinkButton>
      )}

      <div className="text-[10px] uppercase tracking-[0.15em] text-ink-soft">
        Everyone re-readies in the lobby before the host can restart.
      </div>
    </div>
  );
}
