import { type BoardState } from "@/components/game/board";
import { type RosterPlayer } from "@/components/game/turn-banner";

// Shared shape for the get_game_snapshot RPC (server page boot) and the
// fat `update` broadcast payload (live turns). Both carry the same public
// projection of the games row, so the client can apply either one to its
// local state with the same code path.

export type LastMove = {
  row: number;
  col: number;
  action: "place" | "remove";
};

export type LiveGame = {
  version: number;
  status: string;
  board: BoardState;
  turnSeat: number | null;
  turnDeadline: string | null;
  winnerTeam: number | null;
  deckCount: number;
  discardCount: number;
};

type RawGameFields = {
  version: number;
  status: string;
  board: BoardState;
  turn_seat: number | null;
  turn_deadline: string | null;
  winner_team: number | null;
  deck_count: number;
  discard_count: number;
};

export type GameSnapshot = {
  live: LiveGame;
  roomCode: string | null;
  players: RosterPlayer[];
  hand: string[];
  lastMove: LastMove | null;
};

export function liveGameFromRaw(raw: RawGameFields): LiveGame {
  return {
    version: raw.version,
    status: raw.status,
    board: raw.board,
    turnSeat: raw.turn_seat,
    turnDeadline: raw.turn_deadline,
    winnerTeam: raw.winner_team,
    deckCount: raw.deck_count,
    discardCount: raw.discard_count,
  };
}

export function parseSnapshot(
  data: unknown,
  myUserId: string,
): GameSnapshot | null {
  if (!data || typeof data !== "object") return null;
  const raw = data as RawGameFields & {
    room_code: string | null;
    players: {
      user_id: string;
      seat_index: number;
      team: number | null;
      display_name: string | null;
      is_bot: boolean;
    }[];
    hand: string[];
    last_move: { action: "place" | "remove"; row: number; col: number } | null;
  };
  if (typeof raw.version !== "number") return null;

  return {
    live: liveGameFromRaw(raw),
    roomCode: raw.room_code ?? null,
    players: (raw.players ?? []).map((p) => ({
      user_id: p.user_id,
      seat_index: p.seat_index,
      team: p.team,
      display_name: p.display_name,
      is_me: p.user_id === myUserId,
      is_bot: p.is_bot,
    })),
    hand: Array.isArray(raw.hand) ? raw.hand : [],
    lastMove: raw.last_move
      ? {
          row: raw.last_move.row,
          col: raw.last_move.col,
          action: raw.last_move.action,
        }
      : null,
  };
}

// A version bump changes at most one cell's ownership (place or remove),
// so the changed tile can be derived by diffing consecutive boards —
// no game_moves query needed on the live path.
export function diffBoards(
  prev: BoardState,
  next: BoardState,
): LastMove | null {
  for (let r = 0; r < 10; r++) {
    for (let c = 0; c < 10; c++) {
      const a = prev?.[r]?.[c]?.team ?? null;
      const b = next?.[r]?.[c]?.team ?? null;
      if (a === b) continue;
      return { row: r, col: c, action: b === null ? "remove" : "place" };
    }
  }
  return null;
}
