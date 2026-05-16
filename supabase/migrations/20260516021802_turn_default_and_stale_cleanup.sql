-- Defaults & stale-game cleanup.
--
-- 1) Default turn duration moved from 60s → 120s (2 minutes). Existing
--    rooms keep whatever they were created with; only new rooms inherit
--    the new default.
-- 2) rooms.target_players CHECK + create_room: add 9 to the allowed
--    player counts (we already wired 9p hand_size + 3-team layout).
-- 3) Trigger: when a game's status flips to 'finished', flip the parent
--    room back to 'waiting' so the room slot is freed up.
-- 4) mark_stale_games_abandoned + cron job: every 5 minutes, scan for
--    games in_game with no human move (place / remove / swap_dead) in
--    the last 30 minutes — mark those games 'finished' (no winner) and
--    release the room. Stops the DB from filling up with zombie games.

----------------------------------------------------------------
-- 1) rooms.turn_seconds default → 120
----------------------------------------------------------------

alter table public.rooms alter column turn_seconds set default 120;

----------------------------------------------------------------
-- 2) Add 9 to the allowed player counts
----------------------------------------------------------------

alter table public.rooms
  drop constraint if exists rooms_target_players_check;

alter table public.rooms
  add constraint rooms_target_players_check
  check (target_players in (2, 3, 4, 6, 8, 9, 10, 12));

create or replace function public.create_room(p_target_players int)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_room_id uuid;
  v_code text;
  v_attempts int := 0;
begin
  if v_user_id is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  if p_target_players not in (2, 3, 4, 6, 8, 9, 10, 12) then
    raise exception 'Invalid player count: %', p_target_players
      using errcode = '22023';
  end if;

  loop
    v_code := public.generate_room_code();
    begin
      insert into public.rooms (code, host_id, target_players)
      values (v_code, v_user_id, p_target_players)
      returning id into v_room_id;
      exit;
    exception when unique_violation then
      v_attempts := v_attempts + 1;
      if v_attempts > 10 then
        raise exception 'Could not generate a unique room code'
          using errcode = 'P0001';
      end if;
    end;
  end loop;

  insert into public.room_players (room_id, user_id, seat_index)
  values (v_room_id, v_user_id, 0);

  return v_code;
end;
$$;

----------------------------------------------------------------
-- 3) Trigger: game finish -> room back to 'waiting'
----------------------------------------------------------------

create or replace function public.reset_room_on_game_finish()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if NEW.status = 'finished' and (OLD.status is distinct from 'finished') then
    update public.rooms set status = 'waiting' where id = NEW.room_id;
  end if;
  return NEW;
end;
$$;

drop trigger if exists reset_room_on_game_finish_trigger on public.games;
create trigger reset_room_on_game_finish_trigger
after update on public.games
for each row
when (NEW.status is distinct from OLD.status)
execute function public.reset_room_on_game_finish();

----------------------------------------------------------------
-- 4) Stale-game cleanup.
--    Stale = in_game AND started_at older than 30 min AND no human move
--    (place / remove / swap_dead) in the last 30 min. We mark the game
--    'finished' (no winner) and the finish trigger above releases the
--    room. A 'system' move is logged with event='stale_cleanup' so the
--    abandonment is auditable.
----------------------------------------------------------------

create or replace function public.mark_stale_games_abandoned()
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
    select g.id, g.version
    from public.games g
    where g.status = 'in_game'
      and g.started_at < now() - interval '30 minutes'
      and not exists (
        select 1
        from public.game_moves m
        where m.game_id = g.id
          and m.action in ('place', 'remove', 'swap_dead')
          and m.created_at > now() - interval '30 minutes'
      )
  loop
    update public.games set
      version = v_game.version + 1,
      status = 'finished',
      winner_team = null,
      finished_at = now(),
      turn_deadline = null
    where id = v_game.id;

    insert into public.game_moves (
      game_id, version, user_id, action, payload
    ) values (
      v_game.id,
      v_game.version + 1,
      null,
      'system',
      jsonb_build_object('event', 'stale_cleanup')
    );

    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

----------------------------------------------------------------
-- 5) Cron — every 5 minutes
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
    $sql$ select public.mark_stale_games_abandoned(); $sql$
  );
exception when others then
  raise notice 'Could not (re)schedule sequence-stale-cleanup: %', sqlerrm;
end;
$$;
