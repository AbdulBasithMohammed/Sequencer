-- swap_teams(room, user_a, user_b): atomically exchange the two players'
-- team assignments. Lets the host drag-drop a teammate onto an opponent
-- chip even when both teams are at capacity (sequential set_team calls
-- would fail the capacity guard mid-swap).

create or replace function public.swap_teams(
  p_room_id uuid,
  p_user_a uuid,
  p_user_b uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller uuid := auth.uid();
  v_host uuid;
  v_team_a int;
  v_team_b int;
begin
  if v_caller is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  if p_user_a = p_user_b then
    raise exception 'Cannot swap a player with themselves' using errcode = '22023';
  end if;

  select host_id into v_host from public.rooms where id = p_room_id;
  if v_host is null then
    raise exception 'Room not found' using errcode = 'P0002';
  end if;
  if v_caller <> v_host then
    raise exception 'Only the host can swap teams' using errcode = '42501';
  end if;

  select team into v_team_a
  from public.room_players
  where room_id = p_room_id and user_id = p_user_a;
  if not found then
    raise exception 'Player A not in room' using errcode = 'P0002';
  end if;

  select team into v_team_b
  from public.room_players
  where room_id = p_room_id and user_id = p_user_b;
  if not found then
    raise exception 'Player B not in room' using errcode = 'P0002';
  end if;

  if v_team_a is not distinct from v_team_b then
    -- Same team (or both null): no-op.
    return;
  end if;

  -- Park one player on team=null briefly to dodge the unique-friendly
  -- capacity guard, then settle both teams.
  update public.room_players set team = null
    where room_id = p_room_id and user_id = p_user_a;
  update public.room_players set team = v_team_a
    where room_id = p_room_id and user_id = p_user_b;
  update public.room_players set team = v_team_b
    where room_id = p_room_id and user_id = p_user_a;
end;
$$;

grant execute on function public.swap_teams(uuid, uuid, uuid) to authenticated;
