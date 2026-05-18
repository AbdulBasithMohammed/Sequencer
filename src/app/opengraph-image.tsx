import { ImageResponse } from "next/og";

// Rendered at request time by Next.js / Vercel's edge runtime.
// Auto-discovered as both og:image and (via twitter-image.tsx
// re-export) the Twitter card.

export const runtime = "edge";
export const alt = "Sequencr — Play Sequence online with friends.";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

// Brand colors (mirrors src/app/globals.css)
const CANVAS = "#FBF1E2";
const INK = "#1B1530";
const INK_SOFT = "#6E6883";
const PINK = "#FF5C8A";
const BLUE = "#5B7CFA";
const MINT = "#7BD8B5";
const BUTTER = "#FFD23F";

export default async function OpenGraphImage() {
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          background: CANVAS,
          display: "flex",
          flexDirection: "column",
          justifyContent: "space-between",
          padding: 64,
          fontFamily: "ui-sans-serif, system-ui, -apple-system, sans-serif",
          color: INK,
          position: "relative",
        }}
      >
        {/* Soft radial bloom in the background */}
        <div
          style={{
            position: "absolute",
            top: 0,
            right: 0,
            width: 700,
            height: 700,
            background:
              "radial-gradient(circle at 70% 30%, rgba(255,210,63,0.45), rgba(255,92,138,0.18) 50%, rgba(0,0,0,0) 70%)",
            display: "flex",
          }}
        />

        {/* Top row: wordmark + suit corner */}
        <div
          style={{
            display: "flex",
            alignItems: "center",
            justifyContent: "space-between",
            width: "100%",
            zIndex: 1,
          }}
        >
          <div style={{ display: "flex", alignItems: "center", gap: 18 }}>
            {/* Tiny stacked cards */}
            <div style={{ display: "flex", position: "relative", width: 88, height: 96 }}>
              <div
                style={{
                  position: "absolute",
                  left: 0,
                  top: 12,
                  width: 56,
                  height: 80,
                  borderRadius: 10,
                  background: "#FFF",
                  border: `3px solid ${INK}`,
                  transform: "rotate(-10deg)",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  fontSize: 36,
                  color: BLUE,
                }}
              >
                ♦
              </div>
              <div
                style={{
                  position: "absolute",
                  left: 32,
                  top: 8,
                  width: 56,
                  height: 80,
                  borderRadius: 10,
                  background: "#FFF",
                  border: `3px solid ${INK}`,
                  transform: "rotate(8deg)",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  fontSize: 36,
                  color: PINK,
                }}
              >
                ♥
              </div>
            </div>
            <span
              style={{
                fontSize: 60,
                fontWeight: 800,
                letterSpacing: "-0.04em",
              }}
            >
              sequencr
            </span>
          </div>

          {/* Suit cluster top-right */}
          <div
            style={{
              display: "flex",
              gap: 22,
              alignItems: "center",
              fontSize: 56,
            }}
          >
            <span style={{ color: INK, transform: "rotate(-8deg)", display: "flex" }}>♠</span>
            <span style={{ color: PINK, transform: "rotate(6deg)", display: "flex" }}>♥</span>
            <span style={{ color: BLUE, transform: "rotate(-4deg)", display: "flex" }}>♦</span>
            <span style={{ color: MINT, transform: "rotate(10deg)", display: "flex" }}>♣</span>
          </div>
        </div>

        {/* Headline */}
        <div
          style={{
            display: "flex",
            flexDirection: "column",
            zIndex: 1,
          }}
        >
          <span
            style={{
              fontSize: 124,
              fontWeight: 800,
              lineHeight: 0.95,
              letterSpacing: "-0.04em",
            }}
          >
            Play Sequence
          </span>
          <span
            style={{
              fontSize: 124,
              fontWeight: 800,
              fontStyle: "italic",
              color: PINK,
              lineHeight: 0.95,
              letterSpacing: "-0.04em",
            }}
          >
            online.
          </span>
        </div>

        {/* Bottom row: chips + meta */}
        <div
          style={{
            display: "flex",
            justifyContent: "space-between",
            alignItems: "center",
            width: "100%",
            zIndex: 1,
          }}
        >
          <div style={{ display: "flex", alignItems: "center", gap: 14 }}>
            {[PINK, BLUE, MINT, BUTTER].map((c) => (
              <div
                key={c}
                style={{
                  display: "flex",
                  width: 36,
                  height: 36,
                  borderRadius: 18,
                  background: c,
                  boxShadow: `0 4px 0 rgba(0,0,0,0.12)`,
                }}
              />
            ))}
            <span
              style={{
                marginLeft: 14,
                fontSize: 26,
                color: INK_SOFT,
                fontWeight: 600,
              }}
            >
              Free · 2–12 players · 5 in a row to win
            </span>
          </div>

          <span
            style={{
              fontSize: 28,
              fontWeight: 800,
              letterSpacing: "0.02em",
              color: INK,
            }}
          >
            sequencr.app
          </span>
        </div>
      </div>
    ),
    { ...size },
  );
}
