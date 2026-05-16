import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { Wordmark } from "@/components/ui/wordmark";
import {
  LobbyClient,
  type Ban,
  type Player,
  type Room,
  type TokenColor,
} from "./lobby-client";

export const metadata = {
  title: "Room — Sequencr",
};

export default async function LobbyPage({
  params,
}: {
  params: Promise<{ code: string }>;
}) {
  const { code } = await params;
  const normalizedCode = code.toUpperCase();

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/auth?mode=signin");

  const { data: room } = await supabase
    .from("rooms")
    .select("*")
    .eq("code", normalizedCode)
    .maybeSingle();
  if (!room) redirect("/play");

  if (room.status === "in_game") {
    const { data: game } = await supabase
      .from("games")
      .select("id")
      .eq("room_id", room.id)
      .order("started_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    if (game) redirect(`/game/${game.id}`);
  }

  const meIsHost = room.host_id === user.id;

  type PlayerRow = {
    seat_index: number;
    user_id: string;
    team: number | null;
    ready: boolean;
    joined_at: string;
    token_color: TokenColor;
    profiles: { display_name: string } | null;
  };
  type BanRow = {
    user_id: string;
    profiles: { display_name: string } | null;
  };

  const [playersResult, bansResult] = await Promise.all([
    supabase
      .from("room_players")
      .select(
        "seat_index, user_id, team, ready, joined_at, token_color, profiles(display_name)",
      )
      .eq("room_id", room.id)
      .order("seat_index"),
    meIsHost
      ? supabase
          .from("room_bans")
          .select("user_id, profiles(display_name)")
          .eq("room_id", room.id)
          .order("banned_at", { ascending: false })
      : Promise.resolve({ data: null as BanRow[] | null }),
  ]);

  const players: Player[] = (
    (playersResult.data as PlayerRow[] | null) ?? []
  ).map((p) => ({
    seat_index: p.seat_index,
    user_id: p.user_id,
    team: p.team,
    ready: p.ready,
    joined_at: p.joined_at,
    token_color: p.token_color,
    display_name: p.profiles?.display_name ?? null,
  }));

  const bans: Ban[] = ((bansResult.data as BanRow[] | null) ?? []).map(
    (b) => ({
      user_id: b.user_id,
      display_name: b.profiles?.display_name ?? null,
    }),
  );

  const roomData: Room = {
    id: room.id,
    code: room.code,
    host_id: room.host_id,
    target_players: room.target_players,
    team_layout: room.team_layout,
    status: room.status,
  };

  // Three-team layouts need a wider page so each card has the same width
  // as in a two-team layout (~340px).
  const threeTeams = ["1v1v1", "2v2v2", "4v4v4"].includes(room.team_layout);
  const maxWidthClass = threeTeams ? "max-w-[1200px]" : "max-w-[820px]";

  return (
    <div
      className={`mx-auto flex w-full ${maxWidthClass} flex-1 flex-col px-6 py-7 lg:px-10`}
    >
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

      <LobbyClient
        room={roomData}
        players={players}
        bans={bans}
        currentUserId={user.id}
      />
    </div>
  );
}
