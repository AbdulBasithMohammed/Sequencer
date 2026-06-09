-- Phase 8.A — Bots: identity model + lobby add/remove controls.
--
-- A bot is a new kind of seated actor. It never authenticates and never
-- calls an RPC; a later step's server-side bot_take_turn() will act on its
-- behalf (the auto_advance_turn pattern). For now we only need bots to
-- EXIST in a lobby: a profiles row (so they render in player lists) and a
-- room_players row (seat + team), marked ready so they don't gate Start.
--
-- Identity model (decided 2026-06-09): bots are AUTH-LESS profiles rows
-- (is_bot = true, id = a fresh uuid with NO matching auth.users row). That
-- keeps add/remove entirely in SQL SECURITY DEFINER RPCs. The trade-off is
-- the profiles.id -> auth.users(id) FK (which provided ON DELETE CASCADE)
-- must go; we replace its cleanup behaviour with an auth.users delete
-- trigger so human accounts still cascade.

----------------------------------------------------------------
-- 1) Flags / columns
----------------------------------------------------------------

alter table public.profiles
  add column if not exists is_bot boolean not null default false;

-- Difficulty travels with the seat (read later by bot_take_turn). Tiers
-- land properly in 8.F; for now every bot is 'medium'.
alter table public.room_players
  add column if not exists bot_difficulty text
    check (bot_difficulty is null or bot_difficulty in ('rookie', 'medium', 'ace'));

----------------------------------------------------------------
-- 2) Drop the auth.users -> profiles FK cascade, replace with a trigger.
--    Human profiles still get cleaned up when their auth user is deleted
--    (the guest sweeper in particular relies on this); bot profiles are
--    now legal because nothing enforces id ∈ auth.users.
----------------------------------------------------------------

alter table public.profiles
  drop constraint if exists profiles_id_fkey;

create or replace function public.delete_profile_for_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.profiles where id = old.id;
  return old;
end;
$$;

drop trigger if exists on_auth_user_deleted on auth.users;
create trigger on_auth_user_deleted
  after delete on auth.users
  for each row execute function public.delete_profile_for_user();

----------------------------------------------------------------
-- 3) Orphan-bot cleanup. When a bot's last room_players row is removed
--    (remove_bot, kick, room deletion cascade, game-end cleanup), delete
--    the now-orphaned bot profile too. Human profiles are untouched — they
--    outlive rooms. A bot is only ever in one room, so "no rows remain"
--    is unambiguous.
----------------------------------------------------------------

create or replace function public.cleanup_orphan_bot()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (select 1 from public.profiles where id = old.user_id and is_bot) then
    if not exists (
      select 1 from public.room_players where user_id = old.user_id
    ) then
      delete from public.profiles where id = old.user_id and is_bot;
    end if;
  end if;
  return old;
end;
$$;

drop trigger if exists on_room_player_deleted on public.room_players;
create trigger on_room_player_deleted
  after delete on public.room_players
  for each row execute function public.cleanup_orphan_bot();

----------------------------------------------------------------
-- 4) pick_bot_name(room): a robot-flavoured name not already used by a
--    bot in this room. Falls back to a numbered name if the pool is
--    exhausted (only possible past 16 bots in one room).
----------------------------------------------------------------

create or replace function public.pick_bot_name(p_room_id uuid)
returns text
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_names text[] := array[
    'Robbie', 'Hal', 'Data', 'Bishop', 'Marvin', 'Optimus', 'Bender',
    'Gizmo', 'Sonny', 'Vision', 'Jarvis', 'Clank', 'Baymax', 'Dottie',
    'Pixel', 'Cogsworth'
  ];
  v_name text;
begin
  select n into v_name
  from unnest(v_names) as n
  where not exists (
    select 1
    from public.room_players rp
    join public.profiles pr on pr.id = rp.user_id
    where rp.room_id = p_room_id
      and pr.is_bot
      and pr.display_name = n
  )
  order by random()
  limit 1;

  if v_name is null then
    v_name := 'Bot ' || (floor(random() * 9000)::int + 1000)::text;
  end if;

  return v_name;
end;
$$;

----------------------------------------------------------------
-- 5) add_bot(room, difficulty): host-only, waiting-only. Mints an
--    auth-less bot profile and seats it at the next free seat with the
--    layout-derived team, ready = true.
----------------------------------------------------------------

create or replace function public.add_bot(
  p_room_id uuid,
  p_difficulty text default 'medium'
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller uuid := auth.uid();
  v_room public.rooms;
  v_count int;
  v_seat int;
  v_bot_id uuid;
begin
  if v_caller is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  select * into v_room from public.rooms where id = p_room_id;
  if not found then
    raise exception 'Room not found' using errcode = 'P0002';
  end if;
  if v_caller <> v_room.host_id then
    raise exception 'Only the host can add bots' using errcode = '42501';
  end if;
  if v_room.status <> 'waiting' then
    raise exception 'Bots can only be added while the room is waiting'
      using errcode = '22023';
  end if;
  if p_difficulty is null or p_difficulty not in ('rookie', 'medium', 'ace') then
    raise exception 'Invalid difficulty: %', p_difficulty using errcode = '22023';
  end if;

  select count(*) into v_count
  from public.room_players where room_id = p_room_id;
  if v_count >= v_room.target_players then
    raise exception 'Room is full' using errcode = 'P0001';
  end if;

  -- Lowest free seat (handles gaps left by departures).
  select s into v_seat
  from generate_series(0, v_room.target_players - 1) as g(s)
  where not exists (
    select 1 from public.room_players rp
    where rp.room_id = p_room_id and rp.seat_index = g.s
  )
  order by s
  limit 1;

  -- Mint the bot identity (no auth.users row).
  v_bot_id := gen_random_uuid();
  insert into public.profiles (id, display_name, tag, is_bot)
  values (
    v_bot_id,
    public.pick_bot_name(p_room_id),
    public.generate_profile_tag(),
    true
  );

  insert into public.room_players (
    room_id, user_id, seat_index, team, token_color, ready, bot_difficulty
  ) values (
    p_room_id,
    v_bot_id,
    v_seat,
    public.compute_team(v_seat, v_room.target_players, v_room.team_layout),
    public.default_token_color(v_seat),
    true,
    p_difficulty
  );

  return v_bot_id;
end;
$$;

revoke all on function public.add_bot(uuid, text) from public;
grant execute on function public.add_bot(uuid, text) to authenticated;

----------------------------------------------------------------
-- 6) remove_bot(room, seat): host-only, waiting-only. Deletes the bot's
--    seat; the on_room_player_deleted trigger reaps the orphan profile.
----------------------------------------------------------------

create or replace function public.remove_bot(
  p_room_id uuid,
  p_seat int
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller uuid := auth.uid();
  v_room public.rooms;
  v_bot_id uuid;
begin
  if v_caller is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  select * into v_room from public.rooms where id = p_room_id;
  if not found then
    raise exception 'Room not found' using errcode = 'P0002';
  end if;
  if v_caller <> v_room.host_id then
    raise exception 'Only the host can remove bots' using errcode = '42501';
  end if;
  if v_room.status <> 'waiting' then
    raise exception 'Bots can only be removed while the room is waiting'
      using errcode = '22023';
  end if;

  select rp.user_id into v_bot_id
  from public.room_players rp
  join public.profiles pr on pr.id = rp.user_id
  where rp.room_id = p_room_id and rp.seat_index = p_seat and pr.is_bot;

  if v_bot_id is null then
    raise exception 'No bot at seat %', p_seat using errcode = 'P0002';
  end if;

  delete from public.room_players
  where room_id = p_room_id and user_id = v_bot_id;
end;
$$;

revoke all on function public.remove_bot(uuid, int) from public;
grant execute on function public.remove_bot(uuid, int) to authenticated;

----------------------------------------------------------------
-- 7) Hide bots from user search (they have is_guest = false, so without
--    this they'd surface as friend targets). No other friend/invite path
--    can reach a bot — its id is never shown in any human-pickable list.
----------------------------------------------------------------

create or replace function public.search_users(p_query text)
returns table(
  user_id uuid,
  display_name text,
  tag text,
  relationship text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_caller uuid := auth.uid();
  v_q text;
  v_name_part text;
  v_tag_part text;
  v_caller_guest boolean;
begin
  if v_caller is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  select is_guest into v_caller_guest from public.profiles where id = v_caller;
  if v_caller_guest then
    return;
  end if;

  v_q := trim(coalesce(p_query, ''));
  if v_q = '' then
    return;
  end if;

  if position('#' in v_q) > 0 then
    v_name_part := trim(split_part(v_q, '#', 1));
    v_tag_part := upper(trim(split_part(v_q, '#', 2)));
  else
    v_name_part := v_q;
    v_tag_part := null;
  end if;

  return query
  select
    p.id,
    p.display_name,
    p.tag,
    case
      when exists (
        select 1 from public.friendships f
        where f.user_a = least(p.id, v_caller)
          and f.user_b = greatest(p.id, v_caller)
      ) then 'friend'
      when exists (
        select 1 from public.friend_requests r
        where r.from_user = v_caller and r.to_user = p.id
      ) then 'request_sent'
      when exists (
        select 1 from public.friend_requests r
        where r.from_user = p.id and r.to_user = v_caller
      ) then 'request_received'
      when exists (
        select 1 from public.friend_ignores i
        where i.user_id = v_caller and i.ignored_user_id = p.id
      ) then 'ignored'
      else 'none'
    end::text as relationship
  from public.profiles p
  where p.id <> v_caller
    and p.is_guest = false
    and p.is_bot = false
    and (v_name_part = '' or lower(p.display_name) like lower(v_name_part) || '%')
    and (v_tag_part is null or p.tag = v_tag_part)
  order by p.display_name
  limit 20;
end;
$$;

----------------------------------------------------------------
-- 8) leave_room: when the host leaves, hand off to the oldest HUMAN
--    player, not a bot. If only bots (or nobody) remain, delete the room
--    — the cascade + orphan-bot trigger reap everything. Prevents a room
--    stranded under a bot "host" with no human able to control it.
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
    select rp.user_id into v_new_host
    from public.room_players rp
    join public.profiles pr on pr.id = rp.user_id
    where rp.room_id = p_room_id and pr.is_bot = false
    order by rp.joined_at
    limit 1;

    if v_new_host is null then
      -- No humans left (only bots, or empty). Wipe the room.
      delete from public.rooms where id = p_room_id;
    else
      update public.rooms set host_id = v_new_host where id = p_room_id;
    end if;
  else
    -- A non-host human left — clean up if no humans remain.
    if not exists (
      select 1
      from public.room_players rp
      join public.profiles pr on pr.id = rp.user_id
      where rp.room_id = p_room_id and pr.is_bot = false
    ) then
      delete from public.rooms where id = p_room_id;
    end if;
  end if;
end;
$$;
