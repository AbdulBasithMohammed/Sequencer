-- Roll back the stats RPC (product decision: stats removed for now)
-- and add aggressive cleanup for finished games so storage stays tight.
--
-- Cleanup behaviour:
--   - cron every 5 minutes deletes any game with status='finished' and
--     finished_at older than 5 minutes
--   - game_moves cascades via FK so the move log goes with the game
--   - 5 minute grace is enough for the win screen + Back-to-lobby flow;
--     a player who refreshes the game URL after 5 min gets routed to
--     /play (handled by existing page guard)

drop function if exists public.get_my_stats();

create or replace function public.delete_finished_games()
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_deleted int;
begin
  with d as (
    delete from public.games
    where status = 'finished'
      and finished_at is not null
      and finished_at < now() - interval '5 minutes'
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
  for v_jobid in select jobid from cron.job where jobname = 'sequence-delete-finished' loop
    perform cron.unschedule(v_jobid);
  end loop;
  perform cron.schedule(
    'sequence-delete-finished',
    '*/5 * * * *',
    $sql$ select public.delete_finished_games(); $sql$
  );
exception when others then
  raise notice 'Could not (re)schedule sequence-delete-finished: %', sqlerrm;
end;
$$;
