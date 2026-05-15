import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { Wordmark } from "@/components/ui/wordmark";

export const metadata = {
  title: "Game — Sequencr",
};

export default async function GamePage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/auth?mode=signin");

  const { data: game } = await supabase
    .from("games")
    .select("id, status, started_at, room_id, rooms(code)")
    .eq("id", id)
    .maybeSingle();
  if (!game) redirect("/play");

  type GameRow = {
    id: string;
    status: string;
    started_at: string;
    room_id: string;
    rooms: { code: string } | { code: string }[] | null;
  };
  const g = game as unknown as GameRow;
  const roomCode = Array.isArray(g.rooms) ? g.rooms[0]?.code : g.rooms?.code;

  return (
    <div className="mx-auto flex w-full max-w-[820px] flex-1 flex-col px-6 py-7 lg:px-10">
      <header className="mb-10 flex items-center justify-between">
        <Link href="/" aria-label="Sequencr home">
          <Wordmark size={22} accent="pink" />
        </Link>
        <Link
          href="/play"
          className="text-[13px] font-semibold text-ink-soft hover:text-ink"
        >
          ← Back to play
        </Link>
      </header>

      <div className="flex flex-1 flex-col items-center justify-center text-center">
        <div className="text-[12px] font-semibold uppercase tracking-[0.2em] text-ink-soft">
          Game started
        </div>
        <h1
          className="mt-2 font-display font-bold leading-none"
          style={{ fontSize: "clamp(32px, 4vw, 44px)", letterSpacing: "-0.03em" }}
        >
          Room <span className="text-pink">{roomCode ?? "?"}</span>
        </h1>
        <p className="mt-4 max-w-[420px] text-[14px] text-ink-soft">
          Gameplay lands in Phase 3. For now this is the placeholder — the room
          is locked, the <code className="font-mono text-[12px]">games</code>{" "}
          row exists, and everyone is here.
        </p>
        <div className="mt-6 rounded-2xl border border-line bg-surface px-4 py-3 text-left">
          <div className="text-[11px] font-semibold uppercase tracking-[0.15em] text-ink-soft">
            Game ID
          </div>
          <div className="mt-1 font-mono text-[13px] text-ink">{g.id}</div>
        </div>
      </div>
    </div>
  );
}
