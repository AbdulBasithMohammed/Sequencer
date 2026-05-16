-- Friends feature: search → send request → accept/ignore → friends.
--
-- Three tables:
--   friend_requests — pending one-way requests (from_user → to_user)
--   friendships     — accepted, stored once with canonical ordering
--   friend_ignores  — per-user ignore list; blocks future requests
--
-- All mutations through SECURITY DEFINER RPCs (RLS allows SELECT-only
-- on rows the caller is part of).

----------------------------------------------------------------
-- Tables
----------------------------------------------------------------

create table public.friend_requests (
  from_user uuid not null references public.profiles(id) on delete cascade,
  to_user uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (from_user, to_user),
  check (from_user <> to_user)
);

create index friend_requests_to_idx on public.friend_requests (to_user);

create table public.friendships (
  user_a uuid not null references public.profiles(id) on delete cascade,
  user_b uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_a, user_b),
  check (user_a < user_b)
);

create index friendships_user_b_idx on public.friendships (user_b);

create table public.friend_ignores (
  user_id uuid not null references public.profiles(id) on delete cascade,
  ignored_user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, ignored_user_id),
  check (user_id <> ignored_user_id)
);

----------------------------------------------------------------
-- RLS: select-only for rows touching the caller; no direct writes
----------------------------------------------------------------

alter table public.friend_requests enable row level security;
create policy "see related friend_requests"
  on public.friend_requests for select
  using (from_user = (select auth.uid()) or to_user = (select auth.uid()));

alter table public.friendships enable row level security;
create policy "see related friendships"
  on public.friendships for select
  using (user_a = (select auth.uid()) or user_b = (select auth.uid()));

alter table public.friend_ignores enable row level security;
create policy "see own ignores"
  on public.friend_ignores for select
  using (user_id = (select auth.uid()));

----------------------------------------------------------------
-- send_friend_request — also auto-accepts if a reverse request exists
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
begin
  if v_from is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  if v_from = p_to_user then
    raise exception 'Cannot friend yourself' using errcode = '22023';
  end if;
  if not exists (select 1 from public.profiles where id = p_to_user) then
    raise exception 'User not found' using errcode = 'P0002';
  end if;
  if exists (
    select 1 from public.friend_ignores
    where user_id = p_to_user and ignored_user_id = v_from
  ) then
    -- Silently no-op so an ignored sender can't probe ignore status.
    return;
  end if;

  v_min := least(v_from, p_to_user);
  v_max := greatest(v_from, p_to_user);

  if exists (
    select 1 from public.friendships
    where user_a = v_min and user_b = v_max
  ) then
    return;  -- already friends, no-op
  end if;

  -- Auto-accept if the recipient had already sent us a request.
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

----------------------------------------------------------------
-- accept_friend_request
----------------------------------------------------------------

create or replace function public.accept_friend_request(p_from_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_to uuid := auth.uid();
  v_min uuid;
  v_max uuid;
begin
  if v_to is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.friend_requests
    where from_user = p_from_user and to_user = v_to
  ) then
    raise exception 'No incoming request from this user' using errcode = 'P0002';
  end if;

  v_min := least(v_to, p_from_user);
  v_max := greatest(v_to, p_from_user);

  delete from public.friend_requests
    where (from_user = p_from_user and to_user = v_to)
       or (from_user = v_to and to_user = p_from_user);

  insert into public.friendships (user_a, user_b)
  values (v_min, v_max)
  on conflict do nothing;
end;
$$;

----------------------------------------------------------------
-- ignore_friend_request — removes the pending request + adds to
-- the recipient's ignore list so future sends silently fail
----------------------------------------------------------------

create or replace function public.ignore_friend_request(p_from_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_to uuid := auth.uid();
begin
  if v_to is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  if v_to = p_from_user then
    raise exception 'Cannot ignore yourself' using errcode = '22023';
  end if;

  delete from public.friend_requests
    where from_user = p_from_user and to_user = v_to;

  insert into public.friend_ignores (user_id, ignored_user_id)
  values (v_to, p_from_user)
  on conflict do nothing;
end;
$$;

----------------------------------------------------------------
-- unignore_user
----------------------------------------------------------------

create or replace function public.unignore_user(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  delete from public.friend_ignores
    where user_id = v_user and ignored_user_id = p_user_id;
end;
$$;

----------------------------------------------------------------
-- cancel_friend_request — sender takes back their own outgoing
----------------------------------------------------------------

create or replace function public.cancel_friend_request(p_to_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_from uuid := auth.uid();
begin
  if v_from is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  delete from public.friend_requests
    where from_user = v_from and to_user = p_to_user;
end;
$$;

----------------------------------------------------------------
-- unfriend
----------------------------------------------------------------

create or replace function public.unfriend(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_min uuid;
  v_max uuid;
begin
  if v_user is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  v_min := least(v_user, p_user_id);
  v_max := greatest(v_user, p_user_id);

  delete from public.friendships
    where user_a = v_min and user_b = v_max;
end;
$$;

----------------------------------------------------------------
-- search_users — input can be "name" or "name #tag" (or "#tag" alone)
-- Returns at most 20 matches with the relationship to the caller.
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
begin
  if v_caller is null then
    raise exception 'Not authenticated' using errcode = '42501';
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
    and (v_name_part = '' or lower(p.display_name) like lower(v_name_part) || '%')
    and (v_tag_part is null or p.tag = v_tag_part)
  order by p.display_name
  limit 20;
end;
$$;

----------------------------------------------------------------
-- get_friends_data — one round trip for all four sections of the UI
----------------------------------------------------------------

create or replace function public.get_friends_data()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  return jsonb_build_object(
    'friends', coalesce((
      select jsonb_agg(jsonb_build_object(
        'user_id', f.friend_id,
        'display_name', p.display_name,
        'tag', p.tag
      ) order by lower(p.display_name))
      from (
        select case when user_a = v_user then user_b else user_a end as friend_id
        from public.friendships
        where user_a = v_user or user_b = v_user
      ) f
      join public.profiles p on p.id = f.friend_id
    ), '[]'::jsonb),
    'incoming', coalesce((
      select jsonb_agg(jsonb_build_object(
        'user_id', fr.from_user,
        'display_name', p.display_name,
        'tag', p.tag,
        'created_at', fr.created_at
      ) order by fr.created_at desc)
      from public.friend_requests fr
      join public.profiles p on p.id = fr.from_user
      where fr.to_user = v_user
    ), '[]'::jsonb),
    'sent', coalesce((
      select jsonb_agg(jsonb_build_object(
        'user_id', fr.to_user,
        'display_name', p.display_name,
        'tag', p.tag,
        'created_at', fr.created_at
      ) order by fr.created_at desc)
      from public.friend_requests fr
      join public.profiles p on p.id = fr.to_user
      where fr.from_user = v_user
    ), '[]'::jsonb),
    'ignored', coalesce((
      select jsonb_agg(jsonb_build_object(
        'user_id', fi.ignored_user_id,
        'display_name', p.display_name,
        'tag', p.tag
      ) order by lower(p.display_name))
      from public.friend_ignores fi
      join public.profiles p on p.id = fi.ignored_user_id
      where fi.user_id = v_user
    ), '[]'::jsonb)
  );
end;
$$;

grant execute on function public.send_friend_request(uuid) to authenticated;
grant execute on function public.accept_friend_request(uuid) to authenticated;
grant execute on function public.ignore_friend_request(uuid) to authenticated;
grant execute on function public.unignore_user(uuid) to authenticated;
grant execute on function public.cancel_friend_request(uuid) to authenticated;
grant execute on function public.unfriend(uuid) to authenticated;
grant execute on function public.search_users(text) to authenticated;
grant execute on function public.get_friends_data() to authenticated;
