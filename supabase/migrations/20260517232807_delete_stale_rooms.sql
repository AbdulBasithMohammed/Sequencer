-- Stale-room cleanup. The existing crons cover games (mark-stale +
-- delete-finished) and guests, but rooms themselves accumulated:
--   - Hosts created a room and never invited anyone
--   - Everyone left, leaving an empty waiting room
--   - Game row got purged but room.status was stuck on 'in_game'
--
-- Three matching rules, applied with a 5-min grace so we never wipe a
-- fresh room before its host can drop the code into chat:
--   1. Status = 'waiting' AND zero seated players, > 5 min old
--   2. Status = 'in_game' but no actual in_game game row, > 5 min old
--   3. Status = 'waiting' AND > 24 hours old (abandoned even if seated)
--
-- Rooms cascade-delete to room_players, room_invites, room_bans and
-- games (which itself cascades to game_moves), so a single DELETE
-- here cleans up everything beneath.

create or replace function public.delete_stale_rooms()
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_deleted int;
begin
  with d as (
    delete from public.rooms r
    where
      (
        -- empty waiting room sitting around
        not exists (
          select 1 from public.room_players where room_id = r.id
        )
        and r.created_at < now() - interval '5 minutes'
      )
      or
      (
        -- room flagged in_game but no live game exists
        r.status = 'in_game'
        and not exists (
          select 1 from public.games
          where room_id = r.id and status = 'in_game'
        )
        and r.created_at < now() - interval '5 minutes'
      )
      or
      (
        -- old abandoned lobby — players never started a game
        r.status = 'waiting'
        and r.created_at < now() - interval '24 hours'
      )
    returning id
  )
  select count(*) into v_deleted from d;
  return v_deleted;
end;
$$;

do $$
declare
  v_jobid bigint;
begin
  for v_jobid in select jobid from cron.job
                 where jobname = 'sequence-delete-stale-rooms' loop
    perform cron.unschedule(v_jobid);
  end loop;
  perform cron.schedule(
    'sequence-delete-stale-rooms',
    '*/5 * * * *',
    $sql$ select public.delete_stale_rooms(); $sql$
  );
exception when others then
  raise notice 'Could not (re)schedule sequence-delete-stale-rooms: %', sqlerrm;
end;
$$;
