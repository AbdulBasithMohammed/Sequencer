-- Pending Friend Requests Timeline
-- Saved SQL-editor snippet (migrated from the old us-west project, 2026-06-10).
-- Run in the Supabase dashboard SQL editor or via scripts/analytics/run.sh

-- 6c. Pending friend requests (with names)
select
  pf.display_name as from_user, pf.tag as from_tag,
  pt.display_name as to_user,   pt.tag as to_tag,
  fr.created_at
from public.friend_requests fr
join public.profiles pf on pf.id = fr.from_user
join public.profiles pt on pt.id = fr.to_user
order by fr.created_at desc;
