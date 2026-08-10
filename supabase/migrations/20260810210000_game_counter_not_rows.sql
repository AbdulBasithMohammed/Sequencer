-- Replace per-game history with a daily counter.
--
-- 20260810190000 wrote one row per completed game. That is more than is
-- needed to answer "are people finishing games", and it grows without
-- bound. This rolls it up to one row per DAY: ~50 bytes/day, about
-- 18 KB/year, flat forever regardless of how popular the game gets.
--
-- Turn-level data for a future RL project is deliberately NOT collected
-- here. That needs per-move records, which is a different shape and a
-- much larger volume — it should be its own opt-in table with its own
-- retention policy, not a side effect of this counter.

create table if not exists public.game_stats_daily (
  day                date primary key,
  completed          int    not null default 0,
  with_bots          int    not null default 0,
  total_duration_secs bigint not null default 0
);

alter table public.game_stats_daily enable row level security;

-- Carry over anything 20260810190000 already captured, so switching
-- approaches doesn't lose counts.
insert into public.game_stats_daily (day, completed, with_bots, total_duration_secs)
select
  finished_at::date,
  count(*)::int,
  count(*) filter (where bot_count > 0)::int,
  coalesce(sum(duration_seconds), 0)::bigint
from public.game_results
group by finished_at::date
on conflict (day) do update
  set completed           = public.game_stats_daily.completed + excluded.completed,
      with_bots           = public.game_stats_daily.with_bots + excluded.with_bots,
      total_duration_secs = public.game_stats_daily.total_duration_secs
                            + excluded.total_duration_secs;

----------------------------------------------------------------
-- Trigger: increment the day's counters instead of inserting a row
----------------------------------------------------------------

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
    v_ended::date,
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

----------------------------------------------------------------
-- Reads
----------------------------------------------------------------

drop function if exists public.admin_recent_games(int);

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
    coalesce(sum(s.completed) filter (where s.day >= (now() - interval '1 day')::date), 0)::int,
    coalesce(sum(s.completed) filter (where s.day >= (now() - interval '7 days')::date), 0)::int,
    case
      when coalesce(sum(s.completed), 0) = 0 then 0
      else (sum(s.total_duration_secs) / sum(s.completed))::int
    end,
    coalesce(sum(s.with_bots), 0)::int
  from public.game_stats_daily s;
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
         (now() - (greatest(p_days, 1) || ' days')::interval)::date,
         now()::date,
         interval '1 day'
       ) as d(day)
  left join public.game_stats_daily s on s.day = d.day::date
  order by d.day desc;
end;
$$;

revoke all on function public.admin_game_totals()      from public;
revoke all on function public.admin_games_by_day(int)  from public;
grant execute on function public.admin_game_totals()     to authenticated;
grant execute on function public.admin_games_by_day(int) to authenticated;

-- Per-game rows are no longer written; the counts above are carried over.
drop table if exists public.game_results;
