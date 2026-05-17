-- Guest mode: Supabase anonymous sign-ins.
--
-- Guests are real auth.users rows with is_anonymous = true. They get a
-- profile (with a tag) via the existing handle_new_user trigger so they
-- show up in player lists, can join/host rooms, and can play games.
-- They CANNOT use the friends graph (no add, no invite, no search hit)
-- and a cron job sweeps stale guest accounts on a daily TTL.

----------------------------------------------------------------
-- 1) profiles.is_guest mirrors auth.users.is_anonymous at signup
----------------------------------------------------------------

alter table public.profiles
  add column if not exists is_guest boolean not null default false;

----------------------------------------------------------------
-- 2) display_name policy changes
--    - drop case-insensitive uniqueness: tag is the identity now,
--      and guests will all be "Foo (Guest)" — collisions are normal
--    - allow up to 30 chars so a 22-char nickname + " (Guest)" still
--      fits inside the existing min 3, max 30 envelope
----------------------------------------------------------------

drop index if exists public.profiles_display_name_lower_idx;

alter table public.profiles
  drop constraint if exists display_name_length;

alter table public.profiles
  add constraint display_name_length
    check (char_length(trim(display_name)) between 3 and 30);

----------------------------------------------------------------
-- 3) Signup trigger: copy is_anonymous onto the profile row
----------------------------------------------------------------

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text := new.raw_user_meta_data->>'display_name';
begin
  -- Anonymous sign-ups must still pass a nickname in the metadata.
  if v_name is null or char_length(trim(v_name)) < 3 then
    raise exception 'Sign-up requires display_name (>= 3 chars)';
  end if;

  insert into public.profiles (id, display_name, tag, is_guest)
  values (
    new.id,
    v_name,
    public.generate_profile_tag(),
    coalesce(new.is_anonymous, false)
  );
  return new;
end;
$$;

----------------------------------------------------------------
-- 4) Guard the friends graph: guests can't be friended and can't
--    initiate friendships either.
----------------------------------------------------------------

create or replace function public.send_friend_request(p_to_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_from uuid := auth.uid();
  v_min uuid;
  v_max uuid;
  v_caller_guest boolean;
  v_target_guest boolean;
begin
  if v_from is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  if v_from = p_to_user then
    raise exception 'Cannot friend yourself' using errcode = '22023';
  end if;

  select is_guest into v_caller_guest from public.profiles where id = v_from;
  select is_guest into v_target_guest from public.profiles where id = p_to_user;
  if v_target_guest is null then
    raise exception 'User not found' using errcode = 'P0002';
  end if;
  if v_caller_guest then
    raise exception 'Guest accounts cannot send friend requests' using errcode = '42501';
  end if;
  if v_target_guest then
    raise exception 'Cannot friend a guest account' using errcode = '42501';
  end if;

  if exists (
    select 1 from public.friend_ignores
    where user_id = p_to_user and ignored_user_id = v_from
  ) then
    return;  -- silent no-op
  end if;

  v_min := least(v_from, p_to_user);
  v_max := greatest(v_from, p_to_user);

  if exists (
    select 1 from public.friendships
    where user_a = v_min and user_b = v_max
  ) then
    return;
  end if;

  if exists (
    select 1 from public.friend_requests
    where from_user = p_to_user and to_user = v_from
  ) then
    delete from public.friend_requests
      where (from_user = p_to_user and to_user = v_from)
         or (from_user = v_from and to_user = p_to_user);
    insert into public.friendships (user_a, user_b)
    values (v_min, v_max)
    on conflict do nothing;
    return;
  end if;

  insert into public.friend_requests (from_user, to_user)
  values (v_from, p_to_user)
  on conflict do nothing;
end;
$$;

-- search_users: hide guests from search results so they can't even be
-- targeted from the friends UI
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

  -- Guests don't have a friends feature at all; their search returns
  -- empty so the UI doesn't even hint at it.
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
    and (v_name_part = '' or lower(p.display_name) like lower(v_name_part) || '%')
    and (v_tag_part is null or p.tag = v_tag_part)
  order by p.display_name
  limit 20;
end;
$$;

----------------------------------------------------------------
-- 5) Guard the invite graph too — guests can't send or receive
--    room invites
----------------------------------------------------------------

create or replace function public.invite_to_room(
  p_room_id uuid,
  p_to_user uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_from uuid := auth.uid();
  v_min uuid;
  v_max uuid;
  v_room public.rooms;
  v_player_count int;
  v_caller_guest boolean;
  v_target_guest boolean;
begin
  if v_from is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  if v_from = p_to_user then
    raise exception 'Cannot invite yourself' using errcode = '22023';
  end if;

  select is_guest into v_caller_guest from public.profiles where id = v_from;
  select is_guest into v_target_guest from public.profiles where id = p_to_user;
  if v_caller_guest then
    raise exception 'Guest accounts cannot send room invites' using errcode = '42501';
  end if;
  if v_target_guest then
    raise exception 'Cannot invite a guest account' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.room_players
    where room_id = p_room_id and user_id = v_from
  ) then
    raise exception 'You are not in this room' using errcode = '42501';
  end if;

  select * into v_room from public.rooms where id = p_room_id;
  if not found then
    raise exception 'Room not found' using errcode = 'P0002';
  end if;
  if v_room.status <> 'waiting' then
    raise exception 'Room is no longer accepting invites' using errcode = 'P0001';
  end if;

  v_min := least(v_from, p_to_user);
  v_max := greatest(v_from, p_to_user);
  if not exists (
    select 1 from public.friendships
    where user_a = v_min and user_b = v_max
  ) then
    raise exception 'You are not friends with this user' using errcode = '42501';
  end if;

  if exists (
    select 1 from public.room_players
    where room_id = p_room_id and user_id = p_to_user
  ) then
    return;
  end if;
  if exists (
    select 1 from public.room_bans
    where room_id = p_room_id and user_id = p_to_user
  ) then
    raise exception 'User is banned from this room' using errcode = '42501';
  end if;

  select count(*) into v_player_count
  from public.room_players where room_id = p_room_id;
  if v_player_count >= v_room.target_players then
    raise exception 'Room is full' using errcode = 'P0001';
  end if;

  insert into public.room_invites (room_id, from_user, to_user)
  values (p_room_id, v_from, p_to_user)
  on conflict (room_id, to_user) do nothing;
end;
$$;

----------------------------------------------------------------
-- 6) Stale-guest cleanup. Anonymous users that haven't signed in
--    in 24 hours get deleted. Cascades remove their profile + any
--    rooms they hosted + their seats in others.
--
--    A 1-hour grace at creation keeps a player who just signed in
--    seconds ago from being purged mid-game by a hot cron.
----------------------------------------------------------------

create or replace function public.delete_stale_guests()
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count int;
begin
  with d as (
    delete from auth.users
    where is_anonymous = true
      and created_at < now() - interval '1 hour'
      and coalesce(last_sign_in_at, created_at) < now() - interval '24 hours'
    returning id
  )
  select count(*) into v_count from d;
  return v_count;
end;
$$;

do $$
declare
  v_jobid bigint;
begin
  for v_jobid in select jobid from cron.job
                 where jobname = 'sequence-delete-stale-guests' loop
    perform cron.unschedule(v_jobid);
  end loop;
  perform cron.schedule(
    'sequence-delete-stale-guests',
    '0 * * * *',  -- top of every hour
    $sql$ select public.delete_stale_guests(); $sql$
  );
exception when others then
  raise notice 'Could not (re)schedule sequence-delete-stale-guests: %', sqlerrm;
end;
$$;
