-- Phase 2.D — minimal games table + start_game RPC + Start button wiring.
--
-- This is the MINIMAL games schema needed to satisfy 2.D ("creates a games row
-- and redirects — no gameplay yet"). Phase 3.A will ALTER this table to add
-- deck/discard/hands/board/turn_seat/turn_deadline/sequences/winner_team and
-- the game_moves log.

----------------------------------------------------------------
-- Table
----------------------------------------------------------------

create table public.games (
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null unique references public.rooms(id) on delete cascade,
  host_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'in_game'
    check (status in ('in_game', 'finished')),
  version int not null default 0,
  started_at timestamptz not null default now(),
  finished_at timestamptz
);

create index games_room_idx on public.games (room_id);

----------------------------------------------------------------
-- RLS — members of the room can SELECT; mutations only via RPC.
----------------------------------------------------------------

alter table public.games enable row level security;

create policy "Members can see their games"
  on public.games
  for select
  to authenticated
  using (
    room_id in (
      select room_id from public.room_players where user_id = (select auth.uid())
    )
  );

----------------------------------------------------------------
-- start_game: host flips the room to 'in_game' and inserts a games row.
-- Preconditions: caller is host, room is 'waiting', ≥2 players, all
-- non-host players ready.
----------------------------------------------------------------

create or replace function public.start_game(p_code text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller uuid := auth.uid();
  v_room_id uuid;
  v_host_id uuid;
  v_status text;
  v_total int;
  v_non_host_total int;
  v_non_host_ready int;
  v_game_id uuid;
begin
  if v_caller is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  select id, host_id, status
    into v_room_id, v_host_id, v_status
  from public.rooms
  where code = upper(p_code);

  if v_room_id is null then
    raise exception 'Room not found' using errcode = 'P0002';
  end if;
  if v_caller <> v_host_id then
    raise exception 'Only the host can start the game' using errcode = '42501';
  end if;
  if v_status <> 'waiting' then
    raise exception 'Room is not in the waiting state' using errcode = '22023';
  end if;

  select
    count(*),
    count(*) filter (where user_id <> v_host_id),
    count(*) filter (where user_id <> v_host_id and ready)
  into v_total, v_non_host_total, v_non_host_ready
  from public.room_players
  where room_id = v_room_id;

  if v_total < 2 then
    raise exception 'Need at least 2 players to start' using errcode = '22023';
  end if;
  if v_non_host_ready <> v_non_host_total then
    raise exception 'Not all players are ready' using errcode = '22023';
  end if;

  insert into public.games (room_id, host_id)
  values (v_room_id, v_host_id)
  returning id into v_game_id;

  update public.rooms set status = 'in_game' where id = v_room_id;

  return v_game_id;
end;
$$;

grant execute on function public.start_game(text) to authenticated;
