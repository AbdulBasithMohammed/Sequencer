-- Stop polling for games that don't exist, and stop one bad game from
-- freezing every bot on the site.
--
-- The numbers that motivated this (pg_stat_statements, 61 days):
--
--   tick_bot_turns()      2,663,783 calls   70.0% of ALL db exec time
--   tick_expired_turns()  1,071,827 calls   11.6%
--   play_move (humans)       18,986 calls    1.7%
--
-- 82% of the database's lifetime work is the two tick jobs polling an
-- almost-always-empty board: they run every 2s / 5s around the clock —
-- 60,480 invocations a day — whether or not a single game is live.
--
-- Change 1 — event-driven scheduling. The tick jobs are now switched on
-- when a game starts and off when the last in_game game disappears,
-- driven by a trigger on public.games. Idle days cost zero tick runs
-- instead of 60,480. During play the cadence is unchanged (bots still
-- tick at 2s, AFK turns at 5s), so gameplay feel is untouched.
--
-- Change 2 — crash isolation. Both tick loops called their per-game
-- worker bare, so ONE game raising any error aborted the whole tick.
-- With the retry arriving 2 seconds later and hitting the same game
-- first (same ORDER BY), a single wedged game silently froze every bot
-- and every AFK timer on the site, indefinitely, with nothing logged
-- but the same error repeating. Each game is now its own subtransaction:
-- a bad game is skipped with a warning and the rest of the batch runs.
--
-- Change 3 — watchdog. If the gating trigger ever misses (a path we
-- didn't foresee), bots would freeze with no poller to recover them.
-- The existing 5-minute stale-cleanup job now also re-asserts the
-- correct scheduling state, so the worst case is a 5-minute stall, not
-- a permanent one. It also handles switching the jobs OFF after the
-- delete-finished sweeper removes the last game.

----------------------------------------------------------------
-- 1) ensure_tick_jobs — reconcile cron state with reality.
--    Idempotent: safe to call from triggers, sweepers, or by hand.
----------------------------------------------------------------

create or replace function public.ensure_tick_jobs()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_any_games bool;
  v_bot_games bool;
  v_jobid bigint;
begin
  select exists (select 1 from public.games where status = 'in_game')
    into v_any_games;

  -- Bots tick only matters if a live game actually seats a bot.
  select exists (
    select 1
    from public.games g
    join public.room_players rp on rp.room_id = g.room_id
    join public.profiles pr on pr.id = rp.user_id
    where g.status = 'in_game' and pr.is_bot
  ) into v_bot_games;

  -- AFK turn timer: needed while any game is live.
  if v_any_games then
    if not exists (select 1 from cron.job where jobname = 'sequence-tick-turns') then
      perform cron.schedule(
        'sequence-tick-turns', '5 seconds',
        $sql$ select public.tick_expired_turns(); $sql$
      );
    end if;
  else
    for v_jobid in select jobid from cron.job where jobname = 'sequence-tick-turns' loop
      perform cron.unschedule(v_jobid);
    end loop;
  end if;

  -- Bot mover: needed while any live game has a bot.
  if v_bot_games then
    if not exists (select 1 from cron.job where jobname = 'sequence-tick-bots') then
      perform cron.schedule(
        'sequence-tick-bots', '2 seconds',
        $sql$ select public.tick_bot_turns(); $sql$
      );
    end if;
  else
    for v_jobid in select jobid from cron.job where jobname = 'sequence-tick-bots' loop
      perform cron.unschedule(v_jobid);
    end loop;
  end if;
exception when others then
  -- Scheduling bookkeeping must never break a move or a sweep. The
  -- 5-minute watchdog will retry it.
  raise warning 'ensure_tick_jobs failed: %', sqlerrm;
end;
$$;

revoke all on function public.ensure_tick_jobs() from public;

----------------------------------------------------------------
-- 2) Trigger: reconcile when games appear, finish, or vanish.
--    Row-level with a WHEN guard so ordinary move updates (version,
--    hands, deck bumps) don't touch it — only status transitions.
----------------------------------------------------------------

create or replace function public.games_tick_gate()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.ensure_tick_jobs();
  return null;
end;
$$;

drop trigger if exists games_tick_gate_ins on public.games;
create trigger games_tick_gate_ins
  after insert on public.games
  for each row execute function public.games_tick_gate();

drop trigger if exists games_tick_gate_upd on public.games;
create trigger games_tick_gate_upd
  after update on public.games
  for each row
  when (old.status is distinct from new.status)
  execute function public.games_tick_gate();

drop trigger if exists games_tick_gate_del on public.games;
create trigger games_tick_gate_del
  after delete on public.games
  for each row execute function public.games_tick_gate();

----------------------------------------------------------------
-- 3) Crash-isolated tick loops. Same queries and caps as before —
--    the only change is the per-game exception block, so one broken
--    game is skipped and logged instead of aborting the batch.
----------------------------------------------------------------

create or replace function public.tick_bot_turns()
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_game record;
  v_count int := 0;
begin
  for v_game in
    select g.id
    from public.games g
    join public.rooms r on r.id = g.room_id
    join public.room_players rp
      on rp.room_id = g.room_id and rp.seat_index = g.turn_seat
    join public.profiles pr on pr.id = rp.user_id
    where g.status = 'in_game'
      and pr.is_bot
      and g.turn_deadline is not null
      and now() >= g.turn_deadline
                   - make_interval(secs => r.turn_seconds)
                   + make_interval(secs => public.bot_think_seconds() + random() * 1.5)
    order by g.turn_deadline
    limit 50
  loop
    begin
      perform public.bot_take_turn(v_game.id);
      v_count := v_count + 1;
    exception when others then
      raise warning 'bot_take_turn failed for game %: %', v_game.id, sqlerrm;
    end;
  end loop;
  return v_count;
end;
$$;

revoke all on function public.tick_bot_turns() from public;

create or replace function public.tick_expired_turns()
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_game record;
  v_count int := 0;
begin
  for v_game in
    select id from public.games
    where status = 'in_game' and turn_deadline < now()
    order by turn_deadline
    limit 100
  loop
    begin
      perform public.auto_advance_turn(v_game.id);
      v_count := v_count + 1;
    exception when others then
      raise warning 'auto_advance_turn failed for game %: %', v_game.id, sqlerrm;
    end;
  end loop;
  return v_count;
end;
$$;

revoke all on function public.tick_expired_turns() from public;

----------------------------------------------------------------
-- 4) Watchdog: piggyback on the every-5-minutes stale-cleanup job so
--    scheduling state self-heals even if a trigger path is missed.
----------------------------------------------------------------

do $$
declare
  v_jobid bigint;
begin
  for v_jobid in select jobid from cron.job where jobname = 'sequence-stale-cleanup' loop
    perform cron.unschedule(v_jobid);
  end loop;
  perform cron.schedule(
    'sequence-stale-cleanup',
    '*/5 * * * *',
    $sql$ select public.mark_stale_games_abandoned(); select public.ensure_tick_jobs(); $sql$
  );
exception when others then
  raise notice 'Could not (re)schedule sequence-stale-cleanup: %', sqlerrm;
end;
$$;

----------------------------------------------------------------
-- 5) Reconcile immediately so the new regime starts now, not at the
--    next game event. On a quiet board this unschedules both ticks.
----------------------------------------------------------------

select public.ensure_tick_jobs();
