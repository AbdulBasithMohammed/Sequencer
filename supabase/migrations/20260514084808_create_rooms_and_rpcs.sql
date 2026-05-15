-- Phase 2.A — rooms + room_players + RLS + three RPCs.
-- Every mutation lives in a SECURITY DEFINER function; direct writes are blocked by RLS.

----------------------------------------------------------------
-- Tables
----------------------------------------------------------------

create table public.rooms (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  host_id uuid not null references public.profiles(id) on delete cascade,
  target_players int not null check (target_players in (2, 3, 4, 6, 8, 10, 12)),
  team_layout text not null default 'auto',
  turn_seconds int not null default 60 check (turn_seconds between 15 and 600),
  status text not null default 'waiting'
    check (status in ('waiting', 'in_game', 'finished', 'closed')),
  created_at timestamptz not null default now(),
  constraint code_format check (code ~ '^[A-Z0-9]{6}$')
);

create table public.room_players (
  room_id uuid not null references public.rooms(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  seat_index int not null check (seat_index >= 0),
  team int,
  ready boolean not null default false,
  joined_at timestamptz not null default now(),
  primary key (room_id, user_id),
  unique (room_id, seat_index)
);

create index room_players_user_idx on public.room_players (user_id);

----------------------------------------------------------------
-- RLS — SELECT-only for members; mutations only through RPCs.
----------------------------------------------------------------

alter table public.rooms enable row level security;
alter table public.room_players enable row level security;

create policy "Members can see their rooms"
  on public.rooms
  for select
  to authenticated
  using (
    id in (select room_id from public.room_players where user_id = auth.uid())
  );

create policy "Members can see room players"
  on public.room_players
  for select
  to authenticated
  using (
    room_id in (
      select room_id from public.room_players where user_id = auth.uid()
    )
  );

----------------------------------------------------------------
-- Helper: 6-char uppercase room code, ambiguous chars (0/O/1/I) omitted.
----------------------------------------------------------------

create or replace function public.generate_room_code()
returns text
language plpgsql
volatile
set search_path = ''
as $$
declare
  alphabet text := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; -- 32 chars, no 0/O/1/I
  code text := '';
  i int;
begin
  for i in 1..6 loop
    code := code || substring(
      alphabet from (floor(random() * length(alphabet))::int + 1) for 1
    );
  end loop;
  return code;
end;
$$;

----------------------------------------------------------------
-- RPC: create_room
----------------------------------------------------------------

create or replace function public.create_room(p_target_players int)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_room_id uuid;
  v_code text;
  v_attempts int := 0;
begin
  if v_user_id is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  if p_target_players not in (2, 3, 4, 6, 8, 10, 12) then
    raise exception 'Invalid player count: %', p_target_players using errcode = '22023';
  end if;

  -- Try until we get a unique code (extremely unlikely to need many attempts at this volume).
  loop
    v_code := public.generate_room_code();
    begin
      insert into public.rooms (code, host_id, target_players)
      values (v_code, v_user_id, p_target_players)
      returning id into v_room_id;
      exit;
    exception when unique_violation then
      v_attempts := v_attempts + 1;
      if v_attempts > 10 then
        raise exception 'Could not generate a unique room code' using errcode = 'P0001';
      end if;
    end;
  end loop;

  -- Seat the host at index 0.
  insert into public.room_players (room_id, user_id, seat_index)
  values (v_room_id, v_user_id, 0);

  return v_code;
end;
$$;

grant execute on function public.create_room(int) to authenticated;

----------------------------------------------------------------
-- RPC: join_room
----------------------------------------------------------------

create or replace function public.join_room(p_code text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_code text := upper(trim(p_code));
  v_room public.rooms;
  v_player_count int;
  v_next_seat int;
begin
  if v_user_id is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  select * into v_room from public.rooms where code = v_code;
  if not found then
    raise exception 'Room not found' using errcode = 'P0002';
  end if;
  if v_room.status <> 'waiting' then
    raise exception 'Room is not accepting players' using errcode = 'P0001';
  end if;

  -- Idempotent: already a member returns the room id.
  if exists (
    select 1 from public.room_players
    where room_id = v_room.id and user_id = v_user_id
  ) then
    return v_room.id;
  end if;

  select count(*) into v_player_count
  from public.room_players where room_id = v_room.id;
  if v_player_count >= v_room.target_players then
    raise exception 'Room is full' using errcode = 'P0001';
  end if;

  -- Assign the lowest unused seat (in case someone left and left a gap).
  select s into v_next_seat
  from generate_series(0, v_room.target_players - 1) as g(s)
  where not exists (
    select 1 from public.room_players rp
    where rp.room_id = v_room.id and rp.seat_index = g.s
  )
  order by s
  limit 1;

  insert into public.room_players (room_id, user_id, seat_index)
  values (v_room.id, v_user_id, v_next_seat);

  return v_room.id;
end;
$$;

grant execute on function public.join_room(text) to authenticated;

----------------------------------------------------------------
-- RPC: leave_room
----------------------------------------------------------------

create or replace function public.leave_room(p_room_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_room public.rooms;
  v_new_host uuid;
begin
  if v_user_id is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  select * into v_room from public.rooms where id = p_room_id;
  if not found then
    raise exception 'Room not found' using errcode = 'P0002';
  end if;

  delete from public.room_players
  where room_id = p_room_id and user_id = v_user_id;

  -- If the host just left, hand off to the next-oldest player, or close the room.
  if v_user_id = v_room.host_id then
    select user_id into v_new_host
    from public.room_players
    where room_id = p_room_id
    order by joined_at
    limit 1;

    if v_new_host is null then
      update public.rooms set status = 'closed' where id = p_room_id;
    else
      update public.rooms set host_id = v_new_host where id = p_room_id;
    end if;
  end if;
end;
$$;

grant execute on function public.leave_room(uuid) to authenticated;
