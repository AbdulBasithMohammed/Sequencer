-- Bucket the daily rollups by Toronto date instead of UTC.
--
-- now()::date and created_at::date evaluate in the database's timezone,
-- which is UTC. A signup at 21:00 Toronto is 01:00 UTC the next day, so
-- it was landing in tomorrow's column — and evening activity is exactly
-- when a game like this is busiest, so the skew hits the peak hours.
--
-- With /admin now rendering every timestamp in Toronto, leaving the
-- charts on UTC days would put a signup in one column and its timestamp
-- on a different date directly beneath it.
--
-- 'America/Toronto' handles EST/EDT automatically — no DST maintenance.

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
    count(p.id) filter (where not p.is_guest and not p.is_bot)::int,
    count(p.id) filter (where p.is_guest)::int
  from generate_series(
         ((now() at time zone 'America/Toronto')::date
           - (greatest(p_days, 1) || ' days')::interval),
         (now() at time zone 'America/Toronto')::date,
         interval '1 day'
       ) as d(day)
  left join public.profiles p
    on (p.created_at at time zone 'America/Toronto')::date = d.day::date
  group by d.day
  order by d.day desc;
end;
$$;

-- Store the completion under its Toronto date.
create or replace function public.record_game_result()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_bots  int;
  v_ended timestamptz := coalesce(new.finished_at, now());
  v_secs  int := greatest(
    extract(epoch from (v_ended - new.started_at))::int, 0
  );
begin
  select count(*) filter (where pr.is_bot)
    into v_bots
  from public.room_players rp
  join public.profiles pr on pr.id = rp.user_id
  where rp.room_id = new.room_id;

  insert into public.game_stats_daily (day, completed, with_bots, total_duration_secs)
  values (
    (v_ended at time zone 'America/Toronto')::date,
    1,
    case when coalesce(v_bots, 0) > 0 then 1 else 0 end,
    v_secs
  )
  on conflict (day) do update
    set completed           = public.game_stats_daily.completed + 1,
        with_bots           = public.game_stats_daily.with_bots + excluded.with_bots,
        total_duration_secs = public.game_stats_daily.total_duration_secs + excluded.total_duration_secs;

  return null;
exception when others then
  -- Never let bookkeeping break the end of a game.
  raise notice 'record_game_result failed: %', sqlerrm;
  return null;
end;
$$;

create or replace function public.admin_games_by_day(p_days int default 14)
returns table (
  day       date,
  completed int
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
  select d.day::date, coalesce(s.completed, 0)
  from generate_series(
         ((now() at time zone 'America/Toronto')::date
           - (greatest(p_days, 1) || ' days')::interval),
         (now() at time zone 'America/Toronto')::date,
         interval '1 day'
       ) as d(day)
  left join public.game_stats_daily s on s.day = d.day::date
  order by d.day desc;
end;
$$;

-- Totals compare against Toronto dates too, so "last 24h" and "last 7d"
-- line up with the columns in the chart beside them.
create or replace function public.admin_game_totals()
returns table (
  completed_total   int,
  completed_24h     int,
  completed_7d      int,
  avg_duration_secs int,
  games_with_bots   int
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
    coalesce(sum(s.completed), 0)::int,
    coalesce(sum(s.completed) filter (
      where s.day >= (now() at time zone 'America/Toronto')::date
    ), 0)::int,
    coalesce(sum(s.completed) filter (
      where s.day > (now() at time zone 'America/Toronto')::date - 7
    ), 0)::int,
    case
      when coalesce(sum(s.completed), 0) = 0 then 0
      else (sum(s.total_duration_secs) / sum(s.completed))::int
    end,
    coalesce(sum(s.with_bots), 0)::int
  from public.game_stats_daily s;
end;
$$;
