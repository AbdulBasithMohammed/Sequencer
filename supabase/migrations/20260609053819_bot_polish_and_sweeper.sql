-- Phase 8.G — Bot polish + robustness.
--
-- 1. Think-time jitter. The bot tick now fires each bot a random 0–1.5s
--    AFTER its base think delay, so consecutive bot turns (an all-bot game,
--    or several bot games on the same cron beat) don't move in lockstep.
-- 2. Orphan-bot sweeper. Belt-and-suspenders sanitation matching guests:
--    a bot profile with no remaining seat is deleted. The on_room_player_
--    deleted trigger (8.A) already reaps bots on remove/kick/room-delete;
--    this catches anything that ever slips past it. No creation grace is
--    needed because add_bot inserts profile + seat atomically.
--
-- The deck-reshuffle and no-legal-move forced-discard paths already live in
-- bot_take_turn (identical to the human RPCs); 8.G verifies them via a full
-- all-bot game rather than adding code.

----------------------------------------------------------------
-- tick_bot_turns — add per-turn jitter to the think delay.
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
    perform public.bot_take_turn(v_game.id);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

revoke all on function public.tick_bot_turns() from public;

----------------------------------------------------------------
-- delete_orphan_bots — sweep bot profiles with no seat. Runs hourly.
----------------------------------------------------------------

create or replace function public.delete_orphan_bots()
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_count int;
begin
  with d as (
    delete from public.profiles
    where is_bot
      and not exists (
        select 1 from public.room_players rp where rp.user_id = profiles.id
      )
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
  for v_jobid in select jobid from cron.job where jobname = 'sequence-delete-orphan-bots' loop
    perform cron.unschedule(v_jobid);
  end loop;
  perform cron.schedule(
    'sequence-delete-orphan-bots',
    '7 * * * *',  -- hourly, offset from the other sweepers
    $sql$ select public.delete_orphan_bots(); $sql$
  );
exception when others then
  raise notice 'Could not (re)schedule sequence-delete-orphan-bots: %', sqlerrm;
end;
$$;
