-- Full user list for /admin, including the signup email and last sign-in.
--
-- This is the only RPC that returns PII (email addresses), so the admin
-- guard matters more here than anywhere else. Same model as the rest of
-- 20260810140000: the check lives in the function, not the page, because
-- the anon key ships in the client bundle and anyone can call this
-- endpoint directly.
--
-- Note on passwords: auth.users.encrypted_password is a bcrypt hash and is
-- deliberately NOT selected here. It is one-way — it cannot be reversed
-- into the original password, and there is no legitimate reason to surface
-- it in an admin UI.
--
-- Guests have no email (anonymous sign-ins), so email is null for them.

create or replace function public.admin_user_list(p_limit int default 200)
returns table (
  email           text,
  display_name    text,
  tag             text,
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

----------------------------------------------------------------
-- Signups per day for the last 14 days, split registered vs guest.
-- Lifted from docs/admin-stats.sql section 2b.
----------------------------------------------------------------

create or replace function public.admin_signups_by_day(p_days int default 14)
returns table (
  day        date,
  registered int,
  guests     int
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
    d.day::date,
    count(*) filter (where not p.is_guest and not p.is_bot)::int,
    count(*) filter (where p.is_guest)::int
  from generate_series(
         (now() - (greatest(p_days, 1) || ' days')::interval)::date,
         now()::date,
         interval '1 day'
       ) as d(day)
  left join public.profiles p
    on p.created_at >= d.day
   and p.created_at <  d.day + interval '1 day'
  group by d.day
  order by d.day desc;
end;
$$;

revoke all on function public.admin_user_list(int)     from public;
revoke all on function public.admin_signups_by_day(int) from public;

grant execute on function public.admin_user_list(int)      to authenticated;
grant execute on function public.admin_signups_by_day(int) to authenticated;
