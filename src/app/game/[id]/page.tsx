import Link from "next/link";
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { Wordmark } from "@/components/ui/wordmark";
import { type BoardState } from "@/components/game/board";
import { type RosterPlayer } from "@/components/game/turn-banner";
import { GameClient } from "./game-client";
import { GameRefresher } from "./game-refresher";
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

  const supabase = await createClient();
  const {
    data: { user },
  } = await supabase.auth.getUser();
  if (!user) redirect("/auth?mode=signin");

  // deck + hands are blocked at the column-grant layer (see Phase 3.A
  // migration), so this select can never leak another player's hand even
  // if a future caller forgets and asks for everything.
  const { data: game } = await supabase
    .from("games")
    .select(
      "id, status, version, started_at, finished_at, board, turn_seat, turn_deadline, winner_team, room_id, deck_count, discard, rooms(code)",
    )
    .eq("id", id)
    .maybeSingle();
  if (!game) redirect("/play");

  type GameRow = {
    id: string;
    status: string;
    version: number;
    started_at: string;
    finished_at: string | null;
    board: BoardState;
    turn_seat: number | null;
    turn_deadline: string | null;
    winner_team: number | null;
    room_id: string;
    deck_count: number;
    discard: string[] | null;
    rooms: { code: string } | { code: string }[] | null;
  };
  const g = game as unknown as GameRow;
  const roomCode = Array.isArray(g.rooms) ? g.rooms[0]?.code : g.rooms?.code;

  const [{ data: rpRows }, { data: handData }, { data: lastMoveRows }] =
    await Promise.all([
      supabase
        .from("room_players")
        .select("user_id, seat_index, team, profiles(display_name, is_bot)")
        .eq("room_id", g.room_id)
        .order("seat_index"),
      supabase.rpc("get_my_hand", { p_game_id: g.id }),
      supabase
        .from("game_moves")
        .select("action, tile_row, tile_col")
        .eq("game_id", g.id)
        .in("action", ["place", "remove"])
        .not("tile_row", "is", null)
        .order("version", { ascending: false })
        .limit(1),
    ]);

  type LastMoveRow = {
    action: string;
    tile_row: number;
    tile_col: number;
  };
  const lmRows = (lastMoveRows ?? []) as LastMoveRow[];
  const lastMove =
    lmRows.length > 0
      ? {
          row: lmRows[0].tile_row,
          col: lmRows[0].tile_col,
          action: lmRows[0].action as "place" | "remove",
        }
      : null;

  type RpRow = {
    user_id: string;
    seat_index: number;
    team: number | null;
    profiles:
      | { display_name: string | null; is_bot: boolean }
      | { display_name: string | null; is_bot: boolean }[]
      | null;
  };
  const players: RosterPlayer[] = (rpRows ?? []).map((r: RpRow) => {
    const prof = Array.isArray(r.profiles) ? r.profiles[0] : r.profiles;
    return {
      user_id: r.user_id,
      seat_index: r.seat_index,
      team: r.team,
      display_name: prof?.display_name ?? null,
      is_me: r.user_id === user.id,
      is_bot: prof?.is_bot ?? false,
    };
  });

  const hand: string[] = Array.isArray(handData) ? (handData as string[]) : [];

  return (
    <div className="mx-auto flex w-full max-w-[1240px] flex-1 flex-col px-6 py-6 lg:px-10">
      <GameRefresher gameId={g.id} />

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

      <div className="mb-4 flex flex-wrap items-center justify-between gap-3">
        <div>
          <div className="text-[11px] font-semibold uppercase tracking-[0.2em] text-ink-soft">
            Room
          </div>
          <div
            className="font-mono font-bold leading-none text-ink"
            style={{ fontSize: 28, letterSpacing: "0.06em" }}
          >
            {roomCode ?? "?"}
          </div>
        </div>
        <div className="text-[12px] text-ink-soft">
          v<span className="font-mono font-bold text-ink">{g.version}</span>
        </div>
      </div>

      <GameClient
        gameId={g.id}
        gameVersion={g.version}
        status={g.status}
        winnerTeam={g.winner_team}
        board={g.board}
        turnSeat={g.turn_seat}
        turnDeadline={g.turn_deadline}
        players={players}
        hand={hand}
        roomCode={roomCode ?? null}
        deckCount={g.deck_count}
        discardCount={Array.isArray(g.discard) ? g.discard.length : 0}
        lastMove={lastMove}
      />
    </div>
  );
}
