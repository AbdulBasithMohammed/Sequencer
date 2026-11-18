import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { getCurrentUser } from "@/lib/auth/me";
import { Wordmark } from "@/components/ui/wordmark";
import { type Ban, type Player, type Room } from "./lobby-client";
import { LobbyLive } from "./lobby-live";
import { InviteFriendsPanel } from "./invite-friends-panel";

export const metadata = {
  title: "Room",
  // Belt and braces only: a signed-out crawler is bounced to /auth before
  // this ever renders, so nothing external reads this tag today. Kept so
  // the page is still correct if that redirect is ever relaxed — rooms are
  // reaped minutes after they end, so these must never be indexed.
  robots: { index: false, follow: false },
};

export default async function LobbyPage({
  params,
}: {
  params: Promise<{ code: string }>;
}) {
  const { code } = await params;
  const normalizedCode = code.toUpperCase();

  // This page re-renders on every lobby broadcast (joins, ready toggles),
  // so identity comes from the cookie claims — no auth round trip.
  const user = await getCurrentUser();
  if (!user) redirect("/auth?mode=signin");
  const supabase = await createClient();

  const { data: roomRow } = await supabase
    .from("rooms")
    .select("id")
    .eq("code", normalizedCode)
    .maybeSingle();
  if (!roomRow) redirect("/play");

  // Initial state comes from the same SECURITY DEFINER projection the
  // client reconciles against and the broadcast trigger ships. This used
  // to be a direct room_players read embedding profiles(display_name,
  // is_bot) — which broke when profiles went own-row with is_bot
  // withheld (20260902090000): the whole query failed, the lobby rendered
  // with no players (the host missing from their own room), and it stayed
  // empty until some change bumped the room version.
  const { data: snapData } = await supabase.rpc("get_lobby_snapshot", {
    p_room_id: roomRow.id,
  });
  const snap = snapData as {
    version: number;
    room: Room;
    players: Player[];
    game_id: string | null;
  } | null;
  // Null when the caller isn't seated in this room.
  if (!snap) redirect("/play");
  if (snap.room.status === "in_game" && snap.game_id) {
    redirect(`/game/${snap.game_id}`);
  }

  const roomData = snap.room;
  const players = snap.players;
  const meIsHost = roomData.host_id === user.id;

  // Host-only ban list, through an RPC for the same reason as the roster:
  // a direct room_bans read embedding profiles(display_name) now returns
  // null names, since profiles is readable own-row only.
  type BanRow = { user_id: string; display_name: string | null };
  const { data: banRows } = meIsHost
    ? await supabase.rpc("get_room_bans", { p_room_id: roomData.id })
    : { data: null };
  const bans: Ban[] = ((banRows as BanRow[] | null) ?? []).map((b) => ({
    user_id: b.user_id,
    display_name: b.display_name,
  }));

  // Three-team layouts need a wider page so each card has the same width
  // as in a two-team layout (~340px).
  const threeTeams = ["1v1v1", "2v2v2", "4v4v4"].includes(roomData.team_layout);
  const maxWidthClass = threeTeams ? "max-w-[1200px]" : "max-w-[820px]";

  return (
    <div
      className={`page-enter stagger-children mx-auto flex w-full ${maxWidthClass} flex-1 flex-col px-6 py-7 transition-[max-width] duration-500 ease-out lg:px-10`}
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

      <LobbyLive
        initialVersion={snap.version ?? 0}
        initialRoom={roomData}
        initialPlayers={players}
        bans={bans}
        currentUserId={user.id}
      />

      {!user.isAnonymous && <InviteFriendsPanel roomId={roomData.id} />}
    </div>
  );
}
