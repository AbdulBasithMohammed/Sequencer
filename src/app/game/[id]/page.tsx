import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { getCurrentUser } from "@/lib/auth/me";
import { Wordmark } from "@/components/ui/wordmark";
import { GameClient } from "./game-client";
import { parseSnapshot } from "./snapshot";
import { MuteToggle } from "@/components/game/mute-toggle";

export const metadata = {
  title: "Game",
};

export default async function GamePage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;

  // Identity from the cookie claims (no auth round trip); the whole page
  // boots from one SECURITY DEFINER RPC instead of four queries. After the
  // initial render, turns stream in over the broadcast channel and never
  // re-run this server component.
  const user = await getCurrentUser();
  if (!user) redirect("/auth?mode=signin");

  const supabase = await createClient();
  const { data } = await supabase.rpc("get_game_snapshot", {
    p_game_id: id,
  });
  const snapshot = parseSnapshot(data, user.id);
  if (!snapshot) redirect("/play");

  return (
    <div className="mx-auto flex w-full max-w-[1240px] flex-1 flex-col px-6 py-6 lg:px-10">
      <header className="mb-6 flex items-center justify-between">
        <Link href="/" aria-label="Sequencr home">
          <Wordmark size={22} accent="pink" />
        </Link>
        <div className="flex items-center gap-3">
          <MuteToggle />
          <Link
            href="/play"
            className="text-[13px] font-semibold text-ink-soft hover:text-ink"
          >
            ← Back to play
          </Link>
        </div>
      </header>

      <GameClient gameId={id} initialSnapshot={snapshot} myUserId={user.id} />
    </div>
  );
}
