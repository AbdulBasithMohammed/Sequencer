"use client";

import { useSyncExternalStore } from "react";

// Browser online/offline as an external store. Server snapshot says
// "online" so SSR/hydration never shows the pill.
function subscribe(onChange: () => void) {
  window.addEventListener("online", onChange);
  window.addEventListener("offline", onChange);
  return () => {
    window.removeEventListener("online", onChange);
    window.removeEventListener("offline", onChange);
  };
}

export function useBrowserOnline(): boolean {
  return useSyncExternalStore(
    subscribe,
    () => navigator.onLine,
    () => true,
  );
}

// Tiny fixed pill shown while the realtime channel (or the network) is
// down. The self-heal paths recover silently; this just makes the blip
// legible so a quiet moment doesn't read as "the game is broken".
export function ConnectionPill({ show }: { show: boolean }) {
  if (!show) return null;
  return (
    <div
      role="status"
      aria-live="polite"
      // mx-auto centering (not -translate-x-1/2): card-enter animates
      // transform, which would override a transform-based centering and
      // make the pill jump sideways while entering.
      className="card-enter fixed inset-x-0 bottom-4 z-50 mx-auto flex w-fit items-center gap-2 rounded-full border border-line bg-canvas px-3.5 py-1.5 text-[12px] font-semibold text-ink shadow-md"
    >
      <span
        aria-hidden
        className="inline-block h-2 w-2 animate-pulse rounded-full"
        style={{ background: "var(--color-butter, #ffd23f)" }}
      />
      Reconnecting…
    </div>
  );
}
