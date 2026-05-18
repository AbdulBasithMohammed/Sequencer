"use client";

import {
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
  type CSSProperties,
} from "react";
import { CardFace } from "./card-face";

// Fanned face-up hand of cards. Hover/select lifts a card forward.
// Animations:
//   - card-burn: when the parent flags burningIdx, that card flashes pink
//     and shrinks/fades out (the chip going onto the board)
//   - card-deal: when a brand-new card appears in the hand (not in the
//     previous render), it flies in from the right at a tilt (a freshly
//     dealt replacement off the deck)
// CSS keyframes live in globals.css and read CSS variables exposed inline
// so the fan transform composes with the animation.

const CARD_WIDTH = 78;
const SPACING = 46;
const ANGLE_STEP = 8;
const ARC_DROP = 4;
const NEIGHBOR_PUSH_1 = 8;
const NEIGHBOR_PUSH_2 = 3;
const HOVER_LIFT = 20;
const HOVER_SCALE = 1.16;
const BURN_DURATION_MS = 540;
const DEAL_DURATION_MS = 520;

// Hand-tuned ember positions inside the card. Each one flies upward with
// a slight horizontal drift, scales down, and fades — small visual cue
// reinforcing that the card is on fire.
const EMBERS: Array<{
  left: string;
  top: string;
  size: number;
  color: "pink" | "butter";
  drift: number;
  delay: number;
}> = [
  { left: "22%", top: "70%", size: 4, color: "pink", drift: -14, delay: 0 },
  { left: "44%", top: "58%", size: 5, color: "butter", drift: 3, delay: 60 },
  { left: "66%", top: "74%", size: 4, color: "pink", drift: 12, delay: 120 },
  { left: "32%", top: "46%", size: 3, color: "butter", drift: -6, delay: 180 },
  { left: "58%", top: "38%", size: 4, color: "pink", drift: 8, delay: 220 },
  { left: "50%", top: "26%", size: 3, color: "butter", drift: -10, delay: 260 },
];

export function HandStrip({
  cards,
  selectedIdx,
  onSelect,
  disabled,
  burningIdx,
}: {
  cards: string[];
  selectedIdx?: number | null;
  onSelect?: (idx: number) => void;
  disabled?: boolean;
  burningIdx?: number | null;
}) {
  const [hovered, setHovered] = useState<number | null>(null);
  const [dealIdx, setDealIdx] = useState<number | null>(null);
  const [scale, setScale] = useState(1);
  const prevCardsRef = useRef<string[] | null>(null);
  const sizerRef = useRef<HTMLDivElement | null>(null);

  // Natural fan width (cards at full size) must fit the available *layout*
  // width — measured from a parent box, not the viewport. Using
  // window.innerWidth made the fan re-scale during iOS pinch-zoom; a
  // ResizeObserver on our own container only fires when the actual
  // layout box changes, so the hand stays put when users zoom in/out.
  useLayoutEffect(() => {
    const el = sizerRef.current;
    if (!el) return;
    const natural = (cards.length - 1) * SPACING + CARD_WIDTH + 140;
    function update(width: number) {
      const available = Math.max(0, width - 16);
      setScale(Math.min(1, available / natural));
    }
    update(el.clientWidth);
    const ro = new ResizeObserver((entries) => {
      const w = entries[0]?.contentRect.width ?? el.clientWidth;
      update(w);
    });
    ro.observe(el);
    return () => ro.disconnect();
  }, [cards.length]);

  // Detect a newly drawn card. The hand has the played card removed and a
  // replacement appended at the end; we diff against the previous render
  // via a multi-set so it survives duplicates.
  useEffect(() => {
    const prev = prevCardsRef.current;
    prevCardsRef.current = cards;
    if (prev === null) return; // initial mount — no animation

    const counts: Record<string, number> = {};
    for (const c of prev) counts[c] = (counts[c] ?? 0) + 1;
    let newIdx: number | null = null;
    for (let i = 0; i < cards.length; i++) {
      const c = cards[i];
      const n = counts[c] ?? 0;
      if (n > 0) {
        counts[c] = n - 1;
      } else {
        newIdx = i;
        break;
      }
    }
    if (newIdx !== null) {
      setDealIdx(newIdx);
      const t = window.setTimeout(() => setDealIdx(null), DEAL_DURATION_MS);
      return () => window.clearTimeout(t);
    }
  }, [cards]);

  if (cards.length === 0) {
    return (
      <div className="text-center text-[12px] text-ink-soft">
        No cards in hand yet.
      </div>
    );
  }

  const center = (cards.length - 1) / 2;
  const cardHeight = (CARD_WIDTH * 7) / 5;
  const maxRotRad = (Math.abs(center) * ANGLE_STEP * Math.PI) / 180;
  const rotatedBottomDrop = Math.ceil((CARD_WIDTH / 2) * Math.sin(maxRotRad));
  const bottomAnchor = rotatedBottomDrop + 16;
  const containerWidth =
    (cards.length - 1) * SPACING + CARD_WIDTH + 140;
  const containerHeight = cardHeight + bottomAnchor + 60;

  const activeIdx = selectedIdx ?? hovered;

  return (
    <div
      ref={sizerRef}
      className={`w-full overflow-hidden pt-5 ${disabled ? "opacity-60" : ""}`}
    >
      <div
        className="mx-auto"
        style={{
          width: containerWidth * scale,
          height: containerHeight * scale,
        }}
      >
      <div
        className="relative origin-top-left"
        style={{
          width: containerWidth,
          height: containerHeight,
          transform: `scale(${scale})`,
          pointerEvents: disabled ? "none" : undefined,
        }}
        onMouseLeave={() => setHovered(null)}
      >
        {cards.map((card, i) => {
          const offset = i - center;
          const isActive = activeIdx === i;
          const isSelected = selectedIdx === i;
          const isBurning = burningIdx === i;
          const isDealing = dealIdx === i;
          const fanRot = offset * ANGLE_STEP;
          const fanDx = offset * SPACING;
          const fanDy = Math.abs(offset) * ARC_DROP;

          let pushDx = 0;
          if (activeIdx !== null && activeIdx !== undefined && !isActive) {
            const dist = i - activeIdx;
            const absDist = Math.abs(dist);
            if (absDist === 1) pushDx = Math.sign(dist) * NEIGHBOR_PUSH_1;
            else if (absDist === 2) pushDx = Math.sign(dist) * NEIGHBOR_PUSH_2;
          }

          // The burning card stays where it was when selected — popped
          // forward, straightened, lifted. Otherwise the burn animation
          // would snap it back into the fan on frame 0 and the dissolve
          // would feel disconnected from the click.
          const inPoppedPosition = isActive || isBurning;
          const rot = inPoppedPosition ? 0 : fanRot;
          const dx = fanDx + pushDx;
          const dy = inPoppedPosition ? -HOVER_LIFT : fanDy;
          const scale = inPoppedPosition ? HOVER_SCALE : 1;

          const cssVars = {
            "--tx": `${dx}px`,
            "--ty": `${dy}px`,
            "--rot": `${rot}deg`,
            "--scale": scale,
          } as CSSProperties;

          const animation = isBurning
            ? `card-burn ${BURN_DURATION_MS}ms ease-in forwards`
            : isDealing
              ? `card-deal ${DEAL_DURATION_MS}ms cubic-bezier(0.25, 1.3, 0.4, 1) both`
              : undefined;

          return (
            <div
              key={`${card}-${i}`}
              className="absolute left-1/2 cursor-pointer transition-all duration-300 ease-out"
              style={{
                ...cssVars,
                bottom: bottomAnchor,
                marginLeft: -CARD_WIDTH / 2,
                transform: `translate(${dx}px, ${dy}px) rotate(${rot}deg) scale(${scale})`,
                transformOrigin: "50% 100%",
                zIndex: isBurning ? 200 : isActive ? 100 : i,
                animation,
              }}
              onMouseEnter={() => setHovered(i)}
              onClick={onSelect && !isBurning ? () => onSelect(i) : undefined}
            >
              <div
                className="relative rounded-[8px] bg-white transition-shadow duration-300 ease-out"
                style={{
                  width: CARD_WIDTH,
                  aspectRatio: "5 / 7",
                  boxShadow: isSelected
                    ? "0 0 0 2px var(--color-pink), 0 12px 26px rgba(255,92,138,0.35)"
                    : isActive
                      ? "0 10px 22px rgba(0,0,0,0.2)"
                      : "0 2px 8px rgba(0,0,0,0.12)",
                }}
              >
                <CardFace card={card} />
                {isBurning ? (
                  <div className="pointer-events-none absolute inset-0 overflow-visible">
                    {EMBERS.map((e, k) => (
                      <span
                        key={k}
                        className="absolute rounded-full"
                        style={{
                          left: e.left,
                          top: e.top,
                          width: e.size,
                          height: e.size,
                          background:
                            e.color === "pink"
                              ? "var(--color-pink)"
                              : "var(--color-butter)",
                          boxShadow:
                            e.color === "pink"
                              ? "0 0 8px var(--color-pink)"
                              : "0 0 8px var(--color-butter)",
                          animation: `ember ${BURN_DURATION_MS}ms ease-out forwards`,
                          animationDelay: `${e.delay}ms`,
                          ["--ex" as string]: `${e.drift}px`,
                        } as CSSProperties}
                      />
                    ))}
                  </div>
                ) : null}
              </div>
            </div>
          );
        })}
      </div>
      </div>
    </div>
  );
}
