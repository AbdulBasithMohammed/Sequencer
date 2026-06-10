"use client";

import { useSyncExternalStore } from "react";

const STORAGE_KEY = "sequencr.sound.muted";

export function isMuted(): boolean {
  if (typeof window === "undefined") return false;
  try {
    return window.localStorage.getItem(STORAGE_KEY) === "1";
  } catch {
    return false;
  }
}

// localStorage as an external store: cross-tab changes arrive via real
// storage events; same-tab toggles dispatch a synthetic one (below), which
// also feeds the in-game sound hook.
function subscribe(onChange: () => void) {
  const onStorage = (e: StorageEvent) => {
    if (e.key === STORAGE_KEY) onChange();
  };
  window.addEventListener("storage", onStorage);
  return () => window.removeEventListener("storage", onStorage);
}

function getSnapshot(): boolean | null {
  return isMuted();
}

// null = "not on the client yet" → render the fixed-size placeholder
// during SSR/hydration so there's no flicker; React swaps in the real
// snapshot right after hydration.
function getServerSnapshot(): boolean | null {
  return null;
}

export function MuteToggle() {
  const muted = useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot);

  function toggle() {
    const next = !(muted ?? false);
    try {
      window.localStorage.setItem(STORAGE_KEY, next ? "1" : "0");
      // Tell other tabs (and the in-page sound hook) about the change.
      window.dispatchEvent(
        new StorageEvent("storage", {
          key: STORAGE_KEY,
          newValue: next ? "1" : "0",
        }),
      );
    } catch {
      /* ignore */
    }
  }

  if (muted === null) {
    return (
      <span
        aria-hidden
        className="inline-block h-8 w-8 rounded-full"
      />
    );
  }

  return (
    <button
      type="button"
      onClick={toggle}
      aria-pressed={muted}
      title={muted ? "Sound off — tap to enable" : "Sound on — tap to mute"}
      className="inline-flex h-8 w-8 items-center justify-center rounded-full border border-line bg-surface text-ink-soft transition-colors hover:text-ink"
    >
      <svg
        viewBox="0 0 24 24"
        width={16}
        height={16}
        aria-hidden
        focusable="false"
      >
        {muted ? (
          <>
            <path
              d="M4 10v4h3l4 3V7L7 10H4Z"
              fill="currentColor"
            />
            <path
              d="M15 9l5 5M20 9l-5 5"
              stroke="currentColor"
              strokeWidth="1.6"
              strokeLinecap="round"
              fill="none"
            />
          </>
        ) : (
          <>
            <path
              d="M4 10v4h3l4 3V7L7 10H4Z"
              fill="currentColor"
            />
            <path
              d="M14.5 9a4 4 0 0 1 0 6M16.8 7a7 7 0 0 1 0 10"
              stroke="currentColor"
              strokeWidth="1.6"
              strokeLinecap="round"
              fill="none"
            />
          </>
        )}
      </svg>
    </button>
  );
}
