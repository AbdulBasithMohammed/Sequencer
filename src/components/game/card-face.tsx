import { parseCard } from "@/lib/board-layout";

// Renders one playing card face the way a real card looks: small rank+suit
// in the top-left + bottom-right (rotated) corners, and the canonical pip
// pattern in the middle. Face cards (Q, K) show a big rank letter with a
// suit indicator. Aces show a single large center pip. Jacks never appear
// on the board.
//
// Pip positions are percentages of the card face. Cards are rendered in
// 5:7 aspect cells so absolute % positioning translates cleanly.

type PipPos = { x: number; y: number; flip?: boolean };

const PIP_LAYOUT: Record<string, PipPos[]> = {
  A: [{ x: 50, y: 50 }],
  "2": [
    { x: 50, y: 22 },
    { x: 50, y: 78, flip: true },
  ],
  "3": [
    { x: 50, y: 22 },
    { x: 50, y: 50 },
    { x: 50, y: 78, flip: true },
  ],
  "4": [
    { x: 28, y: 22 },
    { x: 72, y: 22 },
    { x: 28, y: 78, flip: true },
    { x: 72, y: 78, flip: true },
  ],
  "5": [
    { x: 28, y: 22 },
    { x: 72, y: 22 },
    { x: 50, y: 50 },
    { x: 28, y: 78, flip: true },
    { x: 72, y: 78, flip: true },
  ],
  "6": [
    { x: 28, y: 22 },
    { x: 72, y: 22 },
    { x: 28, y: 50 },
    { x: 72, y: 50 },
    { x: 28, y: 78, flip: true },
    { x: 72, y: 78, flip: true },
  ],
  "7": [
    { x: 28, y: 22 },
    { x: 72, y: 22 },
    { x: 50, y: 36 },
    { x: 28, y: 50 },
    { x: 72, y: 50 },
    { x: 28, y: 78, flip: true },
    { x: 72, y: 78, flip: true },
  ],
  "8": [
    { x: 28, y: 22 },
    { x: 72, y: 22 },
    { x: 50, y: 36 },
    { x: 28, y: 50 },
    { x: 72, y: 50 },
    { x: 50, y: 64, flip: true },
    { x: 28, y: 78, flip: true },
    { x: 72, y: 78, flip: true },
  ],
  "9": [
    { x: 28, y: 20 },
    { x: 72, y: 20 },
    { x: 28, y: 38 },
    { x: 72, y: 38 },
    { x: 50, y: 50 },
    { x: 28, y: 62, flip: true },
    { x: 72, y: 62, flip: true },
    { x: 28, y: 80, flip: true },
    { x: 72, y: 80, flip: true },
  ],
  "10": [
    { x: 28, y: 18 },
    { x: 72, y: 18 },
    { x: 50, y: 30 },
    { x: 28, y: 42 },
    { x: 72, y: 42 },
    { x: 28, y: 58, flip: true },
    { x: 72, y: 58, flip: true },
    { x: 50, y: 70, flip: true },
    { x: 28, y: 82, flip: true },
    { x: 72, y: 82, flip: true },
  ],
};

const FACE_RANKS = new Set(["J", "Q", "K"]);

export function CardFace({ card }: { card: string }) {
  const parts = parseCard(card);
  const color = parts.color === "red" ? "#E5476B" : "var(--color-ink)";
  const isFace = FACE_RANKS.has(parts.rank);
  const pips = PIP_LAYOUT[parts.rank];

  return (
    <div
      className="relative h-full w-full overflow-hidden rounded-[6px] border border-line/60 bg-white"
      style={{ color }}
    >
      <CornerLabel rank={parts.rank} symbol={parts.symbol} position="tl" />
      <CornerLabel rank={parts.rank} symbol={parts.symbol} position="br" />

      {isFace ? (
        <FaceCenter rank={parts.rank} />
      ) : (
        pips?.map((p, i) => (
          <Pip key={i} x={p.x} y={p.y} symbol={parts.symbol} flip={p.flip} />
        ))
      )}
    </div>
  );
}

function CornerLabel({
  rank,
  symbol,
  position,
}: {
  rank: string;
  symbol: string;
  position: "tl" | "br";
}) {
  const tl = position === "tl";
  return (
    <div
      className="absolute flex flex-col items-center leading-[0.95]"
      style={{
        top: tl ? "4%" : undefined,
        left: tl ? "6%" : undefined,
        bottom: tl ? undefined : "4%",
        right: tl ? undefined : "6%",
        transform: tl ? undefined : "rotate(180deg)",
        fontSize: "clamp(6px, 0.95vw, 10px)",
        fontWeight: 700,
      }}
    >
      <span>{rank}</span>
      <span style={{ fontSize: "0.95em", marginTop: "0.5px" }}>{symbol}</span>
    </div>
  );
}

function Pip({
  x,
  y,
  symbol,
  flip,
}: {
  x: number;
  y: number;
  symbol: string;
  flip?: boolean;
}) {
  return (
    <span
      className="absolute leading-none"
      style={{
        left: `${x}%`,
        top: `${y}%`,
        transform: `translate(-50%, -50%) ${flip ? "rotate(180deg)" : ""}`,
        fontSize: "clamp(8px, 1.55vw, 16px)",
      }}
    >
      {symbol}
    </span>
  );
}

function FaceCenter({ rank }: { rank: string }) {
  return (
    <div className="absolute inset-0 flex items-center justify-center leading-[1]">
      <span
        style={{
          fontFamily:
            'Georgia, "Times New Roman", "DM Serif Display", "Hoefler Text", serif',
          fontWeight: 700,
          fontSize: "clamp(16px, 2.9vw, 30px)",
        }}
      >
        {rank}
      </span>
    </div>
  );
}
