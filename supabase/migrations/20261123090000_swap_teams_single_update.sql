-- Swap two players' teams in ONE statement.
--
-- The old body parked player A on team = null, moved B, then moved A:
-- three UPDATEs. Each row update bumps rooms.version through the
-- bump_rooms_version_on_players trigger, and each bump broadcasts the
-- full roster, so every client saw A vanish, B move, then A reappear —
-- the swap visibly played out in steps before it settled.
--
-- The null parking guarded against a capacity check that lives in
-- set_team, not on the table: room_players has no constraint on team.
-- A single UPDATE touching both rows is safe, and because AFTER ROW
-- triggers run at the end of the statement, both resulting broadcasts
-- already carry the finished swap.

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

  update public.room_players
  set team = case when user_id = p_user_a then v_team_b else v_team_a end
  where room_id = p_room_id
    and user_id in (p_user_a, p_user_b);
end;
$$;

revoke all on function public.swap_teams(uuid, uuid, uuid) from public;
grant execute on function public.swap_teams(uuid, uuid, uuid) to authenticated;
