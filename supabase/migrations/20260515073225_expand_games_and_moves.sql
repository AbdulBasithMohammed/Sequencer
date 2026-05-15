-- Phase 3.A — Expand games + create game_moves + RLS.
--
-- Phase 2.D landed a minimal games row (id, room_id, host_id, status, version,
-- started_at, finished_at) so the Start button had a thing to insert. This
-- migration adds every column the rules engine and renderer will read or
-- write per PRD §8, plus the append-only game_moves log keyed by version.
--
-- Hand privacy is enforced at the column-GRANT layer: clients can SELECT
-- everything on `games` EXCEPT `deck` and `hands`. Those two are reachable
-- only through SECURITY DEFINER RPCs (e.g. get_my_hand — added in 3.B), so
-- there is no way to query another player's hand from the client.

----------------------------------------------------------------
-- Extend the games table with gameplay columns
----------------------------------------------------------------

alter table public.games
  add column deck jsonb not null default '[]'::jsonb,
  add column discard jsonb not null default '[]'::jsonb,
  add column hands jsonb not null default '{}'::jsonb,
  add column board jsonb not null default '[]'::jsonb,
  add column turn_seat int,
  add column turn_deadline timestamptz,
  add column sequences jsonb not null default '[]'::jsonb,
  add column winner_team int;

----------------------------------------------------------------
-- game_moves: append-only log, one row per accepted RPC mutation.
-- Keyed by (game_id, version) so reconnect can replay missed deltas.
----------------------------------------------------------------

create table public.game_moves (
  id bigserial primary key,
  game_id uuid not null references public.games(id) on delete cascade,
  version int not null,
  user_id uuid references public.profiles(id) on delete set null,
  action text not null
    check (action in ('place', 'remove', 'swap_dead', 'auto_discard', 'system')),
  card text,
  tile_row int check (tile_row is null or tile_row between 0 and 9),
  tile_col int check (tile_col is null or tile_col between 0 and 9),
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (game_id, version)
);

-- Reconnect query: "give me every move for this game since version N"
create index game_moves_game_version_idx
  on public.game_moves (game_id, version);

----------------------------------------------------------------
-- RLS: room members can read their game's move log. No INSERT/UPDATE/DELETE
-- policy — only SECURITY DEFINER RPCs may write moves.
----------------------------------------------------------------

alter table public.game_moves enable row level security;

create policy "Members can see moves for their games"
  on public.game_moves
  for select
  to authenticated
  using (
    game_id in (
      select g.id
      from public.games g
      join public.room_players rp on rp.room_id = g.room_id
      where rp.user_id = (select auth.uid())
    )
  );

----------------------------------------------------------------
-- Hand & deck privacy via column-level grants.
--
-- RLS already restricts WHICH rows a client sees (room members only).
-- Column grants restrict WHICH columns. Combined: a member can SELECT
-- their game's row but the `deck` and `hands` columns are blocked at
-- the privilege layer, so even `select *` returns no value for them.
--
-- The RPCs that DO need to read these columns (start_game shuffle,
-- play_move validation, get_my_hand, auto_advance_turn) run as
-- SECURITY DEFINER and bypass column grants entirely.
----------------------------------------------------------------

revoke select on public.games from authenticated;

grant select (
  id,
  room_id,
  host_id,
  status,
  version,
  started_at,
  finished_at,
  discard,
  board,
  turn_seat,
  turn_deadline,
  sequences,
  winner_team
) on public.games to authenticated;
