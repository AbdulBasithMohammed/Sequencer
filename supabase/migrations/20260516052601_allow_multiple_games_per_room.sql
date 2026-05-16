-- Rematch fix: allow multiple games per room over the room's lifetime.
--
-- The original games table had `room_id uuid unique` (one game per
-- room ever), which was fine until rematch support landed. After a
-- game finishes the row stays for history; start_game then INSERTs a
-- new game row and the unique constraint blows up. Lobby and queries
-- that fetch "the current game for this room" now pick the most
-- recent row by started_at.
--
-- The non-unique index games_room_idx already covers lookups by
-- room_id, so the constraint drop has no perf impact.

alter table public.games drop constraint if exists games_room_id_key;
