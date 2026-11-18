"use client";

import {
  useMemo,
  useState,
  useSyncExternalStore,
  useTransition,
} from "react";
import { useRouter } from "next/navigation";
import { replyToFeedback } from "./actions";
import { fmtAgo, fmtDateTime } from "./format";
import { Pill } from "./ui";

// Feedback inbox and the "unread" count shown in the nav and on Today.
//
// Read state is a per-browser convenience, not data: one timestamp in
// localStorage ("newest feedback I've marked read"), namespaced by user id
// so two admins on one browser don't share it. Nothing is written to the
// database — the free-tier quota is org-wide and this doesn't need to
// survive a cleared browser. With no stored mark yet, the last 7 days
// count as unread.

export type Feedback = {
  id: string;
  author_name: string | null;
  author_tag: string | null;
  was_guest: boolean;
  body: string;
  page: string | null;
  created_at: string;
  author_gone: boolean;
  parent_id: string | null;
  parent_body: string | null;
  reply_body: string | null;
  replied_at: string | null;
  reply_seen_at: string | null;
};

const EVENT = "sequencr:admin-feedback-read";
const keyFor = (userId: string) => `sequencr:admin:feedback-read:${userId}`;

function subscribe(cb: () => void) {
  window.addEventListener("storage", cb);
  window.addEventListener(EVENT, cb);
  return () => {
    window.removeEventListener("storage", cb);
    window.removeEventListener(EVENT, cb);
  };
}

// undefined while server-rendering / before hydration; null when the
// browser has no mark yet (or storage is blocked).
function useReadMark(userId: string): string | null | undefined {
  return useSyncExternalStore(
    subscribe,
    () => {
      try {
        return window.localStorage.getItem(keyFor(userId));
      } catch {
        return null;
      }
    },
    () => undefined,
  );
}

function markRead(userId: string, iso: string) {
  try {
    window.localStorage.setItem(keyFor(userId), iso);
  } catch {
    // Private window or blocked storage: nothing to remember it in.
  }
  window.dispatchEvent(new Event(EVENT));
}

function cutoffMs(mark: string | null, now: number) {
  return mark ? new Date(mark).getTime() : now - 7 * 24 * 3600 * 1000;
}

function useUnread(userId: string, timestamps: string[], now: number) {
  const mark = useReadMark(userId);
  if (mark === undefined) return { ready: false, count: 0, cutoff: Infinity };
  const cutoff = cutoffMs(mark, now);
  return {
    ready: true,
    count: timestamps.filter((t) => new Date(t).getTime() > cutoff).length,
    cutoff,
  };
}

/** Small pink count for the nav. Renders nothing at zero. */
export function UnreadBadge({
  userId,
  timestamps,
  now,
}: {
  userId: string;
  timestamps: string[];
  now: number;
}) {
  const { ready, count } = useUnread(userId, timestamps, now);
  if (!ready || count === 0) return null;
  return (
    <span className="ml-auto rounded-full bg-pink px-1.5 py-0.5 text-[10px] font-semibold leading-none text-white tabular-nums">
      {count}
    </span>
  );
}

/** Bare number for the Today KPI tile. */
export function UnreadCount({
  userId,
  timestamps,
  now,
}: {
  userId: string;
  timestamps: string[];
  now: number;
}) {
  const { ready, count } = useUnread(userId, timestamps, now);
  return <>{ready ? count : "–"}</>;
}

type Filter = "all" | "registered" | "guests" | "unread" | "unanswered";

export function FeedbackInbox({
  userId,
  items,
  now,
}: {
  userId: string;
  items: Feedback[];
  now: number;
}) {
  const [filter, setFilter] = useState<Filter>("all");
  const { ready, count: unread, cutoff } = useUnread(
    userId,
    items.map((f) => f.created_at),
    now,
  );
  const isUnread = (f: Feedback) =>
    ready && new Date(f.created_at).getTime() > cutoff;

  const counts = useMemo(
    () => ({
      all: items.length,
      registered: items.filter((f) => !f.was_guest).length,
      guests: items.filter((f) => f.was_guest).length,
      unanswered: items.filter((f) => !f.reply_body && !f.author_gone).length,
    }),
    [items],
  );

  const shown = items.filter((f) =>
    filter === "registered"
      ? !f.was_guest
      : filter === "guests"
        ? f.was_guest
        : filter === "unread"
          ? isUnread(f)
          : filter === "unanswered"
            ? !f.reply_body && !f.author_gone
            : true,
  );

  const newest = items.reduce<string | null>(
    (max, f) => (!max || f.created_at > max ? f.created_at : max),
    null,
  );

  const chips: [Filter, string, number][] = [
    ["all", "All", counts.all],
    ["unread", "Unread", unread],
    ["unanswered", "Unanswered", counts.unanswered],
    ["registered", "Registered", counts.registered],
    ["guests", "Guests", counts.guests],
  ];

  return (
    <div>
      <div className="flex flex-wrap items-center gap-2">
        <div className="flex flex-wrap gap-1.5" role="tablist">
          {chips.map(([id, label, n]) => (
            <button
              key={id}
              type="button"
              role="tab"
              aria-selected={filter === id}
              onClick={() => setFilter(id)}
              className={`rounded-full border px-3 py-1 text-xs transition-colors ${
                filter === id
                  ? "border-ink bg-ink text-canvas"
                  : "border-line bg-surface text-ink-soft hover:text-ink"
              }`}
            >
              {label}
              <span className="ml-1.5 tabular-nums opacity-70">{n}</span>
            </button>
          ))}
        </div>
        {unread > 0 && newest ? (
          <button
            type="button"
            onClick={() => markRead(userId, newest)}
            className="ml-auto rounded-full border border-line bg-surface px-3 py-1 text-xs hover:border-ink-soft"
          >
            Mark all read
          </button>
        ) : null}
      </div>

      {shown.length ? (
        <ul className="mt-4 flex flex-col gap-2">
          {shown.map((f, i) => {
            const fresh = isUnread(f);
            // In the "All" view rows arrive registered-first; mark where
            // the lower-priority guest pile starts.
            const guestDivider =
              filter === "all" && f.was_guest && !shown[i - 1]?.was_guest;
            return (
              <li key={f.id}>
                {guestDivider ? (
                  <p className="mb-2 mt-4 text-xs text-ink-soft">
                    From guests · lower priority
                  </p>
                ) : null}
                <article
                  className={`rounded-2xl border px-4 py-3 ${
                    fresh ? "border-ink-soft bg-surface" : "border-line"
                  } ${f.was_guest ? "" : "bg-surface"}`}
                >
                  <div className="flex flex-wrap items-center gap-x-2 gap-y-1 text-xs text-ink-soft">
                    {fresh ? (
                      <span
                        className="inline-block h-2 w-2 rounded-full bg-pink"
                        aria-label="Unread"
                      />
                    ) : null}
                    <span className="font-medium text-ink">
                      {f.author_name ?? "deleted account"}
                    </span>
                    {f.author_tag ? (
                      <span className="font-mono">#{f.author_tag}</span>
                    ) : null}
                    {f.was_guest ? <Pill>guest</Pill> : null}
                    <span title={fmtDateTime(f.created_at)}>
                      {fmtAgo(f.created_at, now)}
                    </span>
                    {f.page ? (
                      <span className="truncate font-mono">{f.page}</span>
                    ) : null}
                  </div>
                  {f.parent_body ? (
                    <p className="mt-1.5 truncate border-l-2 border-line pl-2 text-xs text-ink-soft">
                      Following up on: {f.parent_body}
                    </p>
                  ) : null}
                  <p
                    className={`mt-1.5 whitespace-pre-wrap break-words text-sm ${
                      f.was_guest ? "text-ink-soft" : ""
                    }`}
                  >
                    {f.body}
                  </p>
                  <ReplyBox item={f} now={now} />
                </article>
              </li>
            );
          })}
        </ul>
      ) : (
        <p className="mt-6 text-sm text-ink-soft">
          {items.length === 0
            ? "No feedback has come in. The button sits in the sidebar on every signed-in page."
            : filter === "unread"
              ? "You're all caught up."
              : "Nothing matches this filter."}
        </p>
      )}
    </div>
  );
}

function ReplyBox({ item, now }: { item: Feedback; now: number }) {
  const router = useRouter();
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState(item.reply_body ?? "");
  const [error, setError] = useState<string | null>(null);
  const [pending, startTransition] = useTransition();

  function save(body: string) {
    if (pending) return;
    setError(null);
    startTransition(async () => {
      const res = await replyToFeedback(item.id, body);
      if (res.error) {
        setError(res.error);
        return;
      }
      setEditing(false);
      router.refresh();
    });
  }

  if (item.author_gone && !item.reply_body) {
    return (
      <p className="mt-2 text-[11px] text-ink-soft">
        Can&apos;t reply — the author&apos;s account is gone
        {item.was_guest ? " (guest expired)" : ""}.
      </p>
    );
  }

  if (editing) {
    return (
      <div className="mt-3">
        <textarea
          autoFocus
          value={draft}
          onChange={(e) => setDraft(e.target.value.slice(0, 2000))}
          rows={3}
          maxLength={2000}
          placeholder="Write a reply they'll see in their feedback panel"
          className="w-full resize-none rounded-2xl border border-line bg-canvas px-3 py-2 text-sm outline-none focus:border-ink-soft"
        />
        <div className="mt-2 flex flex-wrap items-center gap-2">
          <button
            type="button"
            onClick={() => save(draft)}
            disabled={pending || draft.trim().length === 0}
            className="rounded-full bg-ink px-4 py-1.5 text-xs font-medium text-canvas disabled:opacity-40"
          >
            {pending ? "Sending…" : item.reply_body ? "Save reply" : "Send reply"}
          </button>
          <button
            type="button"
            onClick={() => {
              setEditing(false);
              setDraft(item.reply_body ?? "");
              setError(null);
            }}
            disabled={pending}
            className="rounded-full border border-line px-4 py-1.5 text-xs text-ink-soft hover:text-ink"
          >
            Cancel
          </button>
          {item.reply_body ? (
            <button
              type="button"
              onClick={() => save("")}
              disabled={pending}
              className="ml-auto text-xs text-ink-soft underline hover:text-ink"
            >
              Remove reply
            </button>
          ) : null}
          <span className="text-[11px] tabular-nums text-ink-soft">
            {draft.length}/2000
          </span>
        </div>
        {error ? (
          <p className="mt-2 text-xs text-ink" role="alert">
            {error}
          </p>
        ) : null}
      </div>
    );
  }

  if (item.reply_body) {
    return (
      <div className="mt-3 rounded-xl border border-line bg-canvas px-3 py-2">
        <div className="flex flex-wrap items-center gap-x-2 gap-y-1 text-[11px] text-ink-soft">
          <span className="font-medium text-ink">Your reply</span>
          {item.replied_at ? (
            <span title={fmtDateTime(item.replied_at)}>
              {fmtAgo(item.replied_at, now)}
            </span>
          ) : null}
          {item.reply_seen_at ? (
            <Pill tone="mint">seen {fmtAgo(item.reply_seen_at, now)}</Pill>
          ) : (
            <Pill>not seen yet</Pill>
          )}
          <button
            type="button"
            onClick={() => setEditing(true)}
            className="ml-auto underline hover:text-ink"
          >
            Edit
          </button>
        </div>
        <p className="mt-1 whitespace-pre-wrap break-words text-sm">
          {item.reply_body}
        </p>
        {item.author_gone ? (
          <p className="mt-1 text-[11px] text-ink-soft">
            The author&apos;s account is gone, so this won&apos;t be seen.
          </p>
        ) : null}
      </div>
    );
  }

  return (
    <button
      type="button"
      onClick={() => setEditing(true)}
      className="mt-2 rounded-full border border-line bg-surface px-3 py-1 text-xs text-ink-soft hover:border-ink-soft hover:text-ink"
    >
      Reply
    </button>
  );
}
