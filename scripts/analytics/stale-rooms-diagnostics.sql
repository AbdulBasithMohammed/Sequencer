-- Stale Rooms Diagnostics
-- Saved SQL-editor snippet (migrated from the old us-west project, 2026-06-10).
-- Run in the Supabase dashboard SQL editor or via scripts/analytics/run.sh

-- 8c-i. Stale rooms diagnostics — what the delete_stale_rooms cron
--       will pick up on its next pass. Uses last_activity_at so a
--       room being actively poked at survives even past 24h.
select r.code, r.status, r.created_at, r.last_activity_at,
       age(now(), r.last_activity_at) as idle_for,
       (select count(*) from public.room_players where room_id = r.id) as seated,
       case
         when not exists (
           select 1 from public.room_players where room_id = r.id
         ) and r.last_activity_at < now() - interval '5 minutes'
           then 'empty + idle > 5 min'
         when r.status = 'in_game'
              and not exists (
                select 1 from public.games
                where room_id = r.id and status = 'in_game'
              )
              and r.last_activity_at < now() - interval '5 minutes'
           then 'in_game w/o live game + idle > 5 min'
         when r.status = 'waiting'
              and r.last_activity_at < now() - interval '24 hours'
           then 'waiting, idle > 24 h'
       end as reason
from public.rooms r
where
  (not exists (select 1 from public.room_players where room_id = r.id)
   and r.last_activity_at < now() - interval '5 minutes')
  or
  (r.status = 'in_game'
   and not exists (select 1 from public.games
                   where room_id = r.id and status = 'in_game')
   and r.last_activity_at < now() - interval '5 minutes')
  or
  (r.status = 'waiting'
   and r.last_activity_at < now() - interval '24 hours');
