import { notFound, redirect } from "next/navigation";
import { getCurrentUser } from "@/lib/auth/me";
import { createClient } from "@/lib/supabase/server";
import { TrendChart, SERIES_1, SERIES_2 } from "./charts";
import { RoomsTable, UsersTable, type RoomRow, type UserRow } from "./tables";
import { countryLabel, duration, flag, fmtDateTime } from "./format";

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

type SignupDay = { day: string; registered: number; guests: number };
type GameDay = { day: string; completed: number };
type CountryRow = { country: string; players: number };

type GameTotals = {
  completed_total: number;
  completed_24h: number;
  completed_7d: number;
  avg_duration_secs: number;
  games_with_bots: number;
};

type Feedback = {
  id: string;
  author_name: string | null;
  author_tag: string | null;
  was_guest: boolean;
  body: string;
  page: string | null;
  created_at: string;
};

type FeedbackTotals = { total: number; last_24h: number; last_7d: number };

const TABS = ["overview", "feedback", "users"] as const;
type Tab = (typeof TABS)[number];
const RANGES = [7, 30, 90];

export default async function AdminPage({
  searchParams,
}: {
  searchParams: Promise<{ tab?: string; range?: string }>;
}) {
  const user = await getCurrentUser();
  if (!user) redirect("/login");

  const supabase = await createClient();

  // The RPCs each re-check this themselves; this call just decides whether
  // the route exists at all, so non-admins get a 404 rather than a broken page.
  const { data: isAdmin } = await supabase.rpc("current_user_is_admin");
  if (!isAdmin) notFound();

  const params = await searchParams;
  const tab: Tab = (TABS as readonly string[]).includes(params.tab ?? "")
    ? (params.tab as Tab)
    : "overview";
  const range = RANGES.includes(Number(params.range))
    ? Number(params.range)
    : 30;

  // Always shown, so always fetched. Everything else is per-tab, so a
  // visit costs one tab's worth of queries rather than all of them.
  const [overviewRes, fbTotalsRes] = await Promise.all([
    supabase.rpc("admin_overview"),
    supabase.rpc("admin_feedback_totals"),
  ]);
  const o = (overviewRes.data?.[0] ?? null) as Overview | null;
  const fbTotals = (fbTotalsRes.data?.[0] ?? null) as FeedbackTotals | null;

  return (
    <div className="mx-auto flex w-full max-w-[1180px] flex-col px-6 py-8 sm:px-8">
      <div className="flex flex-wrap items-baseline justify-between gap-2">
        <h1
          className="font-display font-bold leading-none"
          style={{ fontSize: "clamp(30px, 4vw, 40px)", letterSpacing: "-0.03em" }}
        >
          Admin
        </h1>
        <span className="text-xs text-ink-soft">
          {fmtDateTime(new Date().toISOString())} Toronto
        </span>
      </div>

      <nav className="mt-5 flex gap-1 border-b border-line">
        <TabLink current={tab} tab="overview" range={range}>
          Overview
        </TabLink>
        <TabLink current={tab} tab="feedback" range={range}>
          Feedback
          {fbTotals?.last_7d ? ` · ${fbTotals.last_7d}` : ""}
        </TabLink>
        <TabLink current={tab} tab="users" range={range}>
          Users · {o?.total_users ?? 0}
        </TabLink>
      </nav>

      {tab === "overview" ? (
        <OverviewTab supabase={supabase} o={o} range={range} />
      ) : null}
      {tab === "feedback" ? (
        <FeedbackTab supabase={supabase} totals={fbTotals} />
      ) : null}
      {tab === "users" ? <UsersTab supabase={supabase} /> : null}
    </div>
  );
}

/* ---------------------------------------------------------------- tabs */

type Db = Awaited<ReturnType<typeof createClient>>;

async function OverviewTab({
  supabase,
  o,
  range,
}: {
  supabase: Db;
  o: Overview | null;
  range: number;
}) {
  const [roomsRes, signupsRes, totalsRes, gamesRes] = await Promise.all([
    supabase.rpc("admin_active_rooms"),
    supabase.rpc("admin_signups_by_day", { p_days: range }),
    supabase.rpc("admin_game_totals"),
    supabase.rpc("admin_games_by_day", { p_days: range }),
  ]);

  const rooms = (roomsRes.data ?? []) as RoomRow[];
  const signups = ((signupsRes.data ?? []) as SignupDay[]).slice().reverse();
  const totals = (totalsRes.data?.[0] ?? null) as GameTotals | null;
  const games = ((gamesRes.data ?? []) as GameDay[]).slice().reverse();
  const liveRooms = rooms.filter((r) => r.has_live_game).length;

  return (
    <>
      <div className="mt-6 grid grid-cols-2 gap-3 lg:grid-cols-4">
        <Kpi
          label="Players"
          value={o?.total_users ?? 0}
          sub={`${o?.registered_users ?? 0} registered`}
        />
        <Kpi
          label="New today"
          value={o?.new_24h ?? 0}
          sub={`${o?.new_7d ?? 0} this week`}
        />
        <Kpi
          label="Playing now"
          value={o?.games_in_progress ?? 0}
          sub={`${liveRooms} live room${liveRooms === 1 ? "" : "s"}`}
        />
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

      <div className="mt-5 flex items-center justify-end gap-1">
        {RANGES.map((r) => (
          <a
            key={r}
            href={`/admin?tab=overview&range=${r}`}
            className={`rounded-full border px-3 py-1 text-xs ${
              r === range
                ? "border-line bg-ink text-canvas"
                : "border-line text-ink-soft hover:text-ink"
            }`}
          >
            {r} days
          </a>
        ))}
      </div>

      {/* Full width, not side by side. At half width the date axis had
          roughly 54px per label to work with, which is why it was
          illegible — the columns need the whole row. */}
      <Card title={`Signups · ${range} days`} className="mt-2">
        <TrendChart
          days={signups.map((d) => d.day)}
          series={[
            {
              name: "Registered",
              color: SERIES_1,
              values: signups.map((d) => d.registered),
            },
            {
              name: "Guests",
              color: SERIES_2,
              values: signups.map((d) => d.guests),
            },
          ]}
          empty={`No signups in the last ${range} days.`}
        />
      </Card>

      <Card title={`Games finished · ${range} days`} className="mt-4">
        <TrendChart
          days={games.map((d) => d.day)}
          series={[
            {
              name: "Completed",
              color: SERIES_1,
              values: games.map((d) => d.completed),
            },
          ]}
          empty="Nothing recorded yet — tracking starts from the deploy that added the counter."
        />
      </Card>

      <div className="mt-4 grid gap-4 lg:grid-cols-2">
        <Card title="Who's signed up">
          <MiniRow
            label="Registered"
            value={o?.registered_users ?? 0}
            of={o?.total_users ?? 0}
          />
          <MiniRow
            label="Guests"
            value={o?.guest_users ?? 0}
            of={o?.total_users ?? 0}
          />
          <MiniRow
            label="Bots"
            value={o?.bot_users ?? 0}
            of={o?.total_users ?? 0}
          />
        </Card>

        <Card title="Rooms right now">
          <MiniRow
            label="Waiting in lobby"
            value={o?.rooms_waiting ?? 0}
            of={o?.rooms_total ?? 0}
          />
          <MiniRow
            label="In game"
            value={o?.rooms_in_game ?? 0}
            of={o?.rooms_total ?? 0}
          />
          <MiniRow
            label="Seated players"
            value={o?.players_seated ?? 0}
            of={o?.players_seated ?? 0}
          />
        </Card>
      </div>

      {rooms.length > 0 ? (
        <Card title={`Live rooms · ${rooms.length}`} className="mt-4">
          <RoomsTable rows={rooms} />
        </Card>
      ) : null}

      <p className="mt-8 text-xs leading-relaxed text-ink-soft">
        Rooms and games are a live snapshot — finished games are deleted 5
        minutes after they end, and guests disappear 24 hours after their last
        sign-in. Only the daily completed-game counter is durable.
      </p>
    </>
  );
}

async function FeedbackTab({
  supabase,
  totals,
}: {
  supabase: Db;
  totals: FeedbackTotals | null;
}) {
  const { data } = await supabase.rpc("admin_feedback", { p_limit: 200 });
  const feedback = (data ?? []) as Feedback[];

  return (
    <>
      <div className="mt-6 grid grid-cols-3 gap-3">
        <Kpi label="All time" value={totals?.total ?? 0} sub="kept 30 days" />
        <Kpi label="Last 24h" value={totals?.last_24h ?? 0} />
        <Kpi label="This week" value={totals?.last_7d ?? 0} />
      </div>

      {feedback.length ? (
        <ul className="mt-4 flex flex-col gap-2">
          {feedback.map((f, i) => (
            <li key={f.id}>
              {/* Rows arrive registered-first; mark where guest feedback
                  starts so the low-priority pile is obvious without
                  reading each byline. */}
              {f.was_guest && !feedback[i - 1]?.was_guest ? (
                <p className="mb-2 mt-5 text-[11px] uppercase tracking-wide text-ink-soft">
                  From guests · lower priority
                </p>
              ) : null}
              <div
                className={`rounded-2xl border border-line px-4 py-3 ${
                  f.was_guest ? "" : "bg-surface"
                }`}
              >
                <p
                  className={`whitespace-pre-wrap text-sm ${
                    f.was_guest ? "text-ink-soft" : ""
                  }`}
                >
                  {f.body}
                </p>
                <p className="mt-2 flex flex-wrap items-center gap-x-2 text-[11px] text-ink-soft">
                  <span>{f.author_name ?? "deleted account"}</span>
                  {f.author_tag ? (
                    <span className="font-mono">#{f.author_tag}</span>
                  ) : null}
                  {f.was_guest ? (
                    <span className="rounded-full border border-line px-1.5 py-0.5 text-[10px] uppercase">
                      guest
                    </span>
                  ) : null}
                  <span>·</span>
                  <span>{fmtDateTime(f.created_at)}</span>
                  {f.page ? (
                    <>
                      <span>·</span>
                      <span className="font-mono">{f.page}</span>
                    </>
                  ) : null}
                </p>
              </div>
            </li>
          ))}
        </ul>
      ) : (
        <Card title="Nothing yet" className="mt-4">
          <p className="text-sm text-ink-soft">
            No feedback has come in. The button sits in the sidebar on every
            signed-in page.
          </p>
        </Card>
      )}
    </>
  );
}

async function UsersTab({ supabase }: { supabase: Db }) {
  const [usersRes, countriesRes] = await Promise.all([
    supabase.rpc("admin_user_list", { p_limit: 300 }),
    supabase.rpc("admin_countries"),
  ]);
  const users = (usersRes.data ?? []) as UserRow[];
  const countries = (countriesRes.data ?? []) as CountryRow[];
  const known = countries.filter((c) => c.country !== "??");
  const totalKnown = known.reduce((s, c) => s + c.players, 0);

  return (
    <>
      {known.length ? (
        <Card title={`Countries · ${known.length}`} className="mt-6">
          {known.slice(0, 8).map((c) => (
            <MiniRow
              key={c.country}
              label={`${flag(c.country)} ${countryLabel(c.country)}`}
              value={c.players}
              of={totalKnown}
            />
          ))}
        </Card>
      ) : null}

      <Card title={`All users · ${users.length}`} className="mt-4">
        <p className="-mt-1 mb-2 text-[11px] text-ink-soft">
          Click any column heading to sort.
        </p>
        <UsersTable rows={users} />
        <p className="mt-3 text-xs text-ink-soft">
          Country is captured from the edge on a signed-in visit and set once.
          Accounts that predate this show — until their next visit; there is no
          historical geo to backfill from.
        </p>
      </Card>
    </>
  );
}

/* ------------------------------------------------------------ elements */

function TabLink({
  current,
  tab,
  range,
  children,
}: {
  current: Tab;
  tab: Tab;
  range: number;
  children: React.ReactNode;
}) {
  const active = current === tab;
  return (
    <a
      href={`/admin?tab=${tab}&range=${range}`}
      className={`-mb-px border-b-2 px-3 py-2 text-sm ${
        active
          ? "border-ink font-medium text-ink"
          : "border-transparent text-ink-soft hover:text-ink"
      }`}
    >
      {children}
    </a>
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
      <span className="w-44 shrink-0 truncate text-sm">{label}</span>
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
