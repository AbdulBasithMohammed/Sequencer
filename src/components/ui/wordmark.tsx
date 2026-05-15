type TokenColor = "pink" | "blue" | "butter" | "mint";

const TOKEN_HEX: Record<TokenColor, string> = {
  pink: "#FF5C8A",
  blue: "#5B7CFA",
  butter: "#FFD23F",
  mint: "#7BD8B5",
};

export function Wordmark({
  size = 26,
  color = "var(--color-ink)",
  accent = "pink",
}: {
  size?: number;
  color?: string;
  accent?: TokenColor | string;
}) {
  const accentHex =
    accent in TOKEN_HEX ? TOKEN_HEX[accent as TokenColor] : (accent as string);

  return (
    <span
      className="inline-flex items-center font-display font-bold leading-none"
      style={{
        fontSize: size,
        color,
        gap: size * 0.18,
        letterSpacing: "-0.02em",
      }}
    >
      <span
        aria-hidden
        className="relative inline-block rounded-full"
        style={{
          width: size * 0.9,
          height: size * 0.9,
          background: accentHex,
        }}
      >
        <span
          className="absolute rounded-full"
          style={{
            inset: size * 0.18,
            border: `${Math.max(2, size * 0.08)}px solid ${color}`,
          }}
        />
      </span>
      <span>sequencer</span>
    </span>
  );
}
