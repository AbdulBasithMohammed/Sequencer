"use client";

import { useEffect, useState, useTransition } from "react";
import { usePathname } from "next/navigation";
import {
  getMyFeedback,
  markFeedbackRepliesSeen,
  submitFeedback,
  type MyFeedback,
} from "@/lib/feedback/actions";

const MAX = 1000;

type Tab = "send" | "mine";

// Controlled by the parent on purpose. The mobile nav dropdown is
// conditionally rendered, so anything inside it unmounts the moment the
// menu closes — and opening feedback closes the menu. Owning the open
// state here meant the modal was destroyed in the same tick it was
// created, which is why the button did nothing on mobile and worked on
// desktop, where the sidebar is always mounted.
//
// AppSidebar holds the state and renders this once, outside both
// layouts, so it survives the dropdown unmounting.
//
// Two tabs: Send (the form) and Your feedback (what you sent, with the
// admin's reply under it). Opening Your feedback marks replies seen and
// tells the parent via onRepliesSeen so it can clear the unread dot.
export function FeedbackModal({
  open,
  onClose,
  unread = 0,
  onRepliesSeen,
}: {
  open: boolean;
  onClose: () => void;
  unread?: number;
  onRepliesSeen?: () => void;
}) {
  const [tab, setTab] = useState<Tab>("send");
  const [body, setBody] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [sent, setSent] = useState(false);
  const [parent, setParent] = useState<MyFeedback | null>(null);
  const [mine, setMine] = useState<MyFeedback[] | null>(null);
  const [mineError, setMineError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();
  const [loading, startLoading] = useTransition();
  const pathname = usePathname();

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [open, onClose]);

  // Land on the replies when it opens with something new to read.
  // Adjusted during render (React's "store the previous prop" pattern)
  // rather than in an effect, so there's no flash of the Send tab.
  const [wasOpen, setWasOpen] = useState(open);
  if (open !== wasOpen) {
    setWasOpen(open);
    if (open && unread > 0) setTab("mine");
  }

  // Reset for the next visit once it has closed.
  useEffect(() => {
    if (open) return;
    const t = setTimeout(() => {
      setTab("send");
      setSent(false);
      setError(null);
      setBody("");
      setParent(null);
      setMine(null);
      setMineError(null);
    }, 200);
    return () => clearTimeout(t);
  }, [open]);

  // Load the list whenever the tab is shown, and mark replies read.
  useEffect(() => {
    if (!open || tab !== "mine") return;
    startLoading(async () => {
      const res = await getMyFeedback();
      setMine(res.items);
      setMineError(res.error);
      if (res.items.some((f) => f.reply_body && !f.reply_seen_at)) {
        const seen = await markFeedbackRepliesSeen();
        if (!seen.error) onRepliesSeen?.();
      }
    });
  }, [open, tab, onRepliesSeen]);

  if (!open) return null;

  const tooShort = body.trim().length < 3;

  function send() {
    if (pending) return;
    setError(null);
    startTransition(async () => {
      const res = await submitFeedback(
        body.trim(),
        pathname,
        parent?.id ?? null,
      );
      if (res.error) {
        setError(res.error);
        return;
      }
      setSent(true);
      setBody("");
      setParent(null);
    });
  }

  function replyTo(f: MyFeedback) {
    setParent(f);
    setSent(false);
    setError(null);
    setTab("send");
  }

  const tabs: [Tab, string][] = [
    ["send", "Send"],
    ["mine", "Your feedback"],
  ];

  return (
    <div
      className="fixed inset-0 z-50 flex items-end justify-center bg-ink/30 p-4 sm:items-center"
      onClick={onClose}
      role="dialog"
      aria-modal="true"
      aria-label="Feedback"
    >
      <div
        className="flex max-h-[85vh] w-full max-w-md flex-col rounded-3xl border border-line bg-surface p-5 shadow-xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between gap-3">
          <div className="flex gap-1.5" role="tablist">
            {tabs.map(([id, label]) => (
              <button
                key={id}
                type="button"
                role="tab"
                aria-selected={tab === id}
                onClick={() => setTab(id)}
                className={`relative rounded-full border px-3 py-1 text-xs font-semibold transition-colors ${
                  tab === id
                    ? "border-ink bg-ink text-canvas"
                    : "border-line bg-canvas text-ink-soft hover:text-ink"
                }`}
              >
                {label}
                {id === "mine" && unread > 0 ? (
                  <span
                    className="absolute -right-0.5 -top-0.5 h-2.5 w-2.5 rounded-full border-2 border-surface bg-pink"
                    aria-label="New reply"
                  />
                ) : null}
              </button>
            ))}
          </div>
          <button
            type="button"
            onClick={onClose}
            className="-mr-1 rounded-full px-2 py-1 text-lg leading-none text-ink-soft hover:text-ink"
            aria-label="Close"
          >
            ×
          </button>
        </div>

        {tab === "send" ? (
          sent ? (
            <>
              <h2 className="mt-4 font-display text-base font-bold">Thanks!</h2>
              <p className="mt-1 text-sm text-ink-soft">
                Got it — this goes straight to the person building the game.
                If they reply, you&apos;ll see it under Your feedback.
              </p>
              <button
                type="button"
                onClick={onClose}
                className="mt-4 w-full rounded-full bg-ink px-4 py-2.5 text-sm font-medium text-canvas"
              >
                Done
              </button>
            </>
          ) : (
            <>
              {parent ? (
                <div className="mt-4 flex items-start gap-2 rounded-xl border border-line bg-canvas px-3 py-2 text-xs text-ink-soft">
                  <p className="min-w-0 flex-1 truncate">
                    Following up on: {parent.body}
                  </p>
                  <button
                    type="button"
                    onClick={() => setParent(null)}
                    className="shrink-0 underline hover:text-ink"
                  >
                    Clear
                  </button>
                </div>
              ) : (
                <p className="mt-4 text-xs text-ink-soft">
                  Bugs, ideas, or anything that felt off.
                </p>
              )}

              <textarea
                autoFocus
                value={body}
                onChange={(e) => setBody(e.target.value.slice(0, MAX))}
                rows={5}
                maxLength={MAX}
                placeholder={parent ? "Your reply" : "What's on your mind?"}
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
          )
        ) : (
          <div className="-mx-1 mt-4 min-h-0 flex-1 overflow-y-auto px-1">
            {mine === null ? (
              <p className="text-sm text-ink-soft">
                {loading ? "Loading…" : ""}
              </p>
            ) : mineError ? (
              <p className="text-sm text-ink" role="alert">
                {mineError}
              </p>
            ) : mine.length === 0 ? (
              <p className="text-sm text-ink-soft">
                Nothing yet. Anything you send shows up here, along with any
                reply.
              </p>
            ) : (
              <ul className="flex flex-col gap-2">
                {mine.map((f) => (
                  <MyFeedbackItem
                    key={f.id}
                    item={f}
                    onReply={() => replyTo(f)}
                  />
                ))}
              </ul>
            )}
          </div>
        )}
      </div>
    </div>
  );
}

function MyFeedbackItem({
  item,
  onReply,
}: {
  item: MyFeedback;
  onReply: () => void;
}) {
  const fresh = item.reply_body && !item.reply_seen_at;
  return (
    <li className="rounded-2xl border border-line bg-canvas px-3.5 py-3">
      <p className="text-[11px] text-ink-soft">
        You · {fmtDay(item.created_at)}
      </p>
      <p className="mt-1 whitespace-pre-wrap break-words text-sm text-ink-soft">
        {item.body}
      </p>
      {item.reply_body ? (
        <div className="mt-2.5 rounded-xl border border-line bg-surface px-3 py-2">
          <p className="flex items-center gap-1.5 text-[11px] font-semibold text-ink">
            {fresh ? (
              <span className="inline-block h-2 w-2 rounded-full bg-pink" />
            ) : null}
            Reply from Sequencr
            {item.replied_at ? (
              <span className="font-normal text-ink-soft">
                · {fmtDay(item.replied_at)}
              </span>
            ) : null}
          </p>
          <p className="mt-1 whitespace-pre-wrap break-words text-sm">
            {item.reply_body}
          </p>
          <button
            type="button"
            onClick={onReply}
            className="mt-1.5 text-[11px] text-ink-soft underline hover:text-ink"
          >
            Reply
          </button>
        </div>
      ) : (
        <p className="mt-1.5 text-[11px] text-ink-soft">No reply yet</p>
      )}
    </li>
  );
}

function fmtDay(iso: string) {
  return new Date(iso).toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
  });
}
