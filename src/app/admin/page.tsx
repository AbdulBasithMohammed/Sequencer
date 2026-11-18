import Link from "next/link";
import { notFound, redirect } from "next/navigation";
import { getCurrentUser } from "@/lib/auth/me";
import { createClient } from "@/lib/supabase/server";
import { TrendChart, SERIES_1, SERIES_2 } from "./charts";
import {
  FeedbackInbox,
  UnreadBadge,
  UnreadCount,
  type Feedback,
} from "./feedback";
import { PlayersList, type UserRow } from "./players";
import { countryLabel, duration, flag, fmtAgo, fmtDateTime, fmtTime } from "./format";
import { Card, Empty, Kpi, MiniRow, Pill, SectionHeader } from "./ui";

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

type RoomRow = {
  code: string;
  status: string;
  host_name: string;
  seats_taken: number;
  capacity: number;
  has_live_game: boolean;
  created_at: string;
  last_activity_at: string;
};

type SignupDay = { day: string; registered: number; guests: number };
type GameDay = { day: string; completed: number };
type CountryRow = { country: string; players: number };

type GameTotals = {
  // completed_24h is "today" in Toronto, not a rolling 24 hours.
  completed_total: number;
  completed_24h: number;
  completed_7d: number;
  avg_duration_secs: number;
  games_with_bots: number;
};

type FeedbackTotals = { total: number; last_24h: number; last_7d: number };

type Onboarding = {
  eligible: number;
  tour_seen: number;
  tour_skipped: number;
  coach_done: number;
  nudge_seen: number;
};

const SECTIONS = [
  { id: "today", label: "Today" },
  { id: "feedback", label: "Feedback" },
  { id: "players", label: "Players" },
  { id: "growth", label: "Growth" },
] as const;
type Section = (typeof SECTIONS)[number]["id"];

// Old bookmarks used ?tab=overview / ?tab=users.
const ALIASES: Record<string, Section> = { overview: "today", users: "players" };
const RANGES = [7, 30, 90];
const USER_CAP = 500;

type Db = Awaited<ReturnType<typeof createClient>>;

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
  const raw = ALIASES[params.tab ?? ""] ?? params.tab;
  const section: Section = SECTIONS.some((s) => s.id === raw)
    ? (raw as Section)
    : "today";
  const range = RANGES.includes(Number(params.range))
    ? Number(params.range)
    : 30;

  // Feedback feeds the nav's unread badge on every section, so it's always
  // fetched. It's small: 30-day retention, capped at 300 rows.
  const fbRes = await supabase.rpc("admin_feedback", { p_limit: 300 });
  const feedback = (fbRes.data ?? []) as Feedback[];
  const fbTimes = feedback.map((f) => f.created_at);

  // One clock for the whole render, handed to client islands so relative
  // times hydrate with the same text the server sent.
  // eslint-disable-next-line react-hooks/purity -- server component, renders once
  const now = Date.now();
  const ctx = { supabase, userId: user.id, now, feedback, fbTimes };

  return (
    <div className="mx-auto w-full max-w-[1240px] px-4 pb-16 pt-5 sm:px-6 lg:grid lg:grid-cols-[200px_minmax(0,1fr)] lg:gap-10 lg:pt-8">
      <aside className="lg:sticky lg:top-8 lg:self-start">
        <div className="flex items-center justify-between gap-3 lg:block">
          <Link
            href="/admin"
            className="font-display text-xl font-bold leading-none"
            style={{ letterSpacing: "-0.03em" }}
          >
            Sequencr admin
          </Link>
          <p className="text-xs text-ink-soft lg:mt-1.5">
            {fmtTime(new Date(now).toISOString()).slice(0, 5)} Toronto
          </p>
        </div>

        {/* A scrollable pill row on phones, a vertical list on desktop. */}
        <nav
          aria-label="Admin sections"
          className="-mx-4 mt-4 flex gap-1.5 overflow-x-auto px-4 pb-1 lg:mx-0 lg:mt-6 lg:flex-col lg:gap-1 lg:overflow-visible lg:px-0"
        >
          {SECTIONS.map((s) => {
            const active = s.id === section;
            return (
              <Link
                key={s.id}
                href={s.id === "today" ? "/admin" : `/admin?tab=${s.id}`}
                aria-current={active ? "page" : undefined}
                className={`flex shrink-0 items-center gap-2 rounded-full border px-3.5 py-1.5 text-sm transition-colors lg:rounded-xl lg:px-3 lg:py-2 ${
                  active
                    ? "border-ink bg-ink text-canvas"
                    : "border-line bg-surface text-ink-soft hover:text-ink lg:border-transparent lg:bg-transparent lg:hover:bg-surface"
                }`}
              >
                {s.label}
                {s.id === "feedback" ? (
                  <UnreadBadge userId={user.id} timestamps={fbTimes} now={now} />
                ) : null}
              </Link>
            );
          })}
        </nav>

        <Link
          href="/play"
          className="mt-6 hidden text-xs text-ink-soft hover:text-ink lg:block"
        >
          ← Back to Sequencr
        </Link>
      </aside>

      <main className="mt-6 min-w-0 lg:mt-0">
        {section === "today" ? <TodaySection {...ctx} /> : null}
        {section === "feedback" ? <FeedbackSection {...ctx} /> : null}
        {section === "players" ? <PlayersSection {...ctx} /> : null}
        {section === "growth" ? <GrowthSection {...ctx} range={range} /> : null}

        <Link
          href="/play"
          className="mt-10 block text-xs text-ink-soft hover:text-ink lg:hidden"
        >
          ← Back to Sequencr
        </Link>
      </main>
    </div>
  );
}

type Ctx = {
  supabase: Db;
  userId: string;
  now: number;
  feedback: Feedback[];
  fbTimes: string[];
};

/* --------------------------------------------------------------- today */

async function TodaySection({ supabase, userId, now, feedback, fbTimes }: Ctx) {
  const [overviewRes, roomsRes, totalsRes, signupsRes, gamesRes] =
    await Promise.all([
      supabase.rpc("admin_overview"),
      supabase.rpc("admin_active_rooms"),
      supabase.rpc("admin_game_totals"),
      supabase.rpc("admin_signups_by_day", { p_days: 14 }),
      supabase.rpc("admin_games_by_day", { p_days: 14 }),
    ]);
  const o = (overviewRes.data?.[0] ?? null) as Overview | null;
  const rooms = (roomsRes.data ?? []) as RoomRow[];
  const totals = (totalsRes.data?.[0] ?? null) as GameTotals | null;
  const signups = ((signupsRes.data ?? []) as SignupDay[]).slice().reverse();
  const games = ((gamesRes.data ?? []) as GameDay[]).slice().reverse();

  // Live first, then waiting rooms; each by most recent activity (the RPC's order).
  const sortedRooms = [...rooms].sort(
    (a, b) => Number(b.has_live_game) - Number(a.has_live_game),
  );
  const liveRooms = rooms.filter((r) => r.has_live_game).length;
  const latest = [...feedback]
    .sort((a, b) => b.created_at.localeCompare(a.created_at))
    .slice(0, 4);

  return (
    <>
      <SectionHeader
        title="Today"
        blurb="What's happening right now and what needs a look."
      />

      <div className="mt-5 grid grid-cols-2 gap-3 xl:grid-cols-4">
        <Kpi
          label="Playing now"
          value={o?.games_in_progress ?? 0}
          sub={`${liveRooms} live room${liveRooms === 1 ? "" : "s"} · ${o?.players_seated ?? 0} seated`}
        />
        <Kpi
          label="New players today"
          value={o?.new_24h ?? 0}
          sub={`${o?.new_7d ?? 0} in the last 7 days`}
          href="/admin?tab=players"
        />
        <Kpi
          label="Games finished today"
          value={totals?.completed_24h ?? 0}
          sub={`${totals?.completed_7d ?? 0} in the last 7 days`}
          href="/admin?tab=growth"
        />
        <Kpi
          label="Unread feedback"
          accent
          value={<UnreadCount userId={userId} timestamps={fbTimes} now={now} />}
          sub="Open the inbox"
          href="/admin?tab=feedback"
        />
      </div>

      <div className="mt-4 grid gap-4 lg:grid-cols-2">
        <Card
          title={`Rooms open · ${rooms.length}`}
          action={
            rooms.length ? (
              <span className="text-xs text-ink-soft">
                {o?.rooms_waiting ?? 0} waiting
              </span>
            ) : null
          }
        >
          {sortedRooms.length ? (
            <ul className="-my-1 max-h-[300px] overflow-y-auto">
              {sortedRooms.map((r) => (
                <li
                  key={r.code}
                  className="flex items-center gap-3 border-t border-line py-2 text-sm first:border-t-0"
                >
                  <span className="font-mono text-xs">{r.code}</span>
                  <span className="min-w-0 flex-1 truncate">{r.host_name}</span>
                  <span className="text-xs tabular-nums text-ink-soft">
                    {r.seats_taken}/{r.capacity}
                  </span>
                  <Pill tone={r.has_live_game ? "dark" : "plain"}>
                    {r.has_live_game ? "playing" : r.status}
                  </Pill>
                  <span
                    className="hidden w-16 text-right text-xs text-ink-soft sm:inline"
                    title={fmtDateTime(r.last_activity_at)}
                  >
                    {fmtAgo(r.last_activity_at, now)}
                  </span>
                </li>
              ))}
            </ul>
          ) : (
            <Empty>No rooms open right now.</Empty>
          )}
        </Card>

        <Card
          title="Latest feedback"
          action={
            <Link
              href="/admin?tab=feedback"
              className="text-xs text-ink-soft hover:text-ink"
            >
              Open inbox →
            </Link>
          }
        >
          {latest.length ? (
            <ul className="-my-1">
              {latest.map((f) => (
                <li
                  key={f.id}
                  className="border-t border-line py-2 first:border-t-0"
                >
                  <p className="line-clamp-2 break-words text-sm">{f.body}</p>
                  <p className="mt-0.5 flex flex-wrap items-center gap-x-1.5 text-xs text-ink-soft">
                    <span>{f.author_name ?? "deleted account"}</span>
                    {f.was_guest ? <Pill>guest</Pill> : null}
                    <span>· {fmtAgo(f.created_at, now)}</span>
                  </p>
                </li>
              ))}
            </ul>
          ) : (
            <Empty>No feedback in the last 30 days.</Empty>
          )}
        </Card>
      </div>

      <div className="mt-4 grid gap-4 lg:grid-cols-2">
        <Card title="Signups · 14 days">
          <TrendChart
            height={200}
            days={signups.map((d) => d.day)}
            series={[
              { name: "Registered", color: SERIES_1, values: signups.map((d) => d.registered) },
              { name: "Guests", color: SERIES_2, values: signups.map((d) => d.guests) },
            ]}
            empty="No signups in the last 14 days."
          />
        </Card>
        <Card title="Games finished · 14 days">
          <TrendChart
            height={200}
            days={games.map((d) => d.day)}
            series={[
              { name: "Completed", color: SERIES_1, values: games.map((d) => d.completed) },
            ]}
            empty="No games finished in the last 14 days."
          />
        </Card>
      </div>

      <p className="mt-6 text-xs leading-relaxed text-ink-soft">
        Rooms are a live snapshot. Longer trends, onboarding and countries are
        under{" "}
        <Link href="/admin?tab=growth" className="underline hover:text-ink">
          Growth
        </Link>
        .
      </p>
    </>
  );
}

/* ------------------------------------------------------------ feedback */

async function FeedbackSection({ supabase, userId, now, feedback }: Ctx) {
  const { data } = await supabase.rpc("admin_feedback_totals");
  const t = (data?.[0] ?? null) as FeedbackTotals | null;

  return (
    <>
      <SectionHeader
        title="Feedback"
        blurb={`${t?.last_24h ?? 0} today · ${t?.last_7d ?? 0} this week · ${t?.total ?? 0} kept (30-day retention). Registered players first.`}
      />
      <div className="mt-5">
        <FeedbackInbox userId={userId} items={feedback} now={now} />
      </div>
      <p className="mt-6 text-xs text-ink-soft">
        Read state is remembered in this browser only.
      </p>
    </>
  );
}

/* ------------------------------------------------------------- players */

async function PlayersSection({ supabase, now }: Ctx) {
  const { data } = await supabase.rpc("admin_user_list", { p_limit: USER_CAP });
  const users = (data ?? []) as UserRow[];

  return (
    <>
      <SectionHeader
        title="Players"
        blurb="Every account, newest first. Guests are removed 24 hours after their last sign-in."
      />
      <div className="mt-5">
        <PlayersList rows={users} now={now} capped={users.length >= USER_CAP} />
      </div>
    </>
  );
}

/* -------------------------------------------------------------- growth */

async function GrowthSection({ supabase, range }: Ctx & { range: number }) {
  const [overviewRes, totalsRes, signupsRes, gamesRes, onbRes, countriesRes] =
    await Promise.all([
      supabase.rpc("admin_overview"),
      supabase.rpc("admin_game_totals"),
      supabase.rpc("admin_signups_by_day", { p_days: range }),
      supabase.rpc("admin_games_by_day", { p_days: range }),
      supabase.rpc("admin_onboarding"),
      supabase.rpc("admin_countries"),
    ]);
  const o = (overviewRes.data?.[0] ?? null) as Overview | null;
  const totals = (totalsRes.data?.[0] ?? null) as GameTotals | null;
  const signups = ((signupsRes.data ?? []) as SignupDay[]).slice().reverse();
  const games = ((gamesRes.data ?? []) as GameDay[]).slice().reverse();
  const onb = (onbRes.data?.[0] ?? null) as Onboarding | null;
  const countries = ((countriesRes.data ?? []) as CountryRow[]).filter(
    (c) => c.country !== "??",
  );
  const totalKnown = countries.reduce((s, c) => s + c.players, 0);
  const botPct =
    totals?.completed_total
      ? Math.round((totals.games_with_bots / totals.completed_total) * 100)
      : 0;

  return (
    <>
      <SectionHeader
        title="Growth"
        blurb="How the player base and play volume are trending."
      >
        <div className="flex gap-1" role="group" aria-label="Chart range">
          {RANGES.map((r) => (
            <Link
              key={r}
              href={`/admin?tab=growth&range=${r}`}
              scroll={false}
              aria-current={r === range ? "true" : undefined}
              className={`rounded-full border px-3 py-1 text-xs ${
                r === range
                  ? "border-ink bg-ink text-canvas"
                  : "border-line bg-surface text-ink-soft hover:text-ink"
              }`}
            >
              {r} days
            </Link>
          ))}
        </div>
      </SectionHeader>

      <div className="mt-5 grid grid-cols-2 gap-3 xl:grid-cols-4">
        <Kpi
          label="Registered players"
          value={o?.registered_users ?? 0}
          sub={`${o?.total_users ?? 0} accounts in all`}
        />
        <Kpi
          label="Guests right now"
          value={o?.guest_users ?? 0}
          sub={`${o?.bot_users ?? 0} bot accounts`}
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
        <Kpi
          label="Games with a bot"
          value={`${botPct}%`}
          sub={`${totals?.games_with_bots ?? 0} games`}
        />
      </div>

      {/* Full width: at half width a 30- or 90-day axis has too little
          room per date label to stay legible. */}
      <Card title={`Signups · ${range} days`} className="mt-4">
        <TrendChart
          days={signups.map((d) => d.day)}
          series={[
            { name: "Registered", color: SERIES_1, values: signups.map((d) => d.registered) },
            { name: "Guests", color: SERIES_2, values: signups.map((d) => d.guests) },
          ]}
          empty={`No signups in the last ${range} days.`}
        />
      </Card>

      <Card title={`Games finished · ${range} days`} className="mt-4">
        <TrendChart
          days={games.map((d) => d.day)}
          series={[
            { name: "Completed", color: SERIES_1, values: games.map((d) => d.completed) },
          ]}
          empty={`No games finished in the last ${range} days.`}
        />
      </Card>

      <div className="mt-4 grid gap-4 lg:grid-cols-2">
        {/* Denominator is every non-bot account, including everyone who
            predates onboarding — so these climb as old accounts come back,
            and "finished the tour" is deliberately net of skips. */}
        <Card title="Onboarding">
          <MiniRow
            label="Finished the tour"
            value={(onb?.tour_seen ?? 0) - (onb?.tour_skipped ?? 0)}
            of={onb?.eligible ?? 0}
          />
          <MiniRow label="Skipped it" value={onb?.tour_skipped ?? 0} of={onb?.eligible ?? 0} />
          <MiniRow label="Played a first game" value={onb?.coach_done ?? 0} of={onb?.eligible ?? 0} />
          <MiniRow label="Saw the feedback nudge" value={onb?.nudge_seen ?? 0} of={onb?.eligible ?? 0} />
          <p className="mt-2 text-xs text-ink-soft">
            Out of {onb?.eligible ?? 0} non-bot accounts.
          </p>
        </Card>

        <Card title={`Countries · ${countries.length}`}>
          {countries.length ? (
            countries.slice(0, 8).map((c) => (
              <MiniRow
                key={c.country}
                label={`${flag(c.country)} ${countryLabel(c.country)}`}
                value={c.players}
                of={totalKnown}
              />
            ))
          ) : (
            <Empty>No countries recorded yet.</Empty>
          )}
        </Card>
      </div>

      <p className="mt-6 text-xs leading-relaxed text-ink-soft">
        Finished games are deleted 5 minutes after they end and guests 24
        hours after their last sign-in; only the daily completed-game counter
        is durable. Days are Toronto days.
      </p>
    </>
  );
}
