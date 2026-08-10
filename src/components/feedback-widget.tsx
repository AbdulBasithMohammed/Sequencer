"use client";

import { useState, useTransition } from "react";
import { usePathname } from "next/navigation";
import { submitFeedback } from "@/lib/feedback/actions";

const MAX = 1000;

export function FeedbackWidget() {
  const [open, setOpen] = useState(false);
  const [body, setBody] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [sent, setSent] = useState(false);
  const [pending, startTransition] = useTransition();
  const pathname = usePathname();

  const tooShort = body.trim().length < 3;

  function send() {
    setError(null);
    startTransition(async () => {
      const res = await submitFeedback(body.trim(), pathname);
      if (res.error) {
        setError(res.error);
        return;
      }
      setSent(true);
      setBody("");
    });
  }

  function close() {
    setOpen(false);
    // Reset a beat later so the panel doesn't visibly change as it closes.
    setTimeout(() => {
      setSent(false);
      setError(null);
    }, 200);
  }

  if (!open) {
    return (
      <button
        type="button"
        onClick={() => setOpen(true)}
        className="fixed bottom-4 right-4 z-40 rounded-full border border-line bg-surface px-4 py-2.5 text-sm font-medium shadow-lg transition hover:bg-canvas"
        aria-label="Send feedback"
      >
        Feedback
      </button>
    );
  }

  return (
    <div className="fixed bottom-4 right-4 z-40 w-[min(360px,calc(100vw-2rem))] rounded-3xl border border-line bg-surface p-4 shadow-xl">
      <div className="flex items-start justify-between gap-3">
        <h2 className="font-display text-base font-bold">
          {sent ? "Thanks!" : "Send feedback"}
        </h2>
        <button
          type="button"
          onClick={close}
          className="-mr-1 -mt-1 rounded-full px-2 py-1 text-sm text-ink-soft hover:text-ink"
          aria-label="Close"
        >
          ×
        </button>
      </div>

      {sent ? (
        <p className="mt-2 text-sm text-ink-soft">
          Got it — this goes straight to the person building the game.
        </p>
      ) : (
        <>
          <p className="mt-1 text-xs text-ink-soft">
            Bugs, ideas, or anything that felt off.
          </p>

          <textarea
            value={body}
            onChange={(e) => setBody(e.target.value.slice(0, MAX))}
            rows={4}
            maxLength={MAX}
            placeholder="What's on your mind?"
            className="mt-3 w-full resize-none rounded-2xl border border-line bg-canvas px-3 py-2 text-sm outline-none focus:border-ink-soft"
          />

          <div className="mt-2 flex items-center justify-between gap-3">
            <span className="text-[11px] tabular-nums text-ink-soft">
              {body.length}/{MAX}
            </span>
            <button
              type="button"
              onClick={send}
              disabled={pending || tooShort}
              className="rounded-full bg-ink px-4 py-2 text-sm font-medium text-canvas transition disabled:opacity-40"
            >
              {pending ? "Sending…" : "Send"}
            </button>
          </div>

          {error ? (
            <p className="mt-2 text-xs text-ink" role="alert">
              {error}
            </p>
          ) : null}
        </>
      )}
    </div>
  );
}
