-- Admin stats: the queries from docs/admin-stats.sql, exposed as RPCs so
-- they can be read from a /admin page instead of pasted into the SQL editor.
--
-- Security model — the guard lives HERE, not in the Next.js page:
--   sequencr.app is public and the anon key ships in the client bundle, so
--   anyone can call any RPC. Every function below therefore re-checks
--   is_admin server-side and raises 42501 otherwise. A page-level check
--   alone would be trivially bypassed by calling the endpoint directly.

----------------------------------------------------------------
-- 1) profiles.is_admin
----------------------------------------------------------------

alter table public.profiles
  add column if not exists is_admin boolean not null default false;

----------------------------------------------------------------
-- 2) Stop users granting themselves admin.
--
--    The existing "Users can update their own profile" policy is
--    `for update ... using (auth.uid() = id)`. Postgres RLS is
--    ROW-level, not column-level, so without this trigger any player
--    could run:
--
--      update profiles set is_admin = true where id = auth.uid();
--
--    and self-promote. The trigger silently pins is_admin to its old
--    value for anything holding a user JWT. auth.uid() is null for the
--    SQL editor (postgres) and for service_role, so those can still
--    set the flag — which is how you grant it.
----------------------------------------------------------------

create or replace function public.protect_is_admin()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is not null and new.is_admin is distinct from old.is_admin then
    new.is_admin := old.is_admin;
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_protect_is_admin on public.profiles;
create trigger profiles_protect_is_admin
  before update on public.profiles
  for each row execute function public.protect_is_admin();

----------------------------------------------------------------
-- 3) Guard helper
----------------------------------------------------------------

create or replace function public.current_user_is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    (select p.is_admin from public.profiles p where p.id = auth.uid()),
    false
  );
$$;

----------------------------------------------------------------
-- 4) Overview — one row, the at-a-glance numbers
----------------------------------------------------------------

create or replace function public.admin_overview()
returns table (
  total_users       int,
  registered_users  int,
  guest_users       int,
  bot_users         int,
  new_24h           int,
  new_7d            int,
  rooms_total       int,
  rooms_waiting     int,
  rooms_in_game     int,
  games_in_progress int,
  players_seated    int
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.current_user_is_admin() then
    raise exception 'Not authorized' using errcode = '42501';
  end if;

  return query
  select
    (select count(*) from public.profiles)::int,
    (select count(*) from public.profiles
      where not is_guest and not is_bot)::int,
    (select count(*) from public.profiles where is_guest)::int,
    (select count(*) from public.profiles where is_bot)::int,
    (select count(*) from public.profiles
      where created_at > now() - interval '24 hours')::int,
    (select count(*) from public.profiles
      where created_at > now() - interval '7 days')::int,
    (select count(*) from public.rooms)::int,
    (select count(*) from public.rooms where status = 'waiting')::int,
    (select count(*) from public.rooms where status = 'in_game')::int,
    (select count(*) from public.games where status = 'in_game')::int,
    (select count(*) from public.room_players)::int;
end;
$$;

----------------------------------------------------------------
-- 5) Recent signups
----------------------------------------------------------------

create or replace function public.admin_recent_users(p_hours int default 24)
returns table (
  display_name text,
  tag          text,
  is_guest     boolean,
  is_bot       boolean,
  created_at   timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.current_user_is_admin() then
    raise exception 'Not authorized' using errcode = '42501';
  end if;

  return query
  select p.display_name, p.tag, p.is_guest, p.is_bot, p.created_at
  from public.profiles p
  where p.created_at > now() - (greatest(p_hours, 1) || ' hours')::interval
  order by p.created_at desc
  limit 200;
end;
$$;

----------------------------------------------------------------
-- 6) Live rooms
--
--    Note: finished games are deleted 5 minutes after they end by
--    sequence-delete-finished, so this is a live snapshot only — it
--    will never show historical games.
----------------------------------------------------------------

create or replace function public.admin_active_rooms()
returns table (
  code             text,
  status           text,
  host_name        text,
  seats_taken      int,
  capacity         int,
  has_live_game    boolean,
  created_at       timestamptz,
  last_activity_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.current_user_is_admin() then
    raise exception 'Not authorized' using errcode = '42501';
  end if;

  return query
  select
    r.code,
    r.status,
    h.display_name,
    (select count(*) from public.room_players rp
      where rp.room_id = r.id)::int,
    r.target_players,
    exists (
      select 1 from public.games g
      where g.room_id = r.id and g.status = 'in_game'
    ),
    r.created_at,
    r.last_activity_at
  from public.rooms r
  join public.profiles h on h.id = r.host_id
  order by r.last_activity_at desc
  limit 100;
end;
$$;

----------------------------------------------------------------
-- 7) Grants — execute is open to authenticated, but every function
--    re-checks is_admin internally and throws for everyone else.
----------------------------------------------------------------

revoke all on function public.current_user_is_admin()   from public;
revoke all on function public.admin_overview()          from public;
revoke all on function public.admin_recent_users(int)   from public;
revoke all on function public.admin_active_rooms()      from public;

grant execute on function public.current_user_is_admin() to authenticated;
grant execute on function public.admin_overview()        to authenticated;
grant execute on function public.admin_recent_users(int) to authenticated;
grant execute on function public.admin_active_rooms()    to authenticated;
