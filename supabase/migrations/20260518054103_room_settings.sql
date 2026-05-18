-- Host-configurable room settings: turn timer preset + win target.
--
-- rooms.turn_seconds already exists (default 120, check 15..600). We just
-- add a host-only RPC that restricts changes to a sane preset list while
-- the lobby is still 'waiting'.
--
-- Win target: today win_threshold() hard-codes 2 for 2-team layouts and
-- 1 for 3-team. Add nullable rooms.target_sequences (1..2) and have
-- win_threshold() honor it when present, falling back to the layout-
-- derived default. Three-team layouts always need 1 (UI keeps the
-- option hidden), so we leave that default untouched.

alter table public.rooms
  add column if not exists target_sequences int
    check (target_sequences is null or target_sequences between 1 and 2);

-- win_threshold: prefer the room override; otherwise the count-of-teams
-- default (3 teams → 1, otherwise 2).
create or replace function public.win_threshold(p_room_id uuid)
returns int
language sql
stable
set search_path = ''
as $$
  select coalesce(
    (select target_sequences from public.rooms where id = p_room_id),
    case
      when (select count(distinct team) from public.room_players
              where room_id = p_room_id and team is not null) = 3
        then 1
      else 2
    end
  );
$$;

-- set_turn_seconds: host-only, lobby-only, must be a preset value.
create or replace function public.set_turn_seconds(
  p_room_id uuid,
  p_seconds int
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller uuid := auth.uid();
  v_host uuid;
  v_status text;
begin
  if v_caller is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  if p_seconds not in (30, 45, 60, 90, 120) then
    raise exception 'Turn seconds must be one of 30/45/60/90/120'
      using errcode = '22023';
  end if;

  select host_id, status into v_host, v_status
  from public.rooms where id = p_room_id;
  if v_host is null then
    raise exception 'Room not found' using errcode = 'P0002';
  end if;
  if v_caller <> v_host then
    raise exception 'Only the host can change the turn timer'
      using errcode = '42501';
  end if;
  if v_status <> 'waiting' then
    raise exception 'Turn timer can only be changed before the game starts'
      using errcode = '22023';
  end if;

  update public.rooms set turn_seconds = p_seconds where id = p_room_id;
end;
$$;

grant execute on function public.set_turn_seconds(uuid, int) to authenticated;

-- set_target_sequences: host-only, lobby-only. p_n in {1, 2} or null
-- (null = auto-default by team count).
create or replace function public.set_target_sequences(
  p_room_id uuid,
  p_n int
) returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller uuid := auth.uid();
  v_host uuid;
  v_status text;
begin
  if v_caller is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  if p_n is not null and p_n not in (1, 2) then
    raise exception 'Target sequences must be 1 or 2'
      using errcode = '22023';
  end if;

  select host_id, status into v_host, v_status
  from public.rooms where id = p_room_id;
  if v_host is null then
    raise exception 'Room not found' using errcode = 'P0002';
  end if;
  if v_caller <> v_host then
    raise exception 'Only the host can change the win target'
      using errcode = '42501';
  end if;
  if v_status <> 'waiting' then
    raise exception 'Win target can only be changed before the game starts'
      using errcode = '22023';
  end if;

  update public.rooms set target_sequences = p_n where id = p_room_id;
end;
$$;

grant execute on function public.set_target_sequences(uuid, int) to authenticated;
