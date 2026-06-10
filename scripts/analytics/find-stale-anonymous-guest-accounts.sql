-- Find Stale Anonymous Guest Accounts
-- Saved SQL-editor snippet (migrated from the old us-west project, 2026-06-10).
-- Run in the Supabase dashboard SQL editor or via scripts/analytics/run.sh

-- 8d. Stale guest accounts the cron will sweep on its next pass
select p.display_name, p.tag, u.created_at, u.last_sign_in_at
from auth.users u
join public.profiles p on p.id = u.id
where u.is_anonymous
  and u.created_at < now() - interval '1 hour'
  and coalesce(u.last_sign_in_at, u.created_at) < now() - interval '24 hours';
