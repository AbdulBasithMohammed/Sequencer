"use client";

import { useRef, type PointerEvent, type ReactNode } from "react";

// Pinch-zoom + drag-pan wrapper for the board on touch devices. Single
// pointer pans (only when zoomed in); two pointers pinch-zoom with the
// midpoint anchored. Scale clamps to [1, 3]. Transform applied imperatively
// on a ref to avoid per-frame re-renders.

type Pt = { x: number; y: number };

export function BoardPanZoom({ children }: { children: ReactNode }) {
  const innerRef = useRef<HTMLDivElement>(null);
  const transformRef = useRef({ scale: 1, tx: 0, ty: 0 });
  const pointersRef = useRef(new Map<number, Pt>());
  const lastPinchRef = useRef<{ dist: number; mid: Pt } | null>(null);

  function apply() {
    const { scale, tx, ty } = transformRef.current;
    if (innerRef.current) {
      innerRef.current.style.transform = `translate(${tx}px, ${ty}px) scale(${scale})`;
    }
  }

  function onPointerDown(e: PointerEvent<HTMLDivElement>) {
    // Pan / pinch is touch-only. On desktop the cards are already big enough
    // and the mouse path needs to deliver clean clicks to children — calling
    // setPointerCapture on a mouse pointer redirects the synthesized click
    // event to this wrapper and swallows the cell's onClick.
    if (e.pointerType !== "touch") return;
    e.currentTarget.setPointerCapture(e.pointerId);
    pointersRef.current.set(e.pointerId, { x: e.clientX, y: e.clientY });
    if (pointersRef.current.size === 2) {
      const [a, b] = [...pointersRef.current.values()];
      lastPinchRef.current = {
        dist: Math.hypot(a.x - b.x, a.y - b.y),
        mid: { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 },
      };
    }
  }

  function onPointerMove(e: PointerEvent<HTMLDivElement>) {
    if (e.pointerType !== "touch") return;
    const prev = pointersRef.current.get(e.pointerId);
    if (!prev) return;
    const next = { x: e.clientX, y: e.clientY };
    pointersRef.current.set(e.pointerId, next);

    const t = transformRef.current;

    if (pointersRef.current.size === 1) {
      if (t.scale > 1) {
        t.tx += next.x - prev.x;
        t.ty += next.y - prev.y;
        apply();
      }
    } else if (pointersRef.current.size === 2 && lastPinchRef.current) {
      const arr = [...pointersRef.current.values()];
      const a = arr[0];
      const b = arr[1];
      const dist = Math.hypot(a.x - b.x, a.y - b.y);
      const mid = { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 };
      const last = lastPinchRef.current;
      const ratio = dist / last.dist;
      const newScale = Math.min(3, Math.max(1, t.scale * ratio));
      const sFactor = newScale / t.scale;
      t.tx = mid.x - (last.mid.x - t.tx) * sFactor;
      t.ty = mid.y - (last.mid.y - t.ty) * sFactor;
      t.scale = newScale;
      if (newScale === 1) {
        t.tx = 0;
        t.ty = 0;
      }
      apply();
      lastPinchRef.current = { dist, mid };
    }
  }

  function onPointerUp(e: PointerEvent<HTMLDivElement>) {
    if (e.pointerType !== "touch") return;
    pointersRef.current.delete(e.pointerId);
    if (pointersRef.current.size < 2) lastPinchRef.current = null;
  }

  function reset() {
    transformRef.current = { scale: 1, tx: 0, ty: 0 };
    apply();
  }

  return (
    <div className="relative">
      <div
        className="overflow-hidden"
        onPointerDown={onPointerDown}
        onPointerMove={onPointerMove}
        onPointerUp={onPointerUp}
        onPointerCancel={onPointerUp}
        style={{ touchAction: "none" }}
      >
        <div
          ref={innerRef}
          style={{
            transformOrigin: "0 0",
            willChange: "transform",
          }}
        >
          {children}
        </div>
      </div>
      <button
        type="button"
        onClick={reset}
        className="absolute right-2 top-2 rounded-full border border-line/60 bg-canvas/90 px-3 py-1 text-[11px] font-semibold text-ink-soft shadow-sm md:hidden"
        aria-label="Reset zoom"
      >
        Reset
      </button>
    </div>
  );
}
