-- Follow-up to 20260516021802: that migration's cron schedule string was
-- '5 minutes' which this pg_cron rejects. Re-scheduling with standard
-- 5-field cron syntax (every 5 minutes).

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
