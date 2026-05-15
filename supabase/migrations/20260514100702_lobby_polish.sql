-- Lobby polish: team layouts + auto-team assignment, bans, delete empty rooms.
-- Affects: create_room, join_room, leave_room (replaced), plus new
-- compute_team helper, room_bans table, ban_player / unban_player /
-- set_team_layout RPCs.

----------------------------------------------------------------
-- room_bans table
----------------------------------------------------------------

create table public.room_bans (
  room_id uuid not null references public.rooms(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  banned_at timestamptz not null default now(),
  primary key (room_id, user_id)
);

alter table public.room_bans enable row level security;

-- Hosts see their own room's bans. Banned users intentionally can't see this
-- table — they get the rejection message from join_room.
create policy "Hosts can see their bans"
  on public.room_bans
  for select
  to authenticated
  using (
    room_id in (select id from public.rooms where host_id = auth.uid())
  );

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'room_bans'
  ) then
    alter publication supabase_realtime add table public.room_bans;
  end if;
end $$;

----------------------------------------------------------------
-- compute_team(seat, target_players, layout): canonical Sequence layouts.
----------------------------------------------------------------

create or replace function public.compute_team(
  p_seat_index int,
  p_target_players int,
  p_layout text
) returns int
language plpgsql
immutable
set search_path = ''
as $$
begin
  return case p_layout
    when '1v1'     then p_seat_index + 1
    when '1v1v1'   then p_seat_index + 1
    when '2v2'     then (p_seat_index % 2) + 1
    when '4v4'     then (p_seat_index % 2) + 1
    when '5v5'     then (p_seat_index % 2) + 1
    when '3v3'     then (p_seat_index / 3) + 1
    when '6v6'     then (p_seat_index / 6) + 1
    when '2v2v2'   then (p_seat_index % 3) + 1
    when '4v4v4'   then (p_seat_index / 4) + 1
    else 1
  end;
end;
$$;

grant execute on function public.compute_team(int, int, text) to authenticated;

----------------------------------------------------------------
-- Default layout for a player count.
----------------------------------------------------------------

create or replace function public.default_layout_for(p_target_players int)
returns text
language sql
immutable
set search_path = ''
as $$
  select case p_target_players
    when 2  then '1v1'
    when 3  then '1v1v1'
    when 4  then '2v2'
    when 6  then '3v3'
    when 8  then '4v4'
    when 10 then '5v5'
    when 12 then '6v6'
  end;
$$;

----------------------------------------------------------------
-- Replace create_room: pick default layout, assign host's team.
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
  v_layout text;
begin
  if v_user_id is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  if p_target_players not in (2, 3, 4, 6, 8, 10, 12) then
    raise exception 'Invalid player count: %', p_target_players using errcode = '22023';
  end if;

  v_layout := public.default_layout_for(p_target_players);

  loop
    v_code := public.generate_room_code();
    begin
      insert into public.rooms (code, host_id, target_players, team_layout)
      values (v_code, v_user_id, p_target_players, v_layout)
      returning id into v_room_id;
      exit;
    exception when unique_violation then
      v_attempts := v_attempts + 1;
      if v_attempts > 10 then
        raise exception 'Could not generate a unique room code' using errcode = 'P0001';
      end if;
    end;
  end loop;

  insert into public.room_players (room_id, user_id, seat_index, team)
  values (
    v_room_id,
    v_user_id,
    0,
    public.compute_team(0, p_target_players, v_layout)
  );

  return v_code;
end;
$$;

----------------------------------------------------------------
-- Replace join_room: ban check + auto-team assignment.
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

  if exists (
    select 1 from public.room_bans
    where room_id = v_room.id and user_id = v_user_id
  ) then
    raise exception 'You are banned from this room' using errcode = '42501';
  end if;

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

  select s into v_next_seat
  from generate_series(0, v_room.target_players - 1) as g(s)
  where not exists (
    select 1 from public.room_players rp
    where rp.room_id = v_room.id and rp.seat_index = g.s
  )
  order by s
  limit 1;

  insert into public.room_players (room_id, user_id, seat_index, team)
  values (
    v_room.id,
    v_user_id,
    v_next_seat,
    public.compute_team(v_next_seat, v_room.target_players, v_room.team_layout)
  );

  return v_room.id;
end;
$$;

----------------------------------------------------------------
-- Replace leave_room: delete empty rooms entirely (cascades cleanup).
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

  if v_user_id = v_room.host_id then
    select user_id into v_new_host
    from public.room_players
    where room_id = p_room_id
    order by joined_at
    limit 1;

    if v_new_host is null then
      -- Empty room — wipe it. CASCADE handles room_players + room_bans.
      delete from public.rooms where id = p_room_id;
    else
      update public.rooms set host_id = v_new_host where id = p_room_id;
    end if;
  else
    -- A non-host left — clean up if they happened to be the last one.
    if not exists (select 1 from public.room_players where room_id = p_room_id) then
      delete from public.rooms where id = p_room_id;
    end if;
  end if;
end;
$$;

----------------------------------------------------------------
-- ban_player: host kicks + records ban so they can't rejoin.
----------------------------------------------------------------

create or replace function public.ban_player(
  p_room_id uuid,
  p_user_id uuid
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller uuid := auth.uid();
  v_host uuid;
begin
  if v_caller is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  select host_id into v_host from public.rooms where id = p_room_id;
  if v_host is null then
    raise exception 'Room not found' using errcode = 'P0002';
  end if;
  if v_caller <> v_host then
    raise exception 'Only the host can ban players' using errcode = '42501';
  end if;
  if p_user_id = v_caller then
    raise exception 'You cannot ban yourself' using errcode = '22023';
  end if;

  delete from public.room_players
  where room_id = p_room_id and user_id = p_user_id;

  insert into public.room_bans (room_id, user_id)
  values (p_room_id, p_user_id)
  on conflict (room_id, user_id) do nothing;
end;
$$;

grant execute on function public.ban_player(uuid, uuid) to authenticated;

----------------------------------------------------------------
-- unban_player: host removes a ban.
----------------------------------------------------------------

create or replace function public.unban_player(
  p_room_id uuid,
  p_user_id uuid
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller uuid := auth.uid();
  v_host uuid;
begin
  if v_caller is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  select host_id into v_host from public.rooms where id = p_room_id;
  if v_host is null then
    raise exception 'Room not found' using errcode = 'P0002';
  end if;
  if v_caller <> v_host then
    raise exception 'Only the host can unban players' using errcode = '42501';
  end if;

  delete from public.room_bans
  where room_id = p_room_id and user_id = p_user_id;
end;
$$;

grant execute on function public.unban_player(uuid, uuid) to authenticated;

----------------------------------------------------------------
-- set_team_layout: host switches the layout for 6- or 12-player rooms.
-- Only player-counts with multiple valid layouts can change.
----------------------------------------------------------------

create or replace function public.set_team_layout(
  p_room_id uuid,
  p_layout text
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller uuid := auth.uid();
  v_room public.rooms;
  v_valid_layouts text[];
begin
  if v_caller is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  select * into v_room from public.rooms where id = p_room_id;
  if not found then
    raise exception 'Room not found' using errcode = 'P0002';
  end if;
  if v_caller <> v_room.host_id then
    raise exception 'Only the host can change layout' using errcode = '42501';
  end if;

  v_valid_layouts := case v_room.target_players
    when 6  then array['3v3', '2v2v2']
    when 12 then array['6v6', '4v4v4']
    else array[public.default_layout_for(v_room.target_players)]
  end;

  if p_layout <> all(v_valid_layouts) then
    raise exception
      'Layout % not valid for % players',
      p_layout, v_room.target_players
      using errcode = '22023';
  end if;

  update public.rooms set team_layout = p_layout where id = p_room_id;

  -- Reassign all current players to fit the new layout.
  update public.room_players
  set team = public.compute_team(seat_index, v_room.target_players, p_layout)
  where room_id = p_room_id;
end;
$$;

grant execute on function public.set_team_layout(uuid, text) to authenticated;
