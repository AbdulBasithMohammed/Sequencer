export type GlyphKind =
  | "dot"
  | "tri"
  | "sq"
  | "hex"
  | "star"
  | "ring"
  | "bar"
  | "diam";

export const GLYPHS: GlyphKind[] = [
  "dot",
  "tri",
  "sq",
  "hex",
  "star",
  "ring",
  "bar",
  "diam",
];

export function Glyph({
  kind,
  color = "currentColor",
  size = 18,
  stroke = 2,
}: {
  kind: GlyphKind;
  color?: string;
  size?: number;
  stroke?: number;
}) {
  switch (kind) {
    case "dot":
      return (
        <svg width={size} height={size} viewBox="0 0 24 24">
          <circle cx="12" cy="12" r="5" fill={color} />
        </svg>
      );
    case "tri":
      return (
        <svg width={size} height={size} viewBox="0 0 24 24">
          <polygon
            points="12,4 21,20 3,20"
            fill="none"
            stroke={color}
            strokeWidth={stroke}
            strokeLinejoin="round"
          />
        </svg>
      );
    case "sq":
      return (
        <svg width={size} height={size} viewBox="0 0 24 24">
          <rect
            x="5"
            y="5"
            width="14"
            height="14"
            rx="2"
            fill="none"
            stroke={color}
            strokeWidth={stroke}
          />
        </svg>
      );
    case "hex":
      return (
        <svg width={size} height={size} viewBox="0 0 24 24">
          <polygon points="12,3 21,8 21,16 12,21 3,16 3,8" fill={color} />
        </svg>
      );
    case "star":
      return (
        <svg width={size} height={size} viewBox="0 0 24 24">
          <polygon
            points="12,3 14.5,9.5 21,10 16,14.5 17.5,21 12,17.5 6.5,21 8,14.5 3,10 9.5,9.5"
            fill={color}
          />
        </svg>
      );
    case "ring":
      return (
        <svg width={size} height={size} viewBox="0 0 24 24">
          <circle
            cx="12"
            cy="12"
            r="6"
            fill="none"
            stroke={color}
            strokeWidth={stroke}
          />
        </svg>
      );
    case "bar":
      return (
        <svg width={size} height={size} viewBox="0 0 24 24">
          <rect x="4" y="10.5" width="16" height="3" rx="1.5" fill={color} />
        </svg>
      );
    case "diam":
      return (
        <svg width={size} height={size} viewBox="0 0 24 24">
          <polygon
            points="12,3 21,12 12,21 3,12"
            fill="none"
            stroke={color}
            strokeWidth={stroke}
          />
        </svg>
      );
  }
}
