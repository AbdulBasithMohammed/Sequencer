-- Test: when deck empties, discard reshuffles into deck.
--
-- Setup a game with deck=['only-card'] and discard=[bunch of cards].
-- play_move that drains the deck. Next play_move should refill from
-- the discard pile. Verify post-state.
--
-- Run via Supabase admin API (see comment at top of swap-dead-card.sql
-- for the curl one-liner).

create or replace function public._test_deck_refill_e2e()
returns table(step text, status text, detail text)
language plpgsql
as $$
declare
  v_user_a uuid;
  v_user_b uuid;
  v_room_id uuid;
  v_game_id uuid;
  v_board jsonb;
  v_r int;
  v_c int;
  v_card_first text := '2D';   -- first card we'll place
  v_card_second text := '3D';  -- second card we'll place (after refill)
  v_first_r int;
  v_first_c int;
  v_second_r int;
  v_second_c int;
  v_started_version int := 5;
  v_call_v1 int;
  v_call_v2 int;
  v_deck_after_first jsonb;
  v_discard_after_first jsonb;
  v_deck_after_second jsonb;
  v_discard_after_second jsonb;
  v_hand_a_after jsonb;
begin
  -- Two profiles
  select id into v_user_a from public.profiles order by created_at limit 1;
  select id into v_user_b from public.profiles where id <> v_user_a
    order by created_at limit 1;
  if v_user_a is null or v_user_b is null then
    step := 'setup'; status := 'FAIL'; detail := 'need 2+ profiles';
    return next;
    return;
  end if;

  insert into public.rooms (code, host_id, target_players, status, team_layout)
  values ('TESTRF', v_user_a, 2, 'in_game', 'auto')
  returning id into v_room_id;

  insert into public.room_players (room_id, user_id, seat_index, team, token_color)
  values (v_room_id, v_user_a, 0, 1, 'pink'),
         (v_room_id, v_user_b, 1, 2, 'blue');

  -- Empty board; we'll place 2D and 3D one after another from user_a.
  v_board := public.empty_board();

  -- Find a valid (row, col) for v_card_first and v_card_second (both empty).
  select r, c into v_first_r, v_first_c
  from generate_series(0,9) r, generate_series(0,9) c
  where public.card_at(r, c) = v_card_first
  limit 1;

  select r, c into v_second_r, v_second_c
  from generate_series(0,9) r, generate_series(0,9) c
  where public.card_at(r, c) = v_card_second
  limit 1;

  -- Deck contains ONE card (so the first play drains it).
  -- Discard already has a handful of cards (these should refill the
  -- deck on the second play).
  insert into public.games (
    room_id, host_id, status, version, deck, discard, hands, board,
    sequences, turn_seat, turn_deadline, started_at
  ) values (
    v_room_id, v_user_a, 'in_game', v_started_version,
    jsonb_build_array('AC'),
    jsonb_build_array('5C', '6C', '7C', '8C'),
    jsonb_build_object(
      v_user_a::text, jsonb_build_array(v_card_first, v_card_second, 'KH'),
      v_user_b::text, jsonb_build_array('AS', 'KS', 'QS')
    ),
    v_board,
    '[]'::jsonb,
    0,
    now() + interval '60 s',
    now()
  ) returning id into v_game_id;

  step := 'setup';
  status := 'OK';
  detail := format(
    'game=%s deck=["AC"] (1) discard=["5C","6C","7C","8C"] (4) hand_a=%s',
    v_game_id,
    (select hands -> v_user_a::text from public.games where id = v_game_id)
  );
  return next;

  -- ─── First play: drains the deck ─────────────────────────────────
  perform set_config('request.jwt.claim.sub', v_user_a::text, true);

  v_call_v1 := public.play_move(
    v_game_id, v_started_version, v_card_first, v_first_r, v_first_c
  );

  select deck, discard into v_deck_after_first, v_discard_after_first
  from public.games where id = v_game_id;

  -- After the first play:
  -- - discard gained 2D (played card) → before: 4, after: 5
  -- - deck had 1 card (AC), top drawn → after: 0
  if jsonb_array_length(v_deck_after_first) <> 0 then
    raise exception 'after first play, deck should be empty, got %', v_deck_after_first;
  end if;
  if jsonb_array_length(v_discard_after_first) <> 5 then
    raise exception 'discard should have 5 cards after first play, got %', v_discard_after_first;
  end if;
  step := '1_first_play_drains_deck';
  status := 'PASS';
  detail := format('deck %s → [], discard ["5C","6C","7C","8C"] → %s',
    jsonb_build_array('AC'), v_discard_after_first);
  return next;

  -- ─── Pass turn back to user_a (test won't bother fully playing user_b) ───
  -- Hack: advance turn_seat manually so user_a can play again.
  -- This bypasses the real turn cycle but exercises the refill code path
  -- without making us play through user_b's turn (which would itself
  -- consume / refill the deck).
  update public.games set turn_seat = 0 where id = v_game_id;

  -- ─── Second play: deck is empty going in; refill should kick in ──
  v_call_v2 := public.play_move(
    v_game_id, v_call_v1, v_card_second, v_second_r, v_second_c
  );

  select deck, discard, hands -> v_user_a::text
    into v_deck_after_second, v_discard_after_second, v_hand_a_after
  from public.games where id = v_game_id;

  -- Refill mechanics:
  -- Before refill (mid-RPC): deck=[], discard=[5C,6C,7C,8C,2D,3D] (6)
  --   → reshuffle: deck=[6 cards shuffled], discard=[]
  --   → draw top: deck=[5 cards], discard=[]
  -- Expected post-state:
  --   deck size = 5, discard size = 0
  --   hand_a size still 3
  --   no '3D' in hand (just played) but a fresh draw appended
  if jsonb_array_length(v_deck_after_second) <> 5 then
    raise exception 'expected deck size 5 after refill, got %', v_deck_after_second;
  end if;
  if jsonb_array_length(v_discard_after_second) <> 0 then
    raise exception 'expected discard empty after refill, got %', v_discard_after_second;
  end if;
  if jsonb_array_length(v_hand_a_after) <> 3 then
    raise exception 'expected hand size 3, got %', v_hand_a_after;
  end if;
  if exists (
    select 1 from jsonb_array_elements_text(v_hand_a_after) c
    where c = v_card_second
  ) then
    raise exception '3D still in hand after play';
  end if;

  step := '2_refill_on_empty_deck';
  status := 'PASS';
  detail := format('post-refill deck=%s discard=%s hand_a=%s',
    v_deck_after_second, v_discard_after_second, v_hand_a_after);
  return next;

  -- Reshuffled deck should consist of the 6 cards previously in
  -- discard (5C, 6C, 7C, 8C, 2D, 3D), minus whichever single one was
  -- drawn to fill the hand. So deck_after_second ∪ {drawn card} =
  -- the set {5C, 6C, 7C, 8C, 2D, 3D}.
  declare
    v_expected_set jsonb := jsonb_build_array('5C','6C','7C','8C','2D','3D');
    v_drawn text := v_hand_a_after ->> 2;  -- newest card is appended last
    v_combined jsonb;
  begin
    v_combined := v_deck_after_second || jsonb_build_array(v_drawn);
    -- Check both contain the same multiset
    if (
      select count(*) from jsonb_array_elements_text(v_combined) c
    ) <> (
      select count(*) from jsonb_array_elements_text(v_expected_set) c
    ) or exists (
      select c from jsonb_array_elements_text(v_combined) c
      except
      select c from jsonb_array_elements_text(v_expected_set) c
    ) or exists (
      select c from jsonb_array_elements_text(v_expected_set) c
      except
      select c from jsonb_array_elements_text(v_combined) c
    ) then
      raise exception 'reshuffled deck contents mismatch: combined=% expected=%',
        v_combined, v_expected_set;
    end if;
    step := '3_refill_contents_match_discard';
    status := 'PASS';
    detail := format('deck+drew (%s) = old-discard+just-played (%s)',
      v_combined, v_expected_set);
    return next;
  end;

  -- ─── deck_count column matches jsonb length ─────────────────────
  declare
    v_dc int;
  begin
    select deck_count into v_dc from public.games where id = v_game_id;
    if v_dc <> jsonb_array_length(v_deck_after_second) then
      raise exception 'deck_count column out of sync: column=% jsonb=%',
        v_dc, jsonb_array_length(v_deck_after_second);
    end if;
    step := '4_deck_count_column_in_sync';
    status := 'PASS';
    detail := format('deck_count column = %s', v_dc);
    return next;
  end;

  -- ─── Cleanup ─────────────────────────────────────────────────────
  delete from public.rooms where id = v_room_id;
  step := 'cleanup';
  status := 'OK';
  detail := 'test room deleted (cascade)';
  return next;
exception
  when others then
    delete from public.rooms where code = 'TESTRF';
    step := 'error';
    status := 'FAIL';
    detail := sqlerrm;
    return next;
end;
$$;

select * from public._test_deck_refill_e2e();
drop function public._test_deck_refill_e2e();
