"use client";

import { useEffect, useState } from "react";

const QUOTES: { text: string; author: string }[] = [
  {
    text: "We don't stop playing because we grow old; we grow old because we stop playing.",
    author: "George Bernard Shaw",
  },
  {
    text: "A game is a series of interesting choices.",
    author: "Sid Meier",
  },
  {
    text: "You can discover more about a person in an hour of play than in a year of conversation.",
    author: "Plato",
  },
  {
    text: "Friends are the family you choose.",
    author: "Jess C. Scott",
  },
  {
    text: "The best mirror is an old friend.",
    author: "George Herbert",
  },
  {
    text: "Family is not an important thing. It's everything.",
    author: "Michael J. Fox",
  },
];

const CYCLE_MS = 8000;
const FADE_MS = 400;

export function QuoteCycler() {
  // Initial render must match server (always 0). After mount we jump to a
  // random quote so each session starts fresh without a hydration mismatch.
  const [idx, setIdx] = useState(0);
  const [visible, setVisible] = useState(true);

  useEffect(() => {
    // Random jump deferred a tick so the hydration pass still renders
    // quote 0 (matching the server) before each session starts fresh.
    const startTimer = window.setTimeout(() => {
      setIdx(Math.floor(Math.random() * QUOTES.length));
    }, 0);
    let fadeTimer: number | undefined;
    const interval = window.setInterval(() => {
      setVisible(false);
      fadeTimer = window.setTimeout(() => {
        setIdx((i) => (i + 1) % QUOTES.length);
        setVisible(true);
      }, FADE_MS);
    }, CYCLE_MS);
    return () => {
      window.clearTimeout(startTimer);
      window.clearInterval(interval);
      if (fadeTimer !== undefined) window.clearTimeout(fadeTimer);
    };
  }, []);

  const q = QUOTES[idx];

  return (
    <div
      className="text-ink transition-opacity"
      style={{
        opacity: visible ? 1 : 0,
        transitionDuration: `${FADE_MS}ms`,
      }}
    >
      <div
        className="font-display font-semibold italic"
        style={{
          fontSize: 22,
          letterSpacing: "-0.02em",
          lineHeight: 1.25,
        }}
      >
        &ldquo;{q.text}&rdquo;
      </div>
      <div
        className="mt-3 opacity-80"
        style={{
          fontFamily: "var(--font-body)",
          fontWeight: 500,
          fontSize: 13,
        }}
      >
        — {q.author}
      </div>
    </div>
  );
}
