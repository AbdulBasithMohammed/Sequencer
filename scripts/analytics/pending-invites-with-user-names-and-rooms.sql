-- Pending Invites with User Names and Rooms
-- Saved SQL-editor snippet (migrated from the old us-west project, 2026-06-10).
-- Run in the Supabase dashboard SQL editor or via scripts/analytics/run.sh

-- 7a. Pending invites with full names + rooms
select
  pf.display_name as from_user, pf.tag as from_tag,
  pt.display_name as to_user,   pt.tag as to_tag,
  r.code as room_code,
  r.status as room_status,
  ri.created_at
from public.room_invites ri
join public.rooms r on r.id = ri.room_id
join public.profiles pf on pf.id = ri.from_user
join public.profiles pt on pt.id = ri.to_user
order by ri.created_at desc;
