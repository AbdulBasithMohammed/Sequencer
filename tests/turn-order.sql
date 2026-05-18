-- Tests for team-alternating turn order.
-- Exercises next_turn_seat() directly with synthetic room_players rows.
--
-- Run via: set -a && source .env.local && set +a &&
--   psql "$SUPABASE_DB_URL" -f tests/turn-order.sql
-- ...or paste into Supabase SQL editor.

begin;

-- Throwaway room + 4 fake users for the test fixtures.
create temp table _ids (room uuid, u1 uuid, u2 uuid, u3 uuid, u4 uuid);
insert into _ids values
  (gen_random_uuid(), gen_random_uuid(), gen_random_uuid(),
   gen_random_uuid(), gen_random_uuid());

-- We can't insert into real room_players without auth.users rows. Instead,
-- create a temp shadow table next_turn_seat will see if we point its
-- search_path. Since the function hardcodes public.room_players, we
-- temporarily insert into the real table; we'll roll back at the end.

-- Stub host (required for rooms.host_id FK). Use any existing user from
-- profiles; pick a host that already exists.
insert into public.rooms (id, code, status, host_id, target_players,
                          team_layout, turn_seconds)
select (select room from _ids), 'TEST01', 'in_game', id, 4, '2v2', 120
from public.profiles
limit 1;

-- Skip the auth.users FK by directly inserting profiles too — but the
-- room_players FK targets profiles.id. We need 4 profiles. Re-use four
-- existing profiles instead of creating fake ones (cleaner; we won't
-- actually start a game).
with avail as (
  select id, row_number() over (order by created_at) as rn
  from public.profiles
  limit 4
)
update _ids set
  u1 = (select id from avail where rn = 1),
  u2 = (select id from avail where rn = 2),
  u3 = (select id from avail where rn = 3),
  u4 = (select id from avail where rn = 4);

-- ========================================================================
-- Scenario A: balanced 2v2 — seats interleaved by team (default).
--   seat 0 = T1, seat 1 = T2, seat 2 = T1, seat 3 = T2
-- Expected order: 0 → 1 → 2 → 3 → 0 → ...
-- ========================================================================
insert into public.room_players (room_id, user_id, seat_index, team)
select (select room from _ids), (select u1 from _ids), 0, 1
union all select (select room from _ids), (select u2 from _ids), 1, 2
union all select (select room from _ids), (select u3 from _ids), 2, 1
union all select (select room from _ids), (select u4 from _ids), 3, 2;

-- Simulate 8 turns starting at seat 0 with empty cursor.
do $$
declare
  v_room uuid := (select room from _ids);
  v_seat int := 0;
  v_cursor jsonb := '{}'::jsonb;
  v_adv record;
  v_order int[] := array[v_seat];
  v_expected int[] := array[0, 1, 2, 3, 0, 1, 2, 3];
begin
  for i in 1..7 loop
    select nt.next_seat, nt.new_cursor into v_adv
    from public.next_turn_seat(v_room, v_seat, v_cursor) nt;
    v_seat := v_adv.next_seat;
    v_cursor := v_adv.new_cursor;
    v_order := v_order || v_seat;
  end loop;
  raise notice 'A balanced 2v2: got=% expected=%', v_order, v_expected;
  if v_order <> v_expected then
    raise exception 'FAIL A: balanced 2v2 order wrong';
  end if;
end$$;

-- ========================================================================
-- Scenario B: 2v2 with players swapped → seats T1,T2,T2,T1 (non-interleaved).
--   seat 0 = T1, seat 1 = T2, seat 2 = T2, seat 3 = T1
-- Expected order: 0 → 1 → 3 → 2 → 0 → 1 → 3 → 2
-- (next_team alternates; within each team smallest-seat round-robin)
-- ========================================================================
update public.room_players set team = 2
  where room_id = (select room from _ids) and seat_index = 2;
update public.room_players set team = 1
  where room_id = (select room from _ids) and seat_index = 3;

do $$
declare
  v_room uuid := (select room from _ids);
  v_seat int := 0;
  v_cursor jsonb := '{}'::jsonb;
  v_adv record;
  v_order int[] := array[v_seat];
  v_expected int[] := array[0, 1, 3, 2, 0, 1, 3, 2];
begin
  for i in 1..7 loop
    select nt.next_seat, nt.new_cursor into v_adv
    from public.next_turn_seat(v_room, v_seat, v_cursor) nt;
    v_seat := v_adv.next_seat;
    v_cursor := v_adv.new_cursor;
    v_order := v_order || v_seat;
  end loop;
  raise notice 'B non-interleaved 2v2: got=% expected=%', v_order, v_expected;
  if v_order <> v_expected then
    raise exception 'FAIL B: non-interleaved 2v2 order wrong';
  end if;
end$$;

-- ========================================================================
-- Scenario C: unbalanced 1v2.
--   seat 0 = T1, seat 1 = T2, seat 2 = T2
-- Expected order: 0 → 1 → 0 → 2 → 0 → 1 → 0 → 2 (T1's lone player every 2nd
-- turn, T2 round-robins between its two players)
-- ========================================================================
delete from public.room_players
  where room_id = (select room from _ids) and seat_index = 3;
update public.room_players set team = 2
  where room_id = (select room from _ids) and seat_index = 1;
update public.room_players set team = 2
  where room_id = (select room from _ids) and seat_index = 2;
update public.room_players set team = 1
  where room_id = (select room from _ids) and seat_index = 0;

do $$
declare
  v_room uuid := (select room from _ids);
  v_seat int := 0;
  v_cursor jsonb := '{}'::jsonb;
  v_adv record;
  v_order int[] := array[v_seat];
  v_expected int[] := array[0, 1, 0, 2, 0, 1, 0, 2];
begin
  for i in 1..7 loop
    select nt.next_seat, nt.new_cursor into v_adv
    from public.next_turn_seat(v_room, v_seat, v_cursor) nt;
    v_seat := v_adv.next_seat;
    v_cursor := v_adv.new_cursor;
    v_order := v_order || v_seat;
  end loop;
  raise notice 'C unbalanced 1v2: got=% expected=%', v_order, v_expected;
  if v_order <> v_expected then
    raise exception 'FAIL C: unbalanced 1v2 order wrong';
  end if;
end$$;

-- ========================================================================
-- Scenario D: 3 teams, 2v2v2 — 6 players, naturally round-robin.
--   seat 0 = T1, seat 1 = T2, seat 2 = T3, seat 3 = T1, seat 4 = T2, seat 5 = T3
-- Expected order: 0 → 1 → 2 → 3 → 4 → 5 → 0 → ...
-- Need 3 more real profile ids for seats 3/4/5.
-- ========================================================================
with avail as (
  select id, row_number() over (order by created_at) as rn
  from public.profiles
  limit 7
)
insert into public.room_players (room_id, user_id, seat_index, team)
select (select room from _ids), (select id from avail where rn = 5), 3, 1
union all
select (select room from _ids), (select id from avail where rn = 6), 4, 2
union all
select (select room from _ids), (select id from avail where rn = 7), 5, 3;

-- Re-stamp teams cleanly.
update public.room_players set team = 1
  where room_id = (select room from _ids) and seat_index in (0, 3);
update public.room_players set team = 2
  where room_id = (select room from _ids) and seat_index in (1, 4);
update public.room_players set team = 3
  where room_id = (select room from _ids) and seat_index in (2, 5);

do $$
declare
  v_room uuid := (select room from _ids);
  v_seat int := 0;
  v_cursor jsonb := '{}'::jsonb;
  v_adv record;
  v_order int[] := array[v_seat];
  v_expected int[] := array[0, 1, 2, 3, 4, 5, 0, 1, 2, 3, 4, 5];
begin
  for i in 1..11 loop
    select nt.next_seat, nt.new_cursor into v_adv
    from public.next_turn_seat(v_room, v_seat, v_cursor) nt;
    v_seat := v_adv.next_seat;
    v_cursor := v_adv.new_cursor;
    v_order := v_order || v_seat;
  end loop;
  raise notice 'D 2v2v2: got=% expected=%', v_order, v_expected;
  if v_order <> v_expected then
    raise exception 'FAIL D: 2v2v2 order wrong';
  end if;
end$$;

-- Always roll back so the test leaves no residue.
rollback;
