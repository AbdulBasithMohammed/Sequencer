-- Find Overdue Finished Games
-- Saved SQL-editor snippet (migrated from the old us-west project, 2026-06-10).
-- Run in the Supabase dashboard SQL editor or via scripts/analytics/run.sh

-- 8c. Games that *should* have been cleaned but haven't yet
--     (status finished and finished_at older than the cron grace).
--     Should normally return 0 rows — anything here means cron lag.
select id, room_id, finished_at, age(now(), finished_at) as overdue_by
from public.games
where status = 'finished'
  and finished_at < now() - interval '6 minutes'
order by finished_at;
