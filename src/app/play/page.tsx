import { createClient } from "@/lib/supabase/server";
import { AppShell } from "@/components/app-shell";
import { CreateRoomCard, JoinRoomCard } from "./play-forms";
import { KickBanToast } from "./kick-ban-toast";
import { NoticeToast } from "./notice-toast";

export const metadata = {
  title: "Lobby — Sequencr",
};

type Stats = {
  games_played: number;
  games_won: number;
  moves_played: number;
  total_seconds: number;
};

function formatPlayTime(seconds: number): string {
  if (seconds < 60) return `${seconds}s`;
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes}m`;
  const hours = Math.floor(minutes / 60);
  const remMin = minutes % 60;
  return remMin === 0 ? `${hours}h` : `${hours}h ${remMin}m`;
}

export default async function PlayPage({
  searchParams,
}: {
  searchParams: Promise<{ kicked?: string; banned?: string; notice?: string }>;
}) {
  const { kicked, banned, notice } = await searchParams;
  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) return null;

  const { data: profile } = await supabase
    .from("profiles")
    .select("display_name")
    .eq("id", user.id)
    .maybeSingle();

  const { data: statsData } = await supabase.rpc("get_my_stats");
  const stats: Stats = (statsData as Stats) ?? {
    games_played: 0,
    games_won: 0,
    moves_played: 0,
    total_seconds: 0,
  };

  const greetingName = profile?.display_name ?? "there";
  const winRate =
    stats.games_played > 0
      ? Math.round((stats.games_won / stats.games_played) * 100)
      : null;

  return (
    <AppShell active="play">
      <div className="px-8 py-7">
        {(banned || kicked) && (
          <KickBanToast banned={banned} kicked={kicked} />
        )}
        {notice && !banned && !kicked && <NoticeToast notice={notice} />}

        <div className="mb-6">
          <div className="text-[13px] font-semibold text-ink-soft">
            Welcome back, {greetingName}.
          </div>
          <h1
            className="mt-1 font-display font-bold leading-none"
            style={{
              fontSize: "clamp(32px, 4vw, 44px)",
              letterSpacing: "-0.03em",
            }}
          >
            Pick a table.{" "}
            <span className="italic text-pink">Or start your own.</span>
          </h1>
        </div>

        <section className="mb-6 grid grid-cols-2 gap-3 lg:grid-cols-4">
          <StatCard
            label="Wins"
            value={stats.games_won.toLocaleString()}
            sub={
              stats.games_played > 0
                ? `of ${stats.games_played} games`
                : "no games yet"
            }
            accent="pink"
          />
          <StatCard
            label="Win rate"
            value={winRate == null ? "—" : `${winRate}%`}
            sub={winRate == null ? "play a game" : "all-time"}
            accent="mint"
          />
          <StatCard
            label="Moves played"
            value={stats.moves_played.toLocaleString()}
            sub="chips, jacks, swaps"
            accent="blue"
          />
          <StatCard
            label="Time at the table"
            value={formatPlayTime(stats.total_seconds)}
            sub="across every game"
            accent="butter"
          />
        </section>

        <div className="grid gap-4 lg:grid-cols-[1.3fr_1fr]">
          <CreateRoomCard />
          <JoinRoomCard />
        </div>
      </div>
    </AppShell>
  );
}

function StatCard({
  label,
  value,
  sub,
  accent,
}: {
  label: string;
  value: string;
  sub: string;
  accent: "pink" | "blue" | "mint" | "butter";
}) {
  const color =
    accent === "pink"
      ? "var(--color-pink)"
      : accent === "blue"
        ? "var(--color-blue)"
        : accent === "mint"
          ? "var(--color-mint)"
          : "var(--color-butter)";
  return (
    <div
      className="rounded-2xl border border-line bg-surface px-4 py-4"
      style={{ borderTopWidth: 3, borderTopColor: color }}
    >
      <div className="text-[11px] font-semibold uppercase tracking-[0.18em] text-ink-soft">
        {label}
      </div>
      <div
        className="mt-1 font-display font-bold leading-none text-ink"
        style={{ fontSize: 28, letterSpacing: "-0.02em" }}
      >
        {value}
      </div>
      <div className="mt-1 text-[11px] text-ink-soft">{sub}</div>
    </div>
  );
}
