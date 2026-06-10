-- View Cron Jobs and Recent Runs
-- Saved SQL-editor snippet (migrated from the old us-west project, 2026-06-10).
-- Run in the Supabase dashboard SQL editor or via scripts/analytics/run.sh

-- 8a. All cron jobs and their schedules
select jobid, jobname, schedule, command, active
from cron.job
order by jobname;

-- 8b. Last 20 cron runs (success/failure)
select jobid, runid, job_pid, status, return_message,
       start_time, end_time
from cron.job_run_details
order by start_time desc
limit 20;
