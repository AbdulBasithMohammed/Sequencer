-- Durable record of completed games.
--
-- The problem: sequence-delete-finished deletes games 5 minutes after
-- they end, and game_moves cascades with them. That keeps storage tiny
-- but means there is NO record that a game was ever played to
-- completion — no completion count, no duration, nothing. Every game
-- finished before this migration is unrecoverable.
--
-- The fix: a trigger writes one summary row the moment a game flips to
-- 'finished', before the cleanup cron can delete it. Roughly 80 bytes
-- per completed game, so 100k games is ~8 MB — negligible against the
-- 500 MB free-tier budget, and unlike game_moves it does not grow with
-- the length of each game.
--
-- No foreign keys on purpose: this table must outlive the rooms,
-- games and guest accounts it describes. A cascade from a deleted
-- guest would silently erase history.

create table if not exists public.game_results (
  id               uuid primary key default gen_random_uuid(),
  room_code        text,
  player_count     int  not null default 0,
  human_count      int  not null default 0,
  bot_count        int  not null default 0,
  winner_team      int,
  started_at       timestamptz,
  finished_at      timestamptz not null default now(),
  duration_seconds int
);

create index if not exists game_results_finished_idx
  on public.game_results (finished_at desc);

-- Locked down: RLS on with no policies at all, so no client role can
-- read or write it. The admin RPCs below are SECURITY DEFINER and
-- bypass RLS, which is the only intended access path.
alter table public.game_results enable row level security;

----------------------------------------------------------------
-- Trigger: capture the summary at the moment of completion
----------------------------------------------------------------

create or replace function public.record_game_result()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_code    text;
  v_players int;
  v_bots    int;
  v_ended   timestamptz := coalesce(new.finished_at, now());
begin
  select r.code into v_code
  from public.rooms r
  where r.id = new.room_id;

  select count(*), count(*) filter (where pr.is_bot)
    into v_players, v_bots
  from public.room_players rp
  join public.profiles pr on pr.id = rp.user_id
  where rp.room_id = new.room_id;

  insert into public.game_results (
    room_code, player_count, human_count, bot_count,
    winner_team, started_at, finished_at, duration_seconds
  )
  values (
    v_code,
    coalesce(v_players, 0),
    coalesce(v_players, 0) - coalesce(v_bots, 0),
    coalesce(v_bots, 0),
    new.winner_team,
    new.started_at,
    v_ended,
    greatest(
      extract(epoch from (v_ended - new.started_at))::int,
      0
    )
  );

  return null;
exception when others then
  -- Never let bookkeeping break the end of a game.
  raise notice 'record_game_result failed: %', sqlerrm;
  return null;
end;
$$;

drop trigger if exists games_record_result on public.games;
create trigger games_record_result
  after update on public.games
  for each row
  when (new.status = 'finished' and old.status is distinct from 'finished')
  execute function public.record_game_result();

----------------------------------------------------------------
-- Admin reads
----------------------------------------------------------------

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
    (select count(*) from public.game_results)::int,
    (select count(*) from public.game_results
      where finished_at > now() - interval '24 hours')::int,
    (select count(*) from public.game_results
      where finished_at > now() - interval '7 days')::int,
    (select coalesce(avg(duration_seconds), 0) from public.game_results)::int,
    (select count(*) from public.game_results where bot_count > 0)::int;
end;
$$;

create or replace function public.admin_recent_games(p_limit int default 50)
returns table (
  room_code        text,
  player_count     int,
  human_count      int,
  bot_count        int,
  winner_team      int,
  duration_seconds int,
  finished_at      timestamptz
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
    g.room_code, g.player_count, g.human_count, g.bot_count,
    g.winner_team, g.duration_seconds, g.finished_at
  from public.game_results g
  order by g.finished_at desc
  limit least(greatest(p_limit, 1), 200);
end;
$$;

revoke all on function public.admin_game_totals()      from public;
revoke all on function public.admin_recent_games(int)  from public;

grant execute on function public.admin_game_totals()     to authenticated;
grant execute on function public.admin_recent_games(int) to authenticated;
