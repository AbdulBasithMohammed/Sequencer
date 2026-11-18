"use client";

import { useMemo, useState } from "react";
import { countryLabel, flag, fmtAgo, fmtDateTime } from "./format";
import { Pill } from "./ui";

// Searchable, filterable player list. Filtering and sorting are
// client-side: admin_user_list caps at 500 rows, nowhere near needing
// server paging. Rows are a grid on desktop and stack on a phone, so
// there's no sideways-scrolling table.

export type UserRow = {
  email: string | null;
  display_name: string;
  tag: string | null;
  country: string | null;
  is_guest: boolean;
  is_bot: boolean;
  is_admin: boolean;
  created_at: string;
  last_sign_in_at: string | null;
};

type Kind = "registered" | "guests" | "bots" | "all";
type Sort = "joined" | "seen" | "name" | "country";

const kindOf = (u: UserRow): Exclude<Kind, "all"> =>
  u.is_bot ? "bots" : u.is_guest ? "guests" : "registered";

const ts = (iso: string | null) => (iso ? new Date(iso).getTime() : -Infinity);

export function PlayersList({
  rows,
  now,
  capped,
}: {
  rows: UserRow[];
  now: number;
  capped: boolean;
}) {
  const [kind, setKind] = useState<Kind>("registered");
  const [sort, setSort] = useState<Sort>("joined");
  const [q, setQ] = useState("");

  const counts = useMemo(() => {
    const c = { registered: 0, guests: 0, bots: 0, all: rows.length };
    for (const r of rows) c[kindOf(r)]++;
    return c;
  }, [rows]);

  const shown = useMemo(() => {
    const needle = q.trim().toLowerCase().replace(/^#/, "");
    const filtered = rows.filter((u) => {
      if (kind !== "all" && kindOf(u) !== kind) return false;
      if (!needle) return true;
      return [u.display_name, u.tag, u.email, u.country, countryLabel(u.country)]
        .filter(Boolean)
        .some((s) => s!.toLowerCase().includes(needle));
    });
    const by: Record<Sort, (a: UserRow, b: UserRow) => number> = {
      joined: (a, b) => ts(b.created_at) - ts(a.created_at),
      seen: (a, b) => ts(b.last_sign_in_at) - ts(a.last_sign_in_at),
      name: (a, b) => a.display_name.localeCompare(b.display_name),
      country: (a, b) =>
        (a.country ? countryLabel(a.country) : "~").localeCompare(
          b.country ? countryLabel(b.country) : "~",
        ),
    };
    return filtered.sort(by[sort]);
  }, [rows, kind, sort, q]);

  const chips: [Kind, string][] = [
    ["registered", "Registered"],
    ["guests", "Guests"],
    ["bots", "Bots"],
    ["all", "All"],
  ];

  return (
    <div>
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center">
        <input
          type="search"
          value={q}
          onChange={(e) => setQ(e.target.value)}
          placeholder="Search name, #tag, email or country"
          aria-label="Search players"
          className="h-9 w-full rounded-full border border-line bg-surface px-4 text-sm outline-none placeholder:text-ink-soft focus:border-ink-soft sm:max-w-xs"
        />
        <div className="flex flex-wrap items-center gap-1.5">
          {chips.map(([id, label]) => (
            <button
              key={id}
              type="button"
              aria-pressed={kind === id}
              onClick={() => setKind(id)}
              className={`rounded-full border px-3 py-1 text-xs transition-colors ${
                kind === id
                  ? "border-ink bg-ink text-canvas"
                  : "border-line bg-surface text-ink-soft hover:text-ink"
              }`}
            >
              {label}
              <span className="ml-1.5 tabular-nums opacity-70">
                {counts[id]}
              </span>
            </button>
          ))}
        </div>
        <label className="flex items-center gap-2 text-xs text-ink-soft sm:ml-auto">
          Sort
          <select
            value={sort}
            onChange={(e) => setSort(e.target.value as Sort)}
            className="h-8 rounded-full border border-line bg-surface px-3 text-xs text-ink"
          >
            <option value="joined">Newest</option>
            <option value="seen">Recently seen</option>
            <option value="name">Name</option>
            <option value="country">Country</option>
          </select>
        </label>
      </div>

      <div className="mt-4 overflow-hidden rounded-2xl border border-line bg-surface">
        <div className="hidden grid-cols-[minmax(0,1.4fr)_minmax(0,1.5fr)_110px_110px] gap-4 border-b border-line px-4 py-2 text-xs text-ink-soft md:grid">
          <span>Player</span>
          <span>Email</span>
          <span>Joined</span>
          <span>Last seen</span>
        </div>
        {shown.length ? (
          <ul>
            {shown.map((u, i) => (
              <li
                key={`${u.tag ?? u.display_name}-${u.created_at}-${i}`}
                className="grid grid-cols-2 gap-x-4 gap-y-0.5 border-t border-line px-4 py-2.5 text-sm first:border-t-0 md:grid-cols-[minmax(0,1.4fr)_minmax(0,1.5fr)_110px_110px] md:items-center"
              >
                <div className="col-span-2 flex min-w-0 flex-wrap items-center gap-x-1.5 gap-y-1 md:col-span-1">
                  <span className="truncate font-medium">{u.display_name}</span>
                  {u.tag ? (
                    <span className="font-mono text-xs text-ink-soft">
                      #{u.tag}
                    </span>
                  ) : null}
                  {u.country ? (
                    <span className="text-xs" title={countryLabel(u.country)}>
                      {flag(u.country)}{" "}
                      <span className="font-mono text-ink-soft">{u.country}</span>
                    </span>
                  ) : null}
                  {u.is_admin ? <Pill tone="dark">admin</Pill> : null}
                  {kind === "all" && kindOf(u) !== "registered" ? (
                    <Pill>{u.is_bot ? "bot" : "guest"}</Pill>
                  ) : null}
                </div>
                <span className="col-span-2 truncate font-mono text-xs text-ink-soft md:col-span-1">
                  {u.email ?? "—"}
                </span>
                <span
                  className="text-xs text-ink-soft"
                  title={fmtDateTime(u.created_at)}
                >
                  <span className="md:hidden">Joined </span>
                  {fmtAgo(u.created_at, now)}
                </span>
                <span
                  className="text-xs text-ink-soft"
                  title={fmtDateTime(u.last_sign_in_at)}
                >
                  <span className="md:hidden">Seen </span>
                  {fmtAgo(u.last_sign_in_at, now)}
                </span>
              </li>
            ))}
          </ul>
        ) : (
          <p className="px-4 py-6 text-sm text-ink-soft">
            No players match{q ? ` “${q}”` : " this filter"}.
          </p>
        )}
      </div>

      <p className="mt-3 text-xs text-ink-soft">
        Showing {shown.length} of {rows.length}
        {capped ? " (the newest 500 accounts)" : ""}. Country is captured
        once, on a signed-in visit; older accounts show none until they come
        back.
      </p>
    </div>
  );
}
