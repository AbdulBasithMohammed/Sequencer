-- Retrieve All Friendship Pairs
-- Saved SQL-editor snippet (migrated from the old us-west project, 2026-06-10).
-- Run in the Supabase dashboard SQL editor or via scripts/analytics/run.sh

-- 6a. All friendships (one row per pair)
select
  pa.display_name as user_a, pa.tag as tag_a,
  pb.display_name as user_b, pb.tag as tag_b,
  f.created_at
from public.friendships f
join public.profiles pa on pa.id = f.user_a
join public.profiles pb on pb.id = f.user_b
order by f.created_at desc;
