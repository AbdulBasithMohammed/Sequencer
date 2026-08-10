-- Record the visitor's country on their profile.
--
-- Vercel attaches x-vercel-ip-country to every request at the edge, so
-- the country is already available server-side — it just was never
-- stored. Vercel Analytics knows it too, but that data lives in a
-- separate system with no API on the Hobby plan, so it cannot be joined
-- against a user list.
--
-- Country only. The IP itself is deliberately never stored: a two-letter
-- country code is coarse enough to be low-risk analytics, while an IP is
-- personal data with real handling obligations and no use here.
--
-- Set-once semantics: the RPC writes only when the column is null, so a
-- normal page load is a no-op after the first hit. That also backfills
-- existing accounts as they return, which is the only way to populate
-- them — there is no historical geo data to recover.

alter table public.profiles
  add column if not exists country text;

alter table public.profiles
  drop constraint if exists profiles_country_format;

alter table public.profiles
  add constraint profiles_country_format
    check (country is null or country ~ '^[A-Z]{2}$');

create or replace function public.set_my_country(p_country text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_cc  text := upper(nullif(trim(coalesce(p_country, '')), ''));
begin
  if v_uid is null then
    return;  -- not signed in: nothing to record, and not an error
  end if;
  if v_cc is null or v_cc !~ '^[A-Z]{2}$' then
    return;  -- unknown or malformed (local dev sends no header)
  end if;

  -- Set-once. Never overwrite: a user travelling or on a VPN should not
  -- churn this column, and the first observation is the useful one.
  update public.profiles
  set country = v_cc
  where id = v_uid and country is null;
end;
$$;

revoke all on function public.set_my_country(text) from public;
grant execute on function public.set_my_country(text) to authenticated;

-- Surface it in the admin user list.
--
-- Dropped rather than replaced: adding country changes the function's
-- OUT row type, and CREATE OR REPLACE cannot alter a return type
-- (42P13). Nothing depends on it besides the admin page.
drop function if exists public.admin_user_list(int);

create or replace function public.admin_user_list(p_limit int default 200)
returns table (
  email           text,
  display_name    text,
  tag             text,
  country         text,
  is_guest        boolean,
  is_bot          boolean,
  is_admin        boolean,
  created_at      timestamptz,
  last_sign_in_at timestamptz
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
    u.email::text,
    p.display_name,
    p.tag,
    p.country,
    p.is_guest,
    p.is_bot,
    p.is_admin,
    p.created_at,
    u.last_sign_in_at
  from public.profiles p
  join auth.users u on u.id = p.id
  order by p.created_at desc
  limit least(greatest(p_limit, 1), 500);
end;
$$;

create or replace function public.admin_countries()
returns table (
  country text,
  players int
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
  select coalesce(p.country, '??'), count(*)::int
  from public.profiles p
  where not p.is_bot
  group by p.country
  order by count(*) desc, coalesce(p.country, '??');
end;
$$;

revoke all on function public.admin_user_list(int) from public;
revoke all on function public.admin_countries()    from public;
grant execute on function public.admin_user_list(int) to authenticated;
grant execute on function public.admin_countries()    to authenticated;
