"use client";

import { useEffect, useState } from "react";

// Shows whose turn it is + a countdown to the turn deadline + a roster of
// all seated players with the active seat highlighted. The countdown is
// purely visual — when it expires the server's pg_cron tick auto-discards
// the AFK player's top card and advances the turn (Phase 6.A).

const TEAM_COLOR: Record<number, string> = {
  1: "var(--color-pink)",
  2: "var(--color-blue)",
  3: "var(--color-mint)",
};

const LOW_THRESHOLD_MS = 10_000;

export type RosterPlayer = {
  user_id: string;
  seat_index: number;
  team: number | null;
  display_name: string | null;
  is_me: boolean;
  is_bot: boolean;
};

export function TurnBanner({
  players,
  turnSeat,
  turnDeadline,
}: {
  players: RosterPlayer[];
  turnSeat: number | null;
  turnDeadline?: string | null;
}) {
  const active = players.find((p) => p.seat_index === turnSeat) ?? null;
  const itsMyTurn = active?.is_me === true;
  const activeName = active?.is_me
    ? "your"
    : `${active?.display_name ?? `seat ${active?.seat_index ?? "?"}`}'s`;
  const activeColor =
    active?.team != null ? TEAM_COLOR[active.team] : "var(--color-ink-soft)";

  return (
    <div className="flex flex-col gap-3">
      <div className="flex items-center justify-center gap-2">
        <span
          className="inline-block size-2.5 rounded-full"
          style={{ background: activeColor }}
          aria-hidden
        />
        <span className="text-[14px] font-semibold text-ink">
          It&apos;s {activeName} turn
          {itsMyTurn ? " — your move" : ""}
        </span>
        {turnDeadline ? (
          <Countdown deadline={turnDeadline} />
        ) : null}
      </div>

      <div className="flex flex-wrap items-center justify-center gap-1.5">
        {players.map((p) => {
          const isActive = p.seat_index === turnSeat;
          const color =
            p.team != null ? TEAM_COLOR[p.team] : "var(--color-ink-soft)";
          return (
            <div
              key={p.user_id}
              className="flex items-center gap-1.5 rounded-full border px-2.5 py-[3px] text-[11px]"
              style={{
                borderColor: isActive ? color : "var(--color-line)",
                background: isActive ? `${color}1A` : "transparent",
                color: isActive ? "var(--color-ink)" : "var(--color-ink-soft)",
                fontWeight: isActive ? 700 : 500,
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
              {p.is_bot ? (
                <span
                  className="rounded-full px-1 py-px text-[8px] font-bold uppercase tracking-wider"
                  style={{
                    background: "var(--color-ink-soft)",
                    color: "var(--color-canvas)",
                  }}
                >
                  Bot
                </span>
              ) : null}
            </div>
          );
        })}
      </div>
    </div>
  );
}

function Countdown({ deadline }: { deadline: string }) {
  const deadlineMs = new Date(deadline).getTime();
  const [now, setNow] = useState<number>(() => Date.now());

  useEffect(() => {
    const id = window.setInterval(() => setNow(Date.now()), 250);
    return () => window.clearInterval(id);
  }, []);

  const remaining = Math.max(0, deadlineMs - now);
  const totalSeconds = Math.ceil(remaining / 1000);
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  const formatted = `${minutes}:${seconds.toString().padStart(2, "0")}`;
  const low = remaining > 0 && remaining < LOW_THRESHOLD_MS;
  const expired = remaining === 0;

  return (
    <span
      className="font-mono text-[12px] tabular-nums"
      style={{
        color: expired
          ? "var(--color-ink-soft)"
          : low
            ? "var(--color-pink)"
            : "var(--color-ink-soft)",
        fontWeight: low || expired ? 700 : 500,
      }}
      aria-label={`Time remaining: ${formatted}`}
    >
      {expired ? "advancing…" : formatted}
    </span>
  );
}
