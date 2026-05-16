-- Test: swap_dead_card RPC behaves correctly.
--
-- Run via Supabase admin API (.env.local + curl):
--
--   set -a && source .env.local && set +a && \
--     curl -s -X POST \
--       "https://api.supabase.com/v1/projects/lbgfjqzvmacikywyzwzr/database/query" \
--       -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
--       -H "Content-Type: application/json" \
--       --data-binary @<(jq -Rs '{query: .}' tests/swap-dead-card.sql)
--
-- Or paste the body into the Supabase SQL editor. The script picks up
-- the two oldest profiles in the database and uses them as test users
-- (they don't need to know anything — the test creates an isolated
-- room + game, runs assertions, then deletes the room which cascades
-- everything away).
--
-- Asserts (raises on failure, all-pass = "ALL TESTS PASSED" notice):
--   1. Owner of a dead card on their turn → swap succeeds; card gone,
--      replacement drawn, version +1, turn does NOT advance.
--   2. Non-dead card → RPC rejects with "Card is not dead".
--   3. Off-turn caller → RPC rejects with "Not your turn".
--   4. Jack → RPC rejects with "Jacks are never dead".

do $$
declare
  v_user_a uuid;
  v_user_b uuid;
  v_room_id uuid;
  v_game_id uuid;
  v_board jsonb;
  v_dead_card text := '2D';
  v_r int;
  v_c int;
  v_call_result int;
  v_hand_after jsonb;
  v_version_after int;
  v_turn_after int;
  v_started_version int := 5;
  v_error_message text;
begin
  -- Pick any two existing profiles (test rides on existing users so we
  -- don't have to fake auth.users entries).
  select id into v_user_a from public.profiles order by created_at limit 1;
  select id into v_user_b from public.profiles where id <> v_user_a
    order by created_at limit 1;
  if v_user_a is null or v_user_b is null then
    raise exception 'Need at least 2 profiles in the database';
  end if;

  -- Isolated room. 'TESTDC' matches the [A-Z0-9]{6} check.
  insert into public.rooms (code, host_id, target_players, status, team_layout)
  values ('TESTDC', v_user_a, 2, 'in_game', 'auto')
  returning id into v_room_id;

  insert into public.room_players (room_id, user_id, seat_index, team, token_color)
  values (v_room_id, v_user_a, 0, 1, 'pink'),
         (v_room_id, v_user_b, 1, 2, 'blue');

  -- Build a board where every '2D' position is occupied → '2D' is dead.
  v_board := public.empty_board();
  for v_r in 0..9 loop
    for v_c in 0..9 loop
      if public.card_at(v_r, v_c) = v_dead_card then
        v_board := jsonb_set(
          v_board,
          array[v_r::text, v_c::text],
          jsonb_build_object('team', 1, 'sequence_ids', '[]'::jsonb)
        );
      end if;
    end loop;
  end loop;

  -- Game in progress, user_a on turn (seat 0). Hand has the dead card
  -- plus two normal cards. Deck has one card so the swap can draw.
  insert into public.games (
    room_id, host_id, status, version, deck, discard, hands, board,
    sequences, turn_seat, turn_deadline, started_at
  ) values (
    v_room_id, v_user_a, 'in_game', v_started_version,
    jsonb_build_array('5C', '6C', '7C'),
    '[]'::jsonb,
    jsonb_build_object(
      v_user_a::text, jsonb_build_array(v_dead_card, 'AH', 'KH'),
      v_user_b::text, jsonb_build_array('5D', '6D', '7D')
    ),
    v_board,
    '[]'::jsonb,
    0,
    now() + interval '60 seconds',
    now()
  ) returning id into v_game_id;

  ------------------------------------------------------------------
  -- TEST 1: user_a swaps the dead card on their turn — should succeed
  ------------------------------------------------------------------
  perform set_config('request.jwt.claim.sub', v_user_a::text, true);

  v_call_result := public.swap_dead_card(v_game_id, v_started_version, v_dead_card);
  if v_call_result <> v_started_version + 1 then
    raise exception 'TEST 1 FAILED: expected version %, got %',
      v_started_version + 1, v_call_result;
  end if;

  select hands -> v_user_a::text, version, turn_seat
    into v_hand_after, v_version_after, v_turn_after
  from public.games where id = v_game_id;

  -- '2D' should be gone from the hand
  if exists (
    select 1 from jsonb_array_elements_text(v_hand_after) as c
    where c = v_dead_card
  ) then
    raise exception 'TEST 1 FAILED: dead card still in hand: %', v_hand_after;
  end if;

  -- Hand should still be 3 cards (one swapped out, one drawn)
  if jsonb_array_length(v_hand_after) <> 3 then
    raise exception 'TEST 1 FAILED: hand size = %, expected 3 (%)',
      jsonb_array_length(v_hand_after), v_hand_after;
  end if;

  -- Turn does NOT advance — still user_a's turn (seat 0)
  if v_turn_after <> 0 then
    raise exception 'TEST 1 FAILED: turn advanced to seat %, expected 0',
      v_turn_after;
  end if;

  raise notice 'TEST 1 PASSED: dead card swapped on own turn (v % -> %, hand %, turn stays at seat 0)',
    v_started_version, v_version_after, v_hand_after;

  ------------------------------------------------------------------
  -- TEST 2: try to swap a non-dead card — should reject
  ------------------------------------------------------------------
  begin
    perform public.swap_dead_card(v_game_id, v_version_after, 'AH');
    raise exception 'TEST 2 FAILED: swap_dead_card accepted a non-dead card';
  exception
    when others then
      v_error_message := sqlerrm;
      if v_error_message not like '%not dead%' then
        raise exception 'TEST 2 FAILED: unexpected error: %', v_error_message;
      end if;
      raise notice 'TEST 2 PASSED: non-dead card rejected (%) ', v_error_message;
  end;

  ------------------------------------------------------------------
  -- TEST 3: swap while off-turn — should reject
  ------------------------------------------------------------------
  perform set_config('request.jwt.claim.sub', v_user_b::text, true);
  begin
    -- doesn't matter what card; the turn check runs before card validation
    perform public.swap_dead_card(v_game_id, v_version_after, '5D');
    raise exception 'TEST 3 FAILED: swap_dead_card accepted off-turn call';
  exception
    when others then
      v_error_message := sqlerrm;
      if v_error_message not like '%Not your turn%' then
        raise exception 'TEST 3 FAILED: unexpected error: %', v_error_message;
      end if;
      raise notice 'TEST 3 PASSED: off-turn call rejected (%) ', v_error_message;
  end;

  ------------------------------------------------------------------
  -- TEST 4: jack rejected outright
  ------------------------------------------------------------------
  perform set_config('request.jwt.claim.sub', v_user_a::text, true);
  begin
    perform public.swap_dead_card(v_game_id, v_version_after, 'JS');
    raise exception 'TEST 4 FAILED: swap_dead_card accepted a Jack';
  exception
    when others then
      v_error_message := sqlerrm;
      if v_error_message not like '%Jacks%' then
        raise exception 'TEST 4 FAILED: unexpected error: %', v_error_message;
      end if;
      raise notice 'TEST 4 PASSED: jack rejected (%) ', v_error_message;
  end;

  ------------------------------------------------------------------
  -- Cleanup (rooms cascade-deletes games, players, moves, etc.)
  ------------------------------------------------------------------
  delete from public.rooms where id = v_room_id;

  raise notice '=== ALL TESTS PASSED ===';
exception
  when others then
    -- Make sure we never leak a test room even when an assertion fails.
    delete from public.rooms where code = 'TESTDC';
    raise;
end;
$$;
