import { notFound, redirect } from "next/navigation";
import { getCurrentUser } from "@/lib/auth/me";
import { createClient } from "@/lib/supabase/server";

// Live snapshot, never cached — a stats page showing stale numbers is
// worse than no stats page.
export const dynamic = "force-dynamic";

export const metadata = {
  title: "Admin",
  // Keep this out of search results. The RPCs behind it enforce their own
  // admin check, but there's no reason to advertise the route.
  robots: { index: false, follow: false },
};

type Overview = {
  total_users: number;
  registered_users: number;
  guest_users: number;
  bot_users: number;
  new_24h: number;
  new_7d: number;
  rooms_total: number;
  rooms_waiting: number;
  rooms_in_game: number;
  games_in_progress: number;
  players_seated: number;
};

type ActiveRoom = {
  code: string;
  status: string;
  host_name: string;
  seats_taken: number;
  capacity: number;
  has_live_game: boolean;
  created_at: string;
  last_activity_at: string;
};

// Contains PII (email). Only ever rendered behind the is_admin check.
type UserRow = {
  email: string | null;
  display_name: string;
  tag: string | null;
  is_guest: boolean;
  is_bot: boolean;
  is_admin: boolean;
  created_at: string;
  last_sign_in_at: string | null;
};

type SignupDay = { day: string; registered: number; guests: number };
type GameDay = { day: string; completed: number };

type GameTotals = {
  completed_total: number;
  completed_24h: number;
  completed_7d: number;
  avg_duration_secs: number;
  games_with_bots: number;
};

function duration(secs: number | null) {
  if (!secs || secs < 0) return "—";
  const m = Math.floor(secs / 60);
  const s = secs % 60;
  return m ? `${m}m ${s}s` : `${s}s`;
}

function shortDay(iso: string) {
  return new Date(iso + "T00:00:00").toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
  });
}

export default async function AdminPage() {
  const user = await getCurrentUser();
  if (!user) redirect("/login");

  const supabase = await createClient();

  // The RPCs each re-check this themselves; this call just decides whether
  // the route exists at all, so non-admins get a 404 rather than a broken page.
  const { data: isAdmin } = await supabase.rpc("current_user_is_admin");
  if (!isAdmin) notFound();

  const [overviewRes, roomsRes, usersRes, signupsRes, totalsRes, gamesRes] =
    await Promise.all([
      supabase.rpc("admin_overview"),
      supabase.rpc("admin_active_rooms"),
      supabase.rpc("admin_user_list", { p_limit: 200 }),
      supabase.rpc("admin_signups_by_day", { p_days: 14 }),
      supabase.rpc("admin_game_totals"),
      supabase.rpc("admin_games_by_day", { p_days: 14 }),
    ]);

  const o = (overviewRes.data?.[0] ?? null) as Overview | null;
  const rooms = (roomsRes.data ?? []) as ActiveRoom[];
  const users = (usersRes.data ?? []) as UserRow[];
  const signups = (signupsRes.data ?? []) as SignupDay[];
  const totals = (totalsRes.data?.[0] ?? null) as GameTotals | null;
  const games = (gamesRes.data ?? []) as GameDay[];

  const liveRooms = rooms.filter((r) => r.has_live_game).length;

  return (
    <div className="mx-auto flex w-full max-w-[1100px] flex-col px-6 py-8 sm:px-8">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <h1
          className="font-display font-bold leading-none"
          style={{ fontSize: "clamp(30px, 4vw, 40px)", letterSpacing: "-0.03em" }}
        >
          Admin
        </h1>
        <span className="text-xs text-ink-soft">
          {new Date().toLocaleString()}
        </span>
      </div>

      {/* The four numbers worth knowing at a glance. */}
      <div className="mt-6 grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Kpi label="Players" value={o?.total_users ?? 0} sub={`${o?.registered_users ?? 0} registered`} />
        <Kpi label="New today" value={o?.new_24h ?? 0} sub={`${o?.new_7d ?? 0} this week`} />
        <Kpi label="Playing now" value={o?.games_in_progress ?? 0} sub={`${liveRooms} live room${liveRooms === 1 ? "" : "s"}`} />
        <Kpi
          label="Games finished"
          value={totals?.completed_total ?? 0}
          sub={
            totals?.completed_total
              ? `avg ${duration(totals.avg_duration_secs)}`
              : "none yet"
          }
        />
      </div>

      <div className="mt-4 grid gap-4 lg:grid-cols-2">
        <Card title="Who's signed up">
          <MiniRow label="Registered" value={o?.registered_users ?? 0} of={o?.total_users ?? 0} />
          <MiniRow label="Guests" value={o?.guest_users ?? 0} of={o?.total_users ?? 0} />
          <MiniRow label="Bots" value={o?.bot_users ?? 0} of={o?.total_users ?? 0} />
        </Card>

        <Card title="Rooms right now">
          <MiniRow label="Waiting in lobby" value={o?.rooms_waiting ?? 0} of={o?.rooms_total ?? 0} />
          <MiniRow label="In game" value={o?.rooms_in_game ?? 0} of={o?.rooms_total ?? 0} />
          <MiniRow label="Seated players" value={o?.players_seated ?? 0} of={o?.players_seated ?? 0} />
        </Card>
      </div>

      <div className="mt-4 grid gap-4 lg:grid-cols-2">
        <Card title="Signups · 14 days">
          <Bars
            rows={signups.map((d) => ({
              day: d.day,
              value: d.registered + d.guests,
              note:
                d.guests > 0 ? `${d.registered} + ${d.guests} guest` : undefined,
            }))}
            empty="No signups in the last 14 days."
          />
        </Card>

        <Card title="Games finished · 14 days">
          <Bars
            rows={games.map((d) => ({ day: d.day, value: d.completed }))}
            empty="Nothing recorded yet — tracking started today. Games finished before that were deleted by the cleanup cron."
          />
        </Card>
      </div>

      {rooms.length > 0 && (
        <Card title={`Live rooms · ${rooms.length}`} className="mt-4">
          <div className="-mx-4 overflow-x-auto">
            <table className="w-full text-left text-sm">
              <thead>
                <tr className="text-xs text-ink-soft">
                  <Th>Code</Th>
                  <Th>Host</Th>
                  <Th>Seats</Th>
                  <Th>Status</Th>
                  <Th>Last activity</Th>
                </tr>
              </thead>
              <tbody>
                {rooms.slice(0, 12).map((r) => (
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
                    <Td className="text-ink-soft">
                      {new Date(r.last_activity_at).toLocaleTimeString()}
                    </Td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </Card>
      )}

      {/* Collapsed by default — this is the long one, and it's reference
          material rather than something you scan every visit. */}
      <details className="group mt-4 rounded-3xl border border-line bg-surface">
        <summary className="cursor-pointer list-none px-5 py-4 text-sm font-medium">
          All users · {users.length}
          <span className="ml-2 text-ink-soft group-open:hidden">show</span>
          <span className="ml-2 hidden text-ink-soft group-open:inline">hide</span>
        </summary>
        <div className="overflow-x-auto border-t border-line">
          <table className="w-full text-left text-sm">
            <thead>
              <tr className="text-xs text-ink-soft">
                <Th>Name</Th>
                <Th>Email</Th>
                <Th>Type</Th>
                <Th>Joined</Th>
                <Th>Last seen</Th>
              </tr>
            </thead>
            <tbody>
              {users.map((u, i) => (
                <tr key={`${u.tag ?? u.display_name}-${i}`} className="border-t border-line">
                  <Td>
                    {u.display_name}
                    {u.tag ? (
                      <span className="ml-1.5 font-mono text-xs text-ink-soft">
                        #{u.tag}
                      </span>
                    ) : null}
                    {u.is_admin ? <Badge live>admin</Badge> : null}
                  </Td>
                  <Td className="font-mono text-xs">{u.email ?? "—"}</Td>
                  <Td>{u.is_bot ? "Bot" : u.is_guest ? "Guest" : "Registered"}</Td>
                  <Td className="text-ink-soft">
                    {new Date(u.created_at).toLocaleDateString()}
                  </Td>
                  <Td className="text-ink-soft">
                    {u.last_sign_in_at
                      ? new Date(u.last_sign_in_at).toLocaleDateString()
                      : "—"}
                  </Td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </details>

      <p className="mt-8 text-xs leading-relaxed text-ink-soft">
        Rooms and games are a live snapshot — finished games are deleted 5
        minutes after they end, and guests disappear 24 hours after their last
        sign-in. Only the daily completed-game counter is durable.
      </p>
    </div>
  );
}

function Kpi({
  label,
  value,
  sub,
}: {
  label: string;
  value: number;
  sub?: string;
}) {
  return (
    <div className="rounded-2xl border border-line bg-surface px-4 py-4">
      <div className="text-xs text-ink-soft">{label}</div>
      <div
        className="mt-1 font-display font-bold leading-none"
        style={{ fontSize: "34px", letterSpacing: "-0.03em" }}
      >
        {value}
      </div>
      {sub ? <div className="mt-1.5 text-xs text-ink-soft">{sub}</div> : null}
    </div>
  );
}

function Card({
  title,
  children,
  className = "",
}: {
  title: string;
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <section
      className={`rounded-3xl border border-line bg-surface px-5 py-4 ${className}`}
    >
      <h2 className="text-xs font-medium uppercase tracking-wide text-ink-soft">
        {title}
      </h2>
      <div className="mt-3">{children}</div>
    </section>
  );
}

function MiniRow({
  label,
  value,
  of,
}: {
  label: string;
  value: number;
  of: number;
}) {
  const pct = of > 0 ? Math.round((value / of) * 100) : 0;
  return (
    <div className="flex items-center gap-3 py-1.5">
      <span className="w-36 shrink-0 text-sm">{label}</span>
      <span className="w-10 shrink-0 text-sm font-semibold tabular-nums">
        {value}
      </span>
      <span className="h-1.5 flex-1 overflow-hidden rounded-full bg-line">
        <span
          className="block h-full rounded-full bg-ink"
          style={{ width: `${pct}%` }}
        />
      </span>
    </div>
  );
}

function Bars({
  rows,
  empty,
}: {
  rows: { day: string; value: number; note?: string }[];
  empty: string;
}) {
  const peak = Math.max(...rows.map((r) => r.value), 1);
  if (!rows.some((r) => r.value > 0)) {
    return <p className="py-2 text-sm text-ink-soft">{empty}</p>;
  }
  return (
    <div className="flex flex-col">
      {rows.map((r) => (
        <div key={r.day} className="flex items-center gap-3 py-1">
          <span className="w-14 shrink-0 text-xs text-ink-soft">
            {shortDay(r.day)}
          </span>
          <span className="w-6 shrink-0 text-sm font-semibold tabular-nums">
            {r.value || ""}
          </span>
          <span className="h-1.5 flex-1 overflow-hidden rounded-full bg-line">
            <span
              className="block h-full rounded-full bg-ink"
              style={{ width: `${(r.value / peak) * 100}%` }}
            />
          </span>
          {r.note ? (
            <span className="shrink-0 text-[11px] text-ink-soft">{r.note}</span>
          ) : null}
        </div>
      ))}
    </div>
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

function Th({ children }: { children: React.ReactNode }) {
  return <th className="px-4 py-2.5 font-medium">{children}</th>;
}

function Td({
  children,
  className = "",
}: {
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <td className={`whitespace-nowrap px-4 py-2.5 ${className}`}>{children}</td>
  );
}
