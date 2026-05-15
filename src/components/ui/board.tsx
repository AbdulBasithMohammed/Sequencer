import { Glyph, GLYPHS } from "./glyph";

export type BoardToken = "pink" | "blue" | "butter" | "ink";
export type BoardCell = { token: BoardToken } | null;

const TOKEN_HEX: Record<BoardToken, string> = {
  pink: "#FF5C8A",
  blue: "#5B7CFA",
  butter: "#FFD23F",
  ink: "#1B1530",
};

export function BoardPreview({
  size = 280,
  cells,
  radius = 14,
  gap = 6,
  animateDrop = false,
}: {
  size?: number;
  cells?: BoardCell[];
  radius?: number;
  gap?: number;
  animateDrop?: boolean;
}) {
  const grid = 6;
  const total = grid * grid;
  const tileSize = (size - gap * (grid + 1)) / grid;
  const filled: BoardCell[] = cells ?? Array.from({ length: total }, () => null);

  return (
    <div
      className="relative grid bg-surface"
      style={{
        width: size,
        height: size,
        borderRadius: radius,
        padding: gap,
        gridTemplateColumns: `repeat(${grid}, 1fr)`,
        gridTemplateRows: `repeat(${grid}, 1fr)`,
        gap,
        boxShadow:
          "0 30px 60px -30px rgba(27,21,48,.25), 0 0 0 1px var(--color-line-strong) inset",
      }}
    >
      {filled.map((cell, i) => {
        const glyph = GLYPHS[(i * 3 + Math.floor(i / 6)) % GLYPHS.length];
        const cornerHi =
          i === 0 || i === grid - 1 || i === total - grid || i === total - 1;
        const tileBg = cornerHi ? "var(--color-ink)" : "var(--color-surface)";
        const glyphColor = cornerHi ? "#FFD23F" : "#C9BFA8";

        return (
          <div
            key={i}
            className="relative flex items-center justify-center"
            style={{
              background: tileBg,
              borderRadius: radius * 0.6,
              opacity: cornerHi ? 1 : 0.85,
            }}
          >
            <Glyph
              kind={glyph}
              size={tileSize * 0.42}
              color={glyphColor}
              stroke={1.6}
            />
            {cell && (
              <div
                className="absolute rounded-full"
                style={{
                  inset: tileSize * 0.12,
                  background: TOKEN_HEX[cell.token],
                  boxShadow: "0 4px 0 rgba(27,21,48,0.18)",
                  animation: animateDrop
                    ? `seq-drop .7s ${i * 0.03}s both cubic-bezier(.34,1.56,.64,1)`
                    : undefined,
                }}
              />
            )}
          </div>
        );
      })}
    </div>
  );
}
