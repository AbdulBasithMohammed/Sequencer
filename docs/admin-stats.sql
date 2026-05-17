-- =============================================================
-- Sequencr · Admin stats playbook
-- =============================================================
--
-- Each section below is a copy-paste-ready SQL block. Run them in
-- Supabase → SQL Editor (or via the Management API the same way the
-- tests/ scripts do).
--
-- Notes:
--   - `games` rows for finished games are deleted 5 min after
--     finish by the sequence-delete-finished cron, so "games right
--     now" only ever reflects in-progress + recently-finished games.
--   - `game_moves` cascades with `games`, so move counts also wipe
--     after that 5-minute window. Treat them as live-snapshot only.
--   - `profiles` and `friendships` are durable.


-- =============================================================
-- 1. AT-A-GLANCE SNAPSHOT
-- =============================================================
-- One row, the broadest possible health-check.

select
  (select count(*) from public.profiles) as total_users,
  (select count(*) from public.profiles where is_guest) as guests,
  (select count(*) from public.profiles where not is_guest) as registered,
  (select count(*) from public.rooms) as rooms_total,
  (select count(*) from public.rooms where status = 'waiting') as rooms_waiting,
  (select count(*) from public.rooms where status = 'in_game') as rooms_in_game,
  (select count(*) from public.games where status = 'in_game') as games_in_session,
  (select count(*) from public.friendships) as friendships,
  (select count(*) from public.friend_requests) as friend_requests_pending,
  (select count(*) from public.room_invites) as room_invites_pending;


-- =============================================================
-- 2. USERS
-- =============================================================

-- 2a. Full list, newest first
select id, display_name, tag, is_guest, created_at
from public.profiles
order by created_at desc;

-- 2b. Signups by day (last 14 days), split by registered vs guest
select
  date_trunc('day', created_at)::date as day,
  count(*) filter (where not is_guest) as registered,
  count(*) filter (where is_guest) as guests,
  count(*) as total
from public.profiles
where created_at > now() - interval '14 days'
group by 1
order by 1 desc;

-- 2c. Brand new users in the last 24 hours
select display_name, tag, is_guest, created_at
from public.profiles
where created_at > now() - interval '24 hours'
order by created_at desc;

-- 2d. Guest accounts approaching the 24-hour cleanup TTL
select p.display_name, p.tag, u.created_at, u.last_sign_in_at,
       now() - coalesce(u.last_sign_in_at, u.created_at) as inactive_for
from public.profiles p
join auth.users u on u.id = p.id
where p.is_guest
order by coalesce(u.last_sign_in_at, u.created_at) asc;


-- =============================================================
-- 3. ROOMS / LOBBIES
-- =============================================================

-- 3a. All currently-existing rooms with their seat count
select
  r.code,
  r.status,
  r.target_players,
  (select count(*) from public.room_players rp where rp.room_id = r.id) as seated,
  r.team_layout,
  r.turn_seconds,
  r.created_at,
  hp.display_name as host
from public.rooms r
join public.profiles hp on hp.id = r.host_id
order by r.created_at desc;

-- 3b. Who's sitting in each waiting lobby (multi-row per room)
select
  r.code,
  r.status,
  rp.seat_index,
  p.display_name,
  p.tag,
  rp.team,
  rp.ready
from public.rooms r
join public.room_players rp on rp.room_id = r.id
join public.profiles p on p.id = rp.user_id
where r.status = 'waiting'
order by r.created_at desc, rp.seat_index;

-- 3c. Average + max seat count across all rooms
select
  avg(seated)::numeric(10,2) as avg_players_per_room,
  max(seated) as max_players_in_a_room,
  count(*) filter (where seated = 0) as empty_rooms
from (
  select r.id,
         (select count(*) from public.room_players rp where rp.room_id = r.id) as seated
  from public.rooms r
) s;

-- 3d. Rooms with nobody sitting in them (orphans — host left, etc.)
select r.code, r.status, r.created_at
from public.rooms r
where not exists (
  select 1 from public.room_players rp where rp.room_id = r.id
)
order by r.created_at;


-- =============================================================
-- 4. GAMES IN SESSION
-- =============================================================

-- 4a. Every in-progress game with players + turn info
select
  g.id as game_id,
  r.code as room_code,
  g.version,
  g.started_at,
  age(now(), g.started_at) as elapsed,
  g.turn_seat,
  active.display_name as on_turn,
  g.turn_deadline,
  g.turn_deadline - now() as time_to_timeout,
  g.deck_count,
  jsonb_array_length(g.discard) as discard_count,
  (select count(*) from public.room_players rp where rp.room_id = g.room_id) as players
from public.games g
join public.rooms r on r.id = g.room_id
left join public.room_players rp_active
       on rp_active.room_id = g.room_id and rp_active.seat_index = g.turn_seat
left join public.profiles active on active.id = rp_active.user_id
where g.status = 'in_game'
order by g.started_at desc;

-- 4b. Roster of every in-progress game: who's seated, what team
select r.code, p.display_name, p.tag, rp.seat_index, rp.team, rp.ready
from public.games g
join public.rooms r on r.id = g.room_id
join public.room_players rp on rp.room_id = g.room_id
join public.profiles p on p.id = rp.user_id
where g.status = 'in_game'
order by r.code, rp.seat_index;

-- 4b-i. Single number: how many distinct people are currently in a game?
select count(distinct rp.user_id) as users_in_game
from public.games g
join public.room_players rp on rp.room_id = g.room_id
where g.status = 'in_game';

-- 4b-ii. Same but split by guest vs registered
select
  count(*) filter (where not p.is_guest) as registered_in_game,
  count(*) filter (where p.is_guest)     as guests_in_game,
  count(*) as total_in_game
from (
  select distinct rp.user_id
  from public.games g
  join public.room_players rp on rp.room_id = g.room_id
  where g.status = 'in_game'
) u
join public.profiles p on p.id = u.user_id;

-- 4c. Sequences claimed in active games (board progress)
select
  r.code,
  s.team,
  jsonb_array_length(s.cells) as chips_in_sequence
from public.games g
join public.rooms r on r.id = g.room_id,
     jsonb_array_elements(g.sequences) as s
where g.status = 'in_game';

-- 4d. Move-rate per active game (turns / minute, rough engagement
--     indicator while game_moves rows still exist)
select
  r.code,
  count(m.*) as moves_logged,
  count(m.*) / greatest(extract(epoch from age(now(), g.started_at)) / 60.0, 1)
    as moves_per_minute
from public.games g
join public.rooms r on r.id = g.room_id
left join public.game_moves m on m.game_id = g.id
where g.status = 'in_game'
group by r.code, g.started_at;


-- =============================================================
-- 5. ACTIVITY / MOVES
-- =============================================================
-- Live-only — these clear with the games table on cleanup.

-- 5a. Action mix across all currently-stored moves
select action, count(*) as moves
from public.game_moves
group by action
order by moves desc;

-- 5b. Move count per player (currently-stored moves only)
select p.display_name, p.tag, count(*) as moves
from public.game_moves m
join public.profiles p on p.id = m.user_id
where m.action in ('place', 'remove', 'swap_dead')
group by p.display_name, p.tag
order by moves desc;

-- 5c. Last 20 moves across the system (real-time stream)
select m.created_at, r.code, p.display_name, m.action, m.card,
       m.tile_row, m.tile_col, m.payload
from public.game_moves m
join public.games g on g.id = m.game_id
join public.rooms r on r.id = g.room_id
left join public.profiles p on p.id = m.user_id
order by m.created_at desc
limit 20;


-- =============================================================
-- 6. FRIENDS GRAPH
-- =============================================================

-- 6a. All friendships (one row per pair)
select
  pa.display_name as user_a, pa.tag as tag_a,
  pb.display_name as user_b, pb.tag as tag_b,
  f.created_at
from public.friendships f
join public.profiles pa on pa.id = f.user_a
join public.profiles pb on pb.id = f.user_b
order by f.created_at desc;

-- 6b. Friend count per user
select p.display_name, p.tag,
       (select count(*) from public.friendships f
          where f.user_a = p.id or f.user_b = p.id) as friends
from public.profiles p
where not p.is_guest
order by friends desc;

-- 6c. Pending friend requests (with names)
select
  pf.display_name as from_user, pf.tag as from_tag,
  pt.display_name as to_user,   pt.tag as to_tag,
  fr.created_at
from public.friend_requests fr
join public.profiles pf on pf.id = fr.from_user
join public.profiles pt on pt.id = fr.to_user
order by fr.created_at desc;

-- 6d. Ignore-list contents (per user)
select
  pu.display_name as user, pu.tag as user_tag,
  pi.display_name as ignored, pi.tag as ignored_tag,
  fi.created_at
from public.friend_ignores fi
join public.profiles pu on pu.id = fi.user_id
join public.profiles pi on pi.id = fi.ignored_user_id
order by fi.created_at desc;


-- =============================================================
-- 7. ROOM INVITES
-- =============================================================

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


-- =============================================================
-- 8. SYSTEM HEALTH
-- =============================================================

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

-- 8c. Games that *should* have been cleaned but haven't yet
--     (status finished and finished_at older than the cron grace).
--     Should normally return 0 rows — anything here means cron lag.
select id, room_id, finished_at, age(now(), finished_at) as overdue_by
from public.games
where status = 'finished'
  and finished_at < now() - interval '6 minutes'
order by finished_at;

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

-- 8d. Stale guest accounts the cron will sweep on its next pass
select p.display_name, p.tag, u.created_at, u.last_sign_in_at
from auth.users u
join public.profiles p on p.id = u.id
where u.is_anonymous
  and u.created_at < now() - interval '1 hour'
  and coalesce(u.last_sign_in_at, u.created_at) < now() - interval '24 hours';

-- 8e. Database table sizes (largest first)
select
  schemaname,
  relname as table_name,
  pg_size_pretty(pg_total_relation_size(format('%I.%I', schemaname, relname)::regclass))
    as total_size,
  n_live_tup as approx_rows
from pg_stat_user_tables
where schemaname in ('public', 'auth')
order by pg_total_relation_size(format('%I.%I', schemaname, relname)::regclass) desc
limit 20;
