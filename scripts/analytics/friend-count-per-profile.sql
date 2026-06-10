-- Friend Count per Profile
-- Saved SQL-editor snippet (migrated from the old us-west project, 2026-06-10).
-- Run in the Supabase dashboard SQL editor or via scripts/analytics/run.sh

-- 6b. Friend count per user
select p.display_name, p.tag,
       (select count(*) from public.friendships f
          where f.user_a = p.id or f.user_b = p.id) as friends
from public.profiles p
where not p.is_guest
order by friends desc;
