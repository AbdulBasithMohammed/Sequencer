-- set_team must reject moves that would push a team over capacity.
-- Capacity = target_players / number_of_teams (derived from team_layout).
-- Null team (unassigned) is still allowed.

create or replace function public.set_team(
  p_room_id uuid,
  p_user_id uuid,
  p_team int
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller uuid := auth.uid();
  v_host uuid;
  v_target int;
  v_layout text;
  v_num_teams int;
  v_capacity int;
  v_occupants int;
begin
  if v_caller is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  select host_id, target_players, team_layout
    into v_host, v_target, v_layout
  from public.rooms
  where id = p_room_id;
  if v_host is null then
    raise exception 'Room not found' using errcode = 'P0002';
  end if;
  if v_caller <> v_host then
    raise exception 'Only the host can set teams' using errcode = '42501';
  end if;
  if p_team is not null and p_team not between 1 and 3 then
    raise exception 'Team must be 1, 2, or 3' using errcode = '22023';
  end if;

  if p_team is not null then
    v_num_teams := case v_layout
      when '1v1v1' then 3
      when '2v2v2' then 3
      when '4v4v4' then 3
      else 2
    end;
    v_capacity := v_target / v_num_teams;

    select count(*) into v_occupants
    from public.room_players
    where room_id = p_room_id
      and team = p_team
      and user_id <> p_user_id;

    if v_occupants >= v_capacity then
      raise exception 'Team % is full', p_team using errcode = '22023';
    end if;
  end if;

  update public.room_players
  set team = p_team
  where room_id = p_room_id and user_id = p_user_id;

  if not found then
    raise exception 'Player not in room' using errcode = 'P0002';
  end if;
end;
$$;
