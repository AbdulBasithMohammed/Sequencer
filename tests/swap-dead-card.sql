-- Test: swap_dead_card RPC end-to-end.
--
-- Wraps the work in a temp function so we can SELECT a step-by-step
-- report back to the caller (DO blocks can't return rows).
--
-- Run via Supabase admin API:
--
--   set -a && source .env.local && set +a && \
--     curl -s -X POST \
--       "https://api.supabase.com/v1/projects/$SUPABASE_PROJECT_REF/database/query" \
--       -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
--       -H "Content-Type: application/json" \
--       --data-binary @<(jq -Rs '{query: .}' tests/swap-dead-card.sql)
--
-- Each step returns (step, status, detail). All "PASS" or "OK" = green.
-- Any FAIL surfaces in the response. Cleanup runs even when an
-- assertion blows up.

create or replace function public._test_swap_dead_card_e2e()
returns table(step text, status text, detail text)
language plpgsql
as $$
declare
  v_user_a uuid;
  v_user_b uuid;
  v_room_id uuid;
  v_game_id uuid;
  v_board jsonb;
  v_dead_card text := '2D';
  v_r int;
  v_c int;
  v_open_positions int;
  v_started_version int := 5;

  v_hand_a_before jsonb;
  v_hand_b_before jsonb;
  v_deck_before jsonb;
  v_discard_before jsonb;
  v_board_before jsonb;
  v_sequences_before jsonb;
  v_turn_before int;
  v_moves_before bigint;

  v_call_version int;
  v_hand_a_after jsonb;
  v_hand_b_after jsonb;
  v_deck_after jsonb;
  v_discard_after jsonb;
  v_board_after jsonb;
  v_sequences_after jsonb;
  v_turn_after int;
  v_moves_after bigint;
  v_log_row record;

  v_err text;
begin
  -- ─── Setup ─────────────────────────────────────────────────────
  select id into v_user_a from public.profiles order by created_at limit 1;
  select id into v_user_b from public.profiles where id <> v_user_a
    order by created_at limit 1;
  if v_user_a is null or v_user_b is null then
    step := 'setup'; status := 'FAIL'; detail := 'need 2+ profiles'; return next;
    return;
  end if;

  insert into public.rooms (code, host_id, target_players, status, team_layout)
  values ('TESTDC', v_user_a, 2, 'in_game', 'auto')
  returning id into v_room_id;

  insert into public.room_players (room_id, user_id, seat_index, team, token_color)
  values (v_room_id, v_user_a, 0, 1, 'pink'),
         (v_room_id, v_user_b, 1, 2, 'blue');

  -- Build a board where '2D' is fully claimed → dead. Drop a couple of
  -- unrelated chips so we can verify other state stays untouched.
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
  -- A random non-dead chip somewhere far away, to verify the board is
  -- untouched by the swap.
  v_board := jsonb_set(
    v_board, array['7','7'],
    jsonb_build_object('team', 2, 'sequence_ids', '[]'::jsonb)
  );

  insert into public.games (
    room_id, host_id, status, version, deck, discard, hands, board,
    sequences, turn_seat, turn_deadline, started_at
  ) values (
    v_room_id, v_user_a, 'in_game', v_started_version,
    jsonb_build_array('5C', '6C', '7C'),
    jsonb_build_array('9H'),
    jsonb_build_object(
      v_user_a::text, jsonb_build_array(v_dead_card, 'AH', 'KH'),
      v_user_b::text, jsonb_build_array('5D', '6D', '7D')
    ),
    v_board,
    '[]'::jsonb,
    0,                       -- user_a is on turn (seat 0)
    now() + interval '60 s',
    now()
  ) returning id into v_game_id;

  step := 'setup'; status := 'OK'; detail := format(
      'room=%s game=%s user_a=%s user_b=%s',
      v_room_id, v_game_id, v_user_a, v_user_b
    ); return next;

  -- ─── Sanity: 2D is actually dead on this board ─────────────────
  select count(*) into v_open_positions
  from generate_series(0,9) r, generate_series(0,9) c
  where public.card_at(r, c) = v_dead_card
    and (v_board -> r -> c ->> 'team') is null;

  if v_open_positions <> 0 then
    delete from public.rooms where id = v_room_id;
    step := 'verify_dead'; status := 'FAIL'; detail := format('2D has %s open position(s) → not actually dead', v_open_positions); return next;
    return;
  end if;
  step := 'verify_dead'; status := 'PASS'; detail := '2D fully covered on the mock board'; return next;

  -- ─── Capture pre-state ─────────────────────────────────────────
  select hands -> v_user_a::text, hands -> v_user_b::text,
         deck, discard, board, sequences, turn_seat,
         (select count(*) from public.game_moves where game_id = v_game_id)
    into v_hand_a_before, v_hand_b_before,
         v_deck_before, v_discard_before, v_board_before, v_sequences_before,
         v_turn_before, v_moves_before
  from public.games where id = v_game_id;

  step := 'pre_state'; status := 'OK'; detail := format(
    'v=%s hand_a=%s deck=%s discard=%s turn_seat=%s moves=%s',
    v_started_version, v_hand_a_before, v_deck_before,
    v_discard_before, v_turn_before, v_moves_before
  ); return next;

  -- ─── TEST 1: dead-card swap on own turn ────────────────────────
  perform set_config('request.jwt.claim.sub', v_user_a::text, true);
  v_call_version := public.swap_dead_card(v_game_id, v_started_version, v_dead_card);

  select hands -> v_user_a::text, hands -> v_user_b::text,
         deck, discard, board, sequences, turn_seat,
         (select count(*) from public.game_moves where game_id = v_game_id)
    into v_hand_a_after, v_hand_b_after,
         v_deck_after, v_discard_after, v_board_after, v_sequences_after,
         v_turn_after, v_moves_after
  from public.games where id = v_game_id;

  -- 1a. version returned matches what's stored
  if v_call_version <> v_started_version + 1 then
    raise exception 'returned version=% expected %', v_call_version, v_started_version + 1;
  end if;
  step := '1a_version_returned'; status := 'PASS'; detail := format('RPC returned v=%s', v_call_version); return next;

  -- 1b. hand no longer contains '2D'
  if exists (
    select 1 from jsonb_array_elements_text(v_hand_a_after) as c
    where c = v_dead_card
  ) then
    raise exception 'dead card still in hand after swap: %', v_hand_a_after;
  end if;
  step := '1b_dead_gone_from_hand'; status := 'PASS'; detail := format('hand was %s, now %s', v_hand_a_before, v_hand_a_after); return next;

  -- 1c. hand size unchanged
  if jsonb_array_length(v_hand_a_after) <> jsonb_array_length(v_hand_a_before) then
    raise exception 'hand size changed: before=% after=%',
      jsonb_array_length(v_hand_a_before), jsonb_array_length(v_hand_a_after);
  end if;
  step := '1c_hand_size_same'; status := 'PASS'; detail := format('size %s → %s', jsonb_array_length(v_hand_a_before),
                            jsonb_array_length(v_hand_a_after)); return next;

  -- 1d. new card is the previous top of the deck
  if (v_hand_a_after -> (jsonb_array_length(v_hand_a_after) - 1))::text
       <> (v_deck_before -> 0)::text then
    raise exception 'drew unexpected card: got % expected (deck top) %',
      v_hand_a_after -> (jsonb_array_length(v_hand_a_after) - 1),
      v_deck_before -> 0;
  end if;
  step := '1d_drew_deck_top'; status := 'PASS'; detail := format('drew %s from deck top', v_deck_before -> 0); return next;

  -- 1e. discard pile gained '2D'
  if (v_discard_after - (jsonb_array_length(v_discard_after) - 1))
       <> v_discard_before
     or (v_discard_after ->> (jsonb_array_length(v_discard_after) - 1))
       <> v_dead_card then
    raise exception 'discard did not get the dead card appended: before=% after=%',
      v_discard_before, v_discard_after;
  end if;
  step := '1e_discard_appended'; status := 'PASS'; detail := format('discard %s → %s', v_discard_before, v_discard_after); return next;

  -- 1f. deck shrunk by 1
  if jsonb_array_length(v_deck_after) <> jsonb_array_length(v_deck_before) - 1 then
    raise exception 'deck size off: before=% after=%',
      jsonb_array_length(v_deck_before), jsonb_array_length(v_deck_after);
  end if;
  step := '1f_deck_shrunk'; status := 'PASS'; detail := format('deck %s → %s', v_deck_before, v_deck_after); return next;

  -- 1g. turn unchanged
  if v_turn_after <> v_turn_before then
    raise exception 'turn advanced: before seat=% after seat=%',
      v_turn_before, v_turn_after;
  end if;
  step := '1g_turn_unchanged'; status := 'PASS'; detail := format('turn_seat stayed at %s', v_turn_after); return next;

  -- 1h. board untouched
  if v_board_after <> v_board_before then
    raise exception 'board changed';
  end if;
  step := '1h_board_untouched'; status := 'PASS'; detail := 'board byte-identical'; return next;

  -- 1i. sequences untouched
  if v_sequences_after <> v_sequences_before then
    raise exception 'sequences changed';
  end if;
  step := '1i_sequences_untouched'; status := 'PASS'; detail := 'sequences byte-identical'; return next;

  -- 1j. other player's hand untouched
  if v_hand_b_after <> v_hand_b_before then
    raise exception 'other player hand changed';
  end if;
  step := '1j_other_hand_untouched'; status := 'PASS'; detail := 'user_b hand unchanged'; return next;

  -- 1k. game_moves got a swap_dead entry
  if v_moves_after <> v_moves_before + 1 then
    raise exception 'game_moves count off: before=% after=%',
      v_moves_before, v_moves_after;
  end if;
  select * into v_log_row from public.game_moves
    where game_id = v_game_id order by version desc limit 1;
  if v_log_row.action <> 'swap_dead'
     or v_log_row.user_id <> v_user_a
     or v_log_row.card <> v_dead_card
     or (v_log_row.payload ->> 'drew') is null then
    raise exception 'log row wrong: %', to_jsonb(v_log_row);
  end if;
  step := '1k_log_entry'; status := 'PASS'; detail := format('action=%s card=%s drew=%s',
      v_log_row.action, v_log_row.card, v_log_row.payload ->> 'drew'); return next;

  -- ─── TEST 2: non-dead rejected ─────────────────────────────────
  begin
    perform public.swap_dead_card(v_game_id, v_call_version, 'AH');
    raise exception 'TEST 2 FAILED: non-dead accepted';
  exception
    when sqlstate '22023' then
      v_err := sqlerrm;
      if v_err not like '%not dead%' then
        raise exception 'TEST 2 FAILED: wrong error: %', v_err;
      end if;
      step := '2_non_dead_rejected'; status := 'PASS'; detail := v_err; return next;
    when others then
      raise;
  end;

  -- ─── TEST 3: off-turn rejected ─────────────────────────────────
  perform set_config('request.jwt.claim.sub', v_user_b::text, true);
  begin
    perform public.swap_dead_card(v_game_id, v_call_version, '5D');
    raise exception 'TEST 3 FAILED: off-turn accepted';
  exception
    when sqlstate '42501' then
      step := '3_off_turn_rejected'; status := 'PASS'; detail := sqlerrm; return next;
    when others then
      raise;
  end;

  -- ─── TEST 4: jack rejected ─────────────────────────────────────
  perform set_config('request.jwt.claim.sub', v_user_a::text, true);
  begin
    perform public.swap_dead_card(v_game_id, v_call_version, 'JS');
    raise exception 'TEST 4 FAILED: jack accepted';
  exception
    when sqlstate '22023' then
      step := '4_jack_rejected'; status := 'PASS'; detail := sqlerrm; return next;
    when others then
      raise;
  end;

  -- ─── TEST 5: stale version rejected ────────────────────────────
  begin
    perform public.swap_dead_card(v_game_id, v_started_version /* stale */, v_dead_card);
    raise exception 'TEST 5 FAILED: stale version accepted';
  exception
    when sqlstate '40001' then
      step := '5_stale_version_rejected'; status := 'PASS'; detail := sqlerrm; return next;
    when others then
      raise;
  end;

  -- ─── Cleanup ───────────────────────────────────────────────────
  delete from public.rooms where id = v_room_id;
  step := 'cleanup'; status := 'OK'; detail := 'test room deleted (cascade)'; return next;
exception
  when others then
    -- Always pull the test room even if an assertion exploded.
    delete from public.rooms where code = 'TESTDC';
    step := 'error'; status := 'FAIL'; detail := sqlerrm; return next;
end;
$$;

select * from public._test_swap_dead_card_e2e();
drop function public._test_swap_dead_card_e2e();
