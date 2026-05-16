import { BOARD_LAYOUT, type BoardCard } from "@/lib/board-layout";
import { CardFace } from "./card-face";

export type BoardCell = { team: number | null; sequence_ids: number[] };
export type BoardState = BoardCell[][];

const TEAM_COLOR: Record<number, string> = {
  1: "var(--color-pink)",
  2: "var(--color-blue)",
  3: "var(--color-mint)",
};

const EMPTY_CELL: BoardCell = { team: null, sequence_ids: [] };

// Cells are portrait (5:7), the same shape as a real playing card. The
// overall grid is portrait too (50:70), and the GameClient wraps the board
// in a rotation container that rotates this whole portrait grid 90° to
// the right so it sits landscape on the page. Each cell counter-rotates
// its content so cards stay upright after the parent rotation.
const CELL_ASPECT = "5 / 7";

export type SelectedKind = "normal" | "two_eyed_jack" | "one_eyed_jack";

export function Board({
  state,
  selectedCard,
  selectedKind,
  myTeam,
  onCellClick,
}: {
  state: BoardState;
  selectedCard?: string | null;
  selectedKind?: SelectedKind | null;
  myTeam?: number | null;
  onCellClick?: (row: number, col: number) => void;
}) {
  return (
    <div
      className="grid h-full w-full grid-cols-10 grid-rows-10 gap-[3px] rounded-2xl border border-line/60 bg-surface p-[6px]"
      style={{
        aspectRatio: "50 / 70",
      }}
    >
      {BOARD_LAYOUT.flatMap((row, r) =>
        row.map((card, c) => {
          const chip = state?.[r]?.[c] ?? EMPTY_CELL;
          const empty = chip.team === null;
          const protectedChip = chip.sequence_ids.length > 0;
          // Highlight rules:
          //   - two-eyed jack: every empty non-corner cell
          //   - one-eyed jack: any opponent chip not in a completed sequence
          //   - normal card: the two cells whose printed card matches
          const isMatch =
            selectedKind === "two_eyed_jack"
              ? card !== null && empty
              : selectedKind === "one_eyed_jack"
                ? card !== null &&
                  !empty &&
                  chip.team !== myTeam &&
                  !protectedChip
                : selectedCard != null &&
                  card === selectedCard &&
                  empty;
          return (
            <Cell
              key={`${r}-${c}`}
              card={card}
              chip={chip}
              row={r}
              col={c}
              isMatch={isMatch}
              onClick={
                isMatch && onCellClick ? () => onCellClick(r, c) : undefined
              }
            />
          );
        }),
      )}
    </div>
  );
}

function Cell({
  card,
  chip,
  row,
  col,
  isMatch,
  onClick,
}: {
  card: BoardCard;
  chip: BoardCell;
  row: number;
  col: number;
  isMatch: boolean;
  onClick?: () => void;
}) {
  const wild = card === null;
  return (
    <div
      className={`relative rounded-[6px] ${onClick ? "cursor-pointer" : ""} ${isMatch ? "animate-[pulse_1.4s_ease-in-out_infinite]" : ""}`}
      style={{
        aspectRatio: CELL_ASPECT,
        outline: isMatch ? "2px solid var(--color-pink)" : undefined,
        outlineOffset: isMatch ? 1 : undefined,
        boxShadow: isMatch ? "0 0 14px rgba(255,92,138,0.55)" : undefined,
        zIndex: isMatch ? 5 : undefined,
      }}
      onClick={onClick}
    >
      {wild ? <CornerCell row={row} col={col} /> : <CardFace card={card} />}
      {chip.team !== null && (
        <ChipOverlay team={chip.team} completed={chip.sequence_ids.length > 0} />
      )}
    </div>
  );
}

// The four corner "wild" spaces. On the real board these are a SEQUENCE
// logo circle — playable as wild for any team. Our take: a soft tri-color
// glow (butter / pink / blue — the three colors from the wordmark icon)
// fading into the canvas, with the "SQR" monogram angled diagonally so
// each of the four corners reads outward toward its own corner of the
// board. Each corner ends up with a different rotation — visual variety
// without losing the brand mark.
function CornerCell({ row, col }: { row: number; col: number }) {
  const isTop = row === 0;
  const isLeft = col === 0;
  // Each corner aligns the "SQR" along the diagonal that runs to that
  // corner. Top corners tilt 45° outward; bottom corners flip 180° so the
  // monogram still "points" outward (and reads upside-down to a viewer at
  // the top of the board — intentional, table-game style).
  const rotation = isTop
    ? isLeft
      ? -45
      : 45
    : isLeft
      ? -135
      : 135;
  // Glow positions shift per corner so the brightest color anchors the
  // outermost corner of each cell — top-left starts butter at the
  // top-left, top-right starts butter at the top-right, etc.
  const glow = isTop
    ? isLeft
      ? `
          radial-gradient(circle at 18% 22%, rgba(255,210,63,0.9) 0%, rgba(255,210,63,0) 58%),
          radial-gradient(circle at 82% 30%, rgba(255,92,138,0.85) 0%, rgba(255,92,138,0) 58%),
          radial-gradient(circle at 55% 85%, rgba(91,124,250,0.85) 0%, rgba(91,124,250,0) 58%)
        `
      : `
          radial-gradient(circle at 82% 22%, rgba(255,210,63,0.9) 0%, rgba(255,210,63,0) 58%),
          radial-gradient(circle at 18% 30%, rgba(255,92,138,0.85) 0%, rgba(255,92,138,0) 58%),
          radial-gradient(circle at 45% 85%, rgba(91,124,250,0.85) 0%, rgba(91,124,250,0) 58%)
        `
    : isLeft
      ? `
          radial-gradient(circle at 18% 78%, rgba(255,210,63,0.9) 0%, rgba(255,210,63,0) 58%),
          radial-gradient(circle at 82% 70%, rgba(255,92,138,0.85) 0%, rgba(255,92,138,0) 58%),
          radial-gradient(circle at 55% 15%, rgba(91,124,250,0.85) 0%, rgba(91,124,250,0) 58%)
        `
      : `
          radial-gradient(circle at 82% 78%, rgba(255,210,63,0.9) 0%, rgba(255,210,63,0) 58%),
          radial-gradient(circle at 18% 70%, rgba(255,92,138,0.85) 0%, rgba(255,92,138,0) 58%),
          radial-gradient(circle at 45% 15%, rgba(91,124,250,0.85) 0%, rgba(91,124,250,0) 58%)
        `;
  return (
    <div
      className="relative flex h-full w-full items-center justify-center overflow-hidden rounded-[6px] border border-line/70"
      style={{
        background: `${glow}, var(--color-canvas)`,
      }}
    >
      <span
        className="font-display font-bold leading-none text-ink"
        style={{
          fontSize: "clamp(8px, 1.35vw, 15px)",
          letterSpacing: "0.04em",
          transform: `rotate(${rotation}deg)`,
          textShadow:
            "0 1px 0 rgba(255,244,232,0.9), 0 0 6px rgba(255,244,232,0.7)",
        }}
      >
        SQR
      </span>
    </div>
  );
}

function ChipOverlay({
  team,
  completed,
}: {
  team: number;
  completed: boolean;
}) {
  return (
    <div
      className="absolute left-1/2 top-1/2 rounded-full"
      style={{
        width: "62%",
        aspectRatio: "1",
        background: TEAM_COLOR[team] ?? "var(--color-ink)",
        boxShadow: completed
          ? "0 0 0 2px var(--color-ink), 0 3px 8px rgba(0,0,0,0.3)"
          : "0 2px 6px rgba(0,0,0,0.2), inset 0 -1px 0 rgba(0,0,0,0.1)",
        transform: "translate(-50%, -50%)",
        animation: "chip-drop 440ms cubic-bezier(0.3, 1.55, 0.4, 1)",
      }}
    />
  );
}
