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

type RecentUser = {
  display_name: string;
  tag: string | null;
  is_guest: boolean;
  is_bot: boolean;
  created_at: string;
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

type SignupDay = {
  day: string;
  registered: number;
  guests: number;
};

const RANGES = [6, 24, 72, 168];

export default async function AdminPage({
  searchParams,
}: {
  searchParams: Promise<{ hours?: string }>;
}) {
  const user = await getCurrentUser();
  if (!user) redirect("/login");

  const supabase = await createClient();

  // The RPCs each re-check this themselves; this call just decides whether
  // the route exists at all, so non-admins get a 404 rather than a broken page.
  const { data: isAdmin } = await supabase.rpc("current_user_is_admin");
  if (!isAdmin) notFound();

  const params = await searchParams;
  const hours = RANGES.includes(Number(params.hours)) ? Number(params.hours) : 24;

  const [overviewRes, usersRes, roomsRes, allUsersRes, signupsRes] =
    await Promise.all([
      supabase.rpc("admin_overview"),
      supabase.rpc("admin_recent_users", { p_hours: hours }),
      supabase.rpc("admin_active_rooms"),
      supabase.rpc("admin_user_list", { p_limit: 200 }),
      supabase.rpc("admin_signups_by_day", { p_days: 14 }),
    ]);

  const overview = (overviewRes.data?.[0] ?? null) as Overview | null;
  const recentUsers = (usersRes.data ?? []) as RecentUser[];
  const rooms = (roomsRes.data ?? []) as ActiveRoom[];
  const allUsers = (allUsersRes.data ?? []) as UserRow[];
  const signups = (signupsRes.data ?? []) as SignupDay[];

  return (
    <div className="mx-auto flex w-full max-w-[1000px] flex-col px-8 py-8">
      <h1
        className="font-display font-bold leading-none"
        style={{ fontSize: "clamp(32px, 4vw, 44px)", letterSpacing: "-0.03em" }}
      >
        Admin
      </h1>
      <p className="mt-2 text-sm text-ink-soft">
        Live snapshot · {new Date().toLocaleString()}
      </p>

      {overview ? (
        <div className="mt-8 grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
          <Stat label="Total users" value={overview.total_users} />
          <Stat label="Registered" value={overview.registered_users} />
          <Stat label="Guests" value={overview.guest_users} />
          <Stat label="Bots" value={overview.bot_users} />
          <Stat label="New · 24h" value={overview.new_24h} accent />
          <Stat label="New · 7d" value={overview.new_7d} accent />
          <Stat label="Playing now" value={overview.games_in_progress} accent />
          <Stat label="Seated players" value={overview.players_seated} />
          <Stat label="Rooms" value={overview.rooms_total} />
          <Stat label="Waiting" value={overview.rooms_waiting} />
          <Stat label="In game" value={overview.rooms_in_game} />
        </div>
      ) : (
        <Empty>Could not load overview.</Empty>
      )}

      <SectionHeading>
        New users
        <span className="ml-3 inline-flex gap-1 align-middle">
          {RANGES.map((h) => (
            <a
              key={h}
              href={`/admin?hours=${h}`}
              className={`rounded-full border px-2.5 py-1 text-xs ${
                h === hours
                  ? "border-line bg-ink text-canvas"
                  : "border-line text-ink-soft hover:text-ink"
              }`}
            >
              {h < 24 ? `${h}h` : `${h / 24}d`}
            </a>
          ))}
        </span>
      </SectionHeading>

      {recentUsers.length ? (
        <Table headers={["Name", "Type", "Joined"]}>
          {recentUsers.map((u, i) => (
            <tr key={`${u.tag ?? u.display_name}-${i}`} className="border-t border-line">
              <Td>
                {u.display_name}
                {u.tag ? (
                  <span className="ml-1.5 font-mono text-ink-soft">#{u.tag}</span>
                ) : null}
              </Td>
              <Td>{u.is_bot ? "Bot" : u.is_guest ? "Guest" : "Registered"}</Td>
              <Td>{new Date(u.created_at).toLocaleString()}</Td>
            </tr>
          ))}
        </Table>
      ) : (
        <Empty>No signups in the last {hours < 24 ? `${hours}h` : `${hours / 24}d`}.</Empty>
      )}

      <SectionHeading>Live rooms</SectionHeading>

      {rooms.length ? (
        <Table headers={["Code", "Host", "Seats", "Status", "Last activity"]}>
          {rooms.map((r) => (
            <tr key={r.code} className="border-t border-line">
              <Td>
                <span className="font-mono">{r.code}</span>
              </Td>
              <Td>{r.host_name}</Td>
              <Td>
                {r.seats_taken}/{r.capacity}
              </Td>
              <Td>{r.has_live_game ? "Playing" : r.status}</Td>
              <Td>{new Date(r.last_activity_at).toLocaleString()}</Td>
            </tr>
          ))}
        </Table>
      ) : (
        <Empty>No rooms right now.</Empty>
      )}

      <SectionHeading>Signups · last 14 days</SectionHeading>

      {signups.some((d) => d.registered + d.guests > 0) ? (
        <Table headers={["Day", "Registered", "Guests", ""]}>
          {signups.map((d) => {
            const peak = Math.max(
              ...signups.map((x) => x.registered + x.guests),
              1,
            );
            const total = d.registered + d.guests;
            return (
              <tr key={d.day} className="border-t border-line">
                <Td>{d.day}</Td>
                <Td>{d.registered}</Td>
                <Td>{d.guests}</Td>
                <td className="w-1/2 px-4 py-3">
                  <div
                    className="h-2 rounded-full bg-ink"
                    style={{ width: `${(total / peak) * 100}%`, minWidth: total ? "4px" : "0" }}
                  />
                </td>
              </tr>
            );
          })}
        </Table>
      ) : (
        <Empty>No signups in the last 14 days.</Empty>
      )}

      <SectionHeading>All users</SectionHeading>

      {allUsers.length ? (
        <Table headers={["Name", "Email", "Type", "Joined", "Last seen"]}>
          {allUsers.map((u, i) => (
            <tr key={`${u.tag ?? u.display_name}-${i}`} className="border-t border-line">
              <Td>
                {u.display_name}
                {u.tag ? (
                  <span className="ml-1.5 font-mono text-ink-soft">#{u.tag}</span>
                ) : null}
                {u.is_admin ? (
                  <span className="ml-2 rounded-full border border-line px-1.5 py-0.5 text-[10px] uppercase tracking-wide text-ink-soft">
                    admin
                  </span>
                ) : null}
              </Td>
              <Td>
                <span className="font-mono text-xs">{u.email ?? "—"}</span>
              </Td>
              <Td>{u.is_bot ? "Bot" : u.is_guest ? "Guest" : "Registered"}</Td>
              <Td>{new Date(u.created_at).toLocaleDateString()}</Td>
              <Td>
                {u.last_sign_in_at
                  ? new Date(u.last_sign_in_at).toLocaleString()
                  : "—"}
              </Td>
            </tr>
          ))}
        </Table>
      ) : (
        <Empty>No users.</Empty>
      )}

      <p className="mt-10 text-xs leading-relaxed text-ink-soft">
        Finished games are deleted 5 minutes after they end by the
        sequence-delete-finished cron, so this page is a live snapshot only —
        it cannot show historical games. Guest accounts disappear 24 hours
        after their last sign-in.
      </p>
    </div>
  );
}

function Stat({
  label,
  value,
  accent,
}: {
  label: string;
  value: number;
  accent?: boolean;
}) {
  return (
    <div className="rounded-2xl border border-line bg-surface px-4 py-3">
      <div className="text-xs text-ink-soft">{label}</div>
      <div
        className={`mt-1 font-display font-bold ${accent ? "text-ink" : "text-ink"}`}
        style={{ fontSize: "28px", letterSpacing: "-0.02em" }}
      >
        {value}
      </div>
    </div>
  );
}

function SectionHeading({ children }: { children: React.ReactNode }) {
  return (
    <h2
      className="mt-10 font-display font-bold leading-none"
      style={{ fontSize: "20px", letterSpacing: "-0.02em" }}
    >
      {children}
    </h2>
  );
}

function Table({
  headers,
  children,
}: {
  headers: string[];
  children: React.ReactNode;
}) {
  return (
    <div className="mt-4 overflow-x-auto rounded-3xl border border-line bg-surface">
      <table className="w-full text-left text-sm">
        <thead>
          <tr>
            {headers.map((h) => (
              <th key={h} className="px-4 py-3 text-xs font-medium text-ink-soft">
                {h}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>{children}</tbody>
      </table>
    </div>
  );
}

function Td({ children }: { children: React.ReactNode }) {
  return <td className="whitespace-nowrap px-4 py-3">{children}</td>;
}

function Empty({ children }: { children: React.ReactNode }) {
  return (
    <div className="mt-4 rounded-3xl border border-line bg-surface px-4 py-6 text-sm text-ink-soft">
      {children}
    </div>
  );
}
