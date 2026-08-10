"use client";

import { useMemo, useState } from "react";
import { countryLabel, flag, fmtDateTime, fmtTime } from "./format";

// Sortable tables.
//
// These are self-contained client components rather than one generic
// <DataTable columns={...}> because render functions cannot cross the
// server/client boundary — a server component can pass plain rows, not
// callbacks. So each table owns its own columns and receives only
// serialisable data.
//
// Sorting is client-side: instant, and the row counts here (hundreds at
// most, capped by the RPCs) are nowhere near needing server-side paging.

type Dir = "asc" | "desc";

function useSort<T>(
  rows: T[],
  accessors: Record<string, (row: T) => string | number | null>,
  initialKey: string,
  initialDir: Dir = "desc",
) {
  const [key, setKey] = useState(initialKey);
  const [dir, setDir] = useState<Dir>(initialDir);

  const sorted = useMemo(() => {
    const get = accessors[key];
    if (!get) return rows;
    return [...rows].sort((a, b) => {
      const av = get(a);
      const bv = get(b);
      // Nulls always sort last, whichever direction — an empty cell is
      // never the most interesting row.
      if (av === null && bv === null) return 0;
      if (av === null) return 1;
      if (bv === null) return -1;
      const cmp =
        typeof av === "number" && typeof bv === "number"
          ? av - bv
          : String(av).localeCompare(String(bv));
      return dir === "asc" ? cmp : -cmp;
    });
    // accessors is defined inline by the caller; keying on the sort state
    // and rows is what actually matters here.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [rows, key, dir]);

  function toggle(k: string) {
    if (k === key) {
      setDir((d) => (d === "asc" ? "desc" : "asc"));
    } else {
      setKey(k);
      setDir("desc");
    }
  }

  return { sorted, key, dir, toggle };
}

function SortHeader({
  label,
  col,
  active,
  dir,
  onClick,
}: {
  label: string;
  col: string;
  active: boolean;
  dir: Dir;
  onClick: (k: string) => void;
}) {
  return (
    <th
      className="px-4 py-2.5 font-medium"
      aria-sort={active ? (dir === "asc" ? "ascending" : "descending") : "none"}
    >
      <button
        type="button"
        onClick={() => onClick(col)}
        className={`flex items-center gap-1 whitespace-nowrap transition-colors hover:text-ink ${
          active ? "text-ink" : ""
        }`}
      >
        {label}
        <span className={active ? "" : "opacity-0 group-hover:opacity-40"}>
          {active ? (dir === "asc" ? "▲" : "▼") : "▾"}
        </span>
      </button>
    </th>
  );
}

/* ---------------------------------------------------------------- users */

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

export function UsersTable({ rows }: { rows: UserRow[] }) {
  const { sorted, key, dir, toggle } = useSort<UserRow>(
    rows,
    {
      name: (r) => r.display_name.toLowerCase(),
      country: (r) => (r.country ? countryLabel(r.country) : null),
      email: (r) => r.email,
      type: (r) => (r.is_bot ? "Bot" : r.is_guest ? "Guest" : "Registered"),
      joined: (r) => new Date(r.created_at).getTime(),
      seen: (r) =>
        r.last_sign_in_at ? new Date(r.last_sign_in_at).getTime() : null,
    },
    "joined",
  );

  const cols: [string, string][] = [
    ["name", "Name"],
    ["country", "Country"],
    ["email", "Email"],
    ["type", "Type"],
    ["joined", "Joined"],
    ["seen", "Last seen"],
  ];

  return (
    <div className="overflow-x-auto">
      <table className="group w-full text-left text-sm">
        <thead>
          <tr className="text-xs text-ink-soft">
            {cols.map(([c, label]) => (
              <SortHeader
                key={c}
                col={c}
                label={label}
                active={key === c}
                dir={dir}
                onClick={toggle}
              />
            ))}
          </tr>
        </thead>
        <tbody>
          {sorted.map((u, i) => (
            <tr
              key={`${u.tag ?? u.display_name}-${i}`}
              className="border-t border-line"
            >
              <Td>
                {u.display_name}
                {u.tag ? (
                  <span className="ml-1.5 font-mono text-xs text-ink-soft">
                    #{u.tag}
                  </span>
                ) : null}
                {u.is_admin ? <Badge>admin</Badge> : null}
              </Td>
              <Td title={countryLabel(u.country)}>
                {u.country ? (
                  <>
                    {flag(u.country)}{" "}
                    <span className="font-mono text-xs">{u.country}</span>
                  </>
                ) : (
                  <span className="text-ink-soft">—</span>
                )}
              </Td>
              <Td className="font-mono text-xs">{u.email ?? "—"}</Td>
              <Td>{u.is_bot ? "Bot" : u.is_guest ? "Guest" : "Registered"}</Td>
              <Td className="text-ink-soft">{fmtDateTime(u.created_at)}</Td>
              <Td className="text-ink-soft">{fmtDateTime(u.last_sign_in_at)}</Td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

/* ---------------------------------------------------------------- rooms */

export type RoomRow = {
  code: string;
  status: string;
  host_name: string;
  seats_taken: number;
  capacity: number;
  has_live_game: boolean;
  created_at: string;
  last_activity_at: string;
};

export function RoomsTable({ rows }: { rows: RoomRow[] }) {
  const { sorted, key, dir, toggle } = useSort<RoomRow>(
    rows,
    {
      code: (r) => r.code,
      host: (r) => r.host_name.toLowerCase(),
      seats: (r) => r.seats_taken,
      status: (r) => (r.has_live_game ? "Playing" : r.status),
      activity: (r) => new Date(r.last_activity_at).getTime(),
    },
    "activity",
  );

  const cols: [string, string][] = [
    ["code", "Code"],
    ["host", "Host"],
    ["seats", "Seats"],
    ["status", "Status"],
    ["activity", "Last activity"],
  ];

  return (
    <div className="overflow-x-auto">
      <table className="group w-full text-left text-sm">
        <thead>
          <tr className="text-xs text-ink-soft">
            {cols.map(([c, label]) => (
              <SortHeader
                key={c}
                col={c}
                label={label}
                active={key === c}
                dir={dir}
                onClick={toggle}
              />
            ))}
          </tr>
        </thead>
        <tbody>
          {sorted.map((r) => (
            <tr key={r.code} className="border-t border-line">
              <Td>
                <span className="font-mono">{r.code}</span>
              </Td>
              <Td>{r.host_name}</Td>
              <Td>
                {r.seats_taken}/{r.capacity}
              </Td>
              <Td>
                <Badge live={r.has_live_game}>
                  {r.has_live_game ? "Playing" : r.status}
                </Badge>
              </Td>
              <Td className="text-ink-soft">{fmtTime(r.last_activity_at)}</Td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

/* ------------------------------------------------------------- elements */

function Td({
  children,
  className = "",
  title,
}: {
  children: React.ReactNode;
  className?: string;
  title?: string;
}) {
  return (
    <td className={`whitespace-nowrap px-4 py-2.5 ${className}`} title={title}>
      {children}
    </td>
  );
}

function Badge({
  children,
  live,
}: {
  children: React.ReactNode;
  live?: boolean;
}) {
  return (
    <span
      className={`ml-1 inline-block rounded-full border px-2 py-0.5 text-[10px] uppercase tracking-wide ${
        live ? "border-line bg-ink text-canvas" : "border-line text-ink-soft"
      }`}
    >
      {children}
    </span>
  );
}
