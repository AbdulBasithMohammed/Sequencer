"use client";

import { useMemo, useState, useSyncExternalStore } from "react";
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

type Filter = "all" | "registered" | "guests" | "unread";

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
          : true,
  );

  const newest = items.reduce<string | null>(
    (max, f) => (!max || f.created_at > max ? f.created_at : max),
    null,
  );

  const chips: [Filter, string, number][] = [
    ["all", "All", counts.all],
    ["unread", "Unread", unread],
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
                  <p
                    className={`mt-1.5 whitespace-pre-wrap break-words text-sm ${
                      f.was_guest ? "text-ink-soft" : ""
                    }`}
                  >
                    {f.body}
                  </p>
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
