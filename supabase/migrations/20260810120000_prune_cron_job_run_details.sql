-- Prune cron.job_run_details so the free-tier 500 MB budget stays intact.
--
-- Why this exists:
--   pg_cron writes one row to cron.job_run_details for every job execution,
--   including the full command text. The scheduler runs roughly 61k jobs/day:
--
--     sequence-tick-bots          every 2s   -> 43,200/day
--     sequence-tick-turns         every 5s   -> 17,280/day
--     sequence-stale-cleanup      every 5m   ->    288/day
--     sequence-delete-finished    every 5m   ->    288/day
--     sequence-delete-stale-rooms every 5m   ->    288/day
--     sequence-delete-stale-guests   hourly  ->     24/day
--     sequence-delete-orphan-bots    hourly  ->     24/day
--
--   That is ~10 MB/day. Nothing pruned it, so by 2026-08-10 the table had
--   reached 584 MB out of a 602 MB database — 97% of all storage, against
--   <1 MB of actual application data. The org went 146% over quota.
--
-- Retention: 24 hours. That keeps ~61k rows (~10 MB) which is far more than
-- scripts/analytics/view-cron-jobs-and-recent-runs.sql needs (last 20 runs),
-- while holding steady-state usage to ~10 MB instead of unbounded growth.
--
-- NOTE: this migration stops the growth but does NOT shrink the existing
-- 584 MB file. A plain DELETE marks tuples dead; the space is reused by new
-- inserts but is not returned to disk, and Supabase bills on disk. The
-- one-time reclaim (TRUNCATE or VACUUM FULL) has to be run manually in the
-- SQL editor — neither can run inside a migration transaction. See
-- docs/free-tier-storage.md.

create or replace function public.prune_cron_run_details()
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_deleted int;
begin
  with d as (
    delete from cron.job_run_details
    where end_time < now() - interval '24 hours'
       or (end_time is null and start_time < now() - interval '24 hours')
    returning runid
  )
  select count(*) into v_deleted from d;
  return v_deleted;
end;
$$;

-- Hourly rather than daily: at ~10 MB/day a daily sweep lets the table swing
-- by a full day's worth between runs, and each sweep deletes 61k rows at once.
-- Hourly keeps both the size and the per-run delete volume flat.
do $$
declare
  v_jobid bigint;
begin
  for v_jobid in select jobid from cron.job
                 where jobname = 'sequence-prune-cron-history' loop
    perform cron.unschedule(v_jobid);
  end loop;
  perform cron.schedule(
    'sequence-prune-cron-history',
    '23 * * * *',  -- hourly, offset from the other sweepers
    $sql$ select public.prune_cron_run_details(); $sql$
  );
exception when others then
  raise notice 'Could not (re)schedule sequence-prune-cron-history: %', sqlerrm;
end;
$$;
