"use client";

import { useEffect, useState, useTransition } from "react";
import { usePathname } from "next/navigation";
import { submitFeedback } from "@/lib/feedback/actions";

const MAX = 1000;

// Lives in the sidebar rather than floating over the page. A fixed
// bottom-right button covered real content on mobile, where the viewport
// is short and the game board already reaches the bottom edge. Sitting in
// the nav means it can never overlap anything and it's in the same place
// on both layouts.
//
// The panel itself is a modal: a bottom sheet on small screens, centred
// on larger ones.
export function FeedbackWidget({ onOpen }: { onOpen?: () => void }) {
  const [open, setOpen] = useState(false);
  const [body, setBody] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [sent, setSent] = useState(false);
  const [pending, startTransition] = useTransition();
  const pathname = usePathname();

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") setOpen(false);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open]);

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

  return (
    <>
      <button
        type="button"
        onClick={() => {
          setOpen(true);
          onOpen?.();
        }}
        className="w-full rounded-xl border border-line bg-canvas px-3 py-2 text-[12px] font-semibold text-ink-soft transition-colors hover:bg-line/60 hover:text-ink"
      >
        Send feedback
      </button>

      {open ? (
        <div
          className="fixed inset-0 z-50 flex items-end justify-center bg-ink/30 p-4 sm:items-center"
          onClick={close}
          role="dialog"
          aria-modal="true"
          aria-label="Send feedback"
        >
          <div
            className="w-full max-w-md rounded-3xl border border-line bg-surface p-5 shadow-xl"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-start justify-between gap-3">
              <h2 className="font-display text-base font-bold">
                {sent ? "Thanks!" : "Send feedback"}
              </h2>
              <button
                type="button"
                onClick={close}
                className="-mr-1 -mt-1 rounded-full px-2 py-1 text-lg leading-none text-ink-soft hover:text-ink"
                aria-label="Close"
              >
                ×
              </button>
            </div>

            {sent ? (
              <>
                <p className="mt-2 text-sm text-ink-soft">
                  Got it — this goes straight to the person building the game.
                </p>
                <button
                  type="button"
                  onClick={close}
                  className="mt-4 w-full rounded-full bg-ink px-4 py-2.5 text-sm font-medium text-canvas"
                >
                  Done
                </button>
              </>
            ) : (
              <>
                <p className="mt-1 text-xs text-ink-soft">
                  Bugs, ideas, or anything that felt off.
                </p>

                <textarea
                  autoFocus
                  value={body}
                  onChange={(e) => setBody(e.target.value.slice(0, MAX))}
                  rows={5}
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
                    className="rounded-full bg-ink px-5 py-2 text-sm font-medium text-canvas transition disabled:opacity-40"
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
        </div>
      ) : null}
    </>
  );
}
