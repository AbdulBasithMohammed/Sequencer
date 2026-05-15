-- Phase 2.C — lobby controls: set_team, set_ready, kick_player, transfer_host.
-- All run as SECURITY DEFINER; gate on host where applicable.

----------------------------------------------------------------
-- set_team: host can set any seated player's team (1, 2, or 3).
----------------------------------------------------------------

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
begin
  if v_caller is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  select host_id into v_host from public.rooms where id = p_room_id;
  if v_host is null then
    raise exception 'Room not found' using errcode = 'P0002';
  end if;
  if v_caller <> v_host then
    raise exception 'Only the host can set teams' using errcode = '42501';
  end if;
  if p_team is not null and p_team not between 1 and 3 then
    raise exception 'Team must be 1, 2, or 3' using errcode = '22023';
  end if;

  update public.room_players
  set team = p_team
  where room_id = p_room_id and user_id = p_user_id;

  if not found then
    raise exception 'Player not in room' using errcode = 'P0002';
  end if;
end;
$$;

grant execute on function public.set_team(uuid, uuid, int) to authenticated;

----------------------------------------------------------------
-- set_ready: a player toggles their own ready state.
----------------------------------------------------------------

create or replace function public.set_ready(
  p_room_id uuid,
  p_ready boolean
)
returns void
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

  update public.room_players
  set ready = p_ready
  where room_id = p_room_id and user_id = v_caller;

  if not found then
    raise exception 'Not in this room' using errcode = 'P0002';
  end if;
end;
$$;

grant execute on function public.set_ready(uuid, boolean) to authenticated;

----------------------------------------------------------------
-- kick_player: host removes someone else (hosts leave via leave_room).
----------------------------------------------------------------

create or replace function public.kick_player(
  p_room_id uuid,
  p_user_id uuid
)
returns void
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
    raise exception 'Only the host can kick players' using errcode = '42501';
  end if;
  if p_user_id = v_caller then
    raise exception 'Use leave_room to leave your own room' using errcode = '22023';
  end if;

  delete from public.room_players
  where room_id = p_room_id and user_id = p_user_id;
end;
$$;

grant execute on function public.kick_player(uuid, uuid) to authenticated;

----------------------------------------------------------------
-- transfer_host: hand the host badge to another player in the room.
----------------------------------------------------------------

create or replace function public.transfer_host(
  p_room_id uuid,
  p_new_host_id uuid
)
returns void
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
    raise exception 'Only the host can transfer host' using errcode = '42501';
  end if;
  if p_new_host_id = v_caller then
    raise exception 'You are already the host' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.room_players
    where room_id = p_room_id and user_id = p_new_host_id
  ) then
    raise exception 'New host must be in the room' using errcode = '22023';
  end if;

  update public.rooms set host_id = p_new_host_id where id = p_room_id;
end;
$$;

grant execute on function public.transfer_host(uuid, uuid) to authenticated;
