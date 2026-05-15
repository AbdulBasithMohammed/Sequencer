-- Token color: each player picks the color shown on their avatar in the lobby.
-- Distinct from team (which is gameplay-mechanical); token color is personal.

alter table public.room_players
  add column token_color text not null default 'pink'
    check (token_color in ('pink', 'blue', 'butter', 'mint', 'ink'));

-- Default token color cycles through the palette by seat index so initial
-- joins look varied without anyone having to pick.
create or replace function public.default_token_color(p_seat_index int)
returns text
language sql
immutable
set search_path = ''
as $$
  select case (p_seat_index % 5)
    when 0 then 'pink'
    when 1 then 'blue'
    when 2 then 'butter'
    when 3 then 'mint'
    else 'ink'
  end;
$$;

----------------------------------------------------------------
-- Replace create_room + join_room to seed token_color.
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

  insert into public.room_players (room_id, user_id, seat_index, team, token_color)
  values (
    v_room_id,
    v_user_id,
    0,
    public.compute_team(0, p_target_players, v_layout),
    public.default_token_color(0)
  );

  return v_code;
end;
$$;

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

  insert into public.room_players (room_id, user_id, seat_index, team, token_color)
  values (
    v_room.id,
    v_user_id,
    v_next_seat,
    public.compute_team(v_next_seat, v_room.target_players, v_room.team_layout),
    public.default_token_color(v_next_seat)
  );

  return v_room.id;
end;
$$;

----------------------------------------------------------------
-- set_token_color: a player updates their own avatar color.
----------------------------------------------------------------

create or replace function public.set_token_color(
  p_room_id uuid,
  p_color text
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller uuid := auth.uid();
begin
  if v_caller is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  if p_color not in ('pink', 'blue', 'butter', 'mint', 'ink') then
    raise exception 'Invalid color' using errcode = '22023';
  end if;

  update public.room_players
  set token_color = p_color
  where room_id = p_room_id and user_id = v_caller;

  if not found then
    raise exception 'Not in this room' using errcode = 'P0002';
  end if;
end;
$$;

grant execute on function public.set_token_color(uuid, text) to authenticated;
