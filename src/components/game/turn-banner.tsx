// Shows whose turn it is + a roster of all seated players with the active
// seat highlighted. Active seat's team color is used as the highlight.

const TEAM_COLOR: Record<number, string> = {
  1: "var(--color-pink)",
  2: "var(--color-blue)",
  3: "var(--color-mint)",
};

export type RosterPlayer = {
  user_id: string;
  seat_index: number;
  team: number | null;
  display_name: string | null;
  is_me: boolean;
};

export function TurnBanner({
  players,
  turnSeat,
}: {
  players: RosterPlayer[];
  turnSeat: number | null;
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
            </div>
          );
        })}
      </div>
    </div>
  );
}
