-- Stable sequences: a declared sequence never moves.
--
-- Bug: rebalance_board_sequences() recomputed every sequence from scratch
-- on each placement, re-anchoring 5-windows to the start of each run. So
-- extending a completed sequence by one chip visibly SHIFTED the locked
-- window — and with it which chips a one-eyed jack may remove. Per the
-- rulebook a declared sequence is immutable.
--
-- Fix: assign_board_sequences(board, prev_sequences) keeps every previous
-- sequence verbatim (same id, same cells) and only ADDS new sequences:
-- candidate 5-windows (same-team chips, corners wild) are accepted when
-- they overlap every already-declared same-team sequence by at most one
-- chip — the rulebook's shared-chip rule, now enforced against declared
-- history instead of a fresh re-partition. The legal 9-chip double
-- ([0..4] + [4..8] sharing one chip) still forms; an extended 6-chip line
-- changes nothing.
--
-- The four callers below are regenerated from their live definitions with
-- only the call site changed (rebalance_board_sequences(v_board) ->
-- assign_board_sequences(v_board, v_sequences)).

create or replace function public.assign_board_sequences(
  p_board jsonb,
  p_prev_sequences jsonb
)
returns table(new_board jsonb, new_sequences jsonb)
language plpgsql
immutable
set search_path = ''
as $fn$
declare
  v_seqs jsonb := coalesce(p_prev_sequences, '[]'::jsonb);
  v_next_id int := 1;
  v_seq jsonb;
  v_board jsonb := p_board;
  v_dr int; v_dc int; v_d int;
  v_r int; v_c int; v_k int;
  v_rr int; v_cc int;
  v_team int;
  v_cell_team int;
  v_valid boolean;
  v_cells jsonb;
  v_overlap int;
  v_reject boolean;
  v_cell jsonb;
begin
  -- Next id continues after the highest already declared.
  for v_seq in select * from jsonb_array_elements(v_seqs) loop
    if (v_seq ->> 'id')::int >= v_next_id then
      v_next_id := (v_seq ->> 'id')::int + 1;
    end if;
  end loop;

  -- Enumerate every 5-window, top-left first (stable, deterministic).
  for v_r in 0..9 loop
    for v_c in 0..9 loop
      for v_d in 1..4 loop
        v_dr := case v_d when 1 then 0 else 1 end;
        v_dc := case v_d when 1 then 1 when 2 then 0 when 3 then 1 else -1 end;
        v_rr := v_r + 4 * v_dr;
        v_cc := v_c + 4 * v_dc;
        continue when v_rr > 9 or v_cc > 9 or v_cc < 0;

        -- Window is valid when all 5 cells are corners or one team's chips.
        v_team := null; v_valid := true; v_cells := '[]'::jsonb;
        for v_k in 0..4 loop
          v_rr := v_r + v_k * v_dr;
          v_cc := v_c + v_k * v_dc;
          if public.card_at(v_rr, v_cc) is null then
            v_cells := v_cells || jsonb_build_object('row', v_rr, 'col', v_cc);
          else
            v_cell_team := (v_board -> v_rr -> v_cc ->> 'team')::int;
            if v_cell_team is null
               or (v_team is not null and v_cell_team <> v_team) then
              v_valid := false;
              exit;
            end if;
            v_team := v_cell_team;
            v_cells := v_cells || jsonb_build_object('row', v_rr, 'col', v_cc);
          end if;
        end loop;
        continue when not v_valid or v_team is null;

        -- Shared-chip rule vs every declared same-team sequence
        -- (previous AND ones accepted earlier in this pass).
        v_reject := false;
        for v_seq in select * from jsonb_array_elements(v_seqs) loop
          if (v_seq ->> 'team')::int = v_team then
            select count(*) into v_overlap
            from jsonb_array_elements(v_cells) a
            join jsonb_array_elements(v_seq -> 'cells') b
              on (a ->> 'row') = (b ->> 'row')
             and (a ->> 'col') = (b ->> 'col');
            if v_overlap > 1 then
              v_reject := true;
              exit;
            end if;
          end if;
        end loop;
        continue when v_reject;

        v_seqs := v_seqs || jsonb_build_object(
          'id', v_next_id, 'team', v_team, 'cells', v_cells);
        v_next_id := v_next_id + 1;
      end loop;
    end loop;
  end loop;

  -- Rewrite chip-level sequence_ids from the final list.
  for v_r in 0..9 loop
    for v_c in 0..9 loop
      if public.card_at(v_r, v_c) is not null
         and (v_board -> v_r -> v_c ->> 'team') is not null then
        v_board := jsonb_set(
          v_board, array[v_r::text, v_c::text, 'sequence_ids'], '[]'::jsonb);
      end if;
    end loop;
  end loop;
  for v_seq in select * from jsonb_array_elements(v_seqs) loop
    for v_cell in select * from jsonb_array_elements(v_seq -> 'cells') loop
      v_r := (v_cell ->> 'row')::int;
      v_c := (v_cell ->> 'col')::int;
      if public.card_at(v_r, v_c) is not null then
        v_board := jsonb_set(
          v_board, array[v_r::text, v_c::text, 'sequence_ids'],
          (v_board -> v_r -> v_c -> 'sequence_ids') || (v_seq -> 'id'));
      end if;
    end loop;
  end loop;

  new_board := v_board;
  new_sequences := v_seqs;
  return next;
end;
$fn$;


-- ── play_move: regenerated from live definition, call site swapped ──
CREATE OR REPLACE FUNCTION public.play_move(p_game_id uuid, p_client_version integer, p_card text, p_row integer, p_col integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_caller uuid := auth.uid();
  v_room_id uuid;
  v_status text;
  v_version int;
  v_turn_seat int;
  v_turn_seconds int;
  v_deck jsonb;
  v_discard jsonb;
  v_hands jsonb;
  v_board jsonb;
  v_sequences jsonb;
  v_team_cursor jsonb;
  v_caller_seat int;
  v_caller_team int;
  v_caller_hand jsonb;
  v_found_idx int;
  v_new_hand jsonb;
  v_top_card text;
  v_board_card text;
  v_cell jsonb;
  v_next_seat int;
  v_new_cursor jsonb;
  v_new_version int;
  v_prev_seq_count int;
  v_team_seq_count int;
  v_required int;
  v_new_status text := 'in_game';
  v_winner_team int := null;
  v_rebalanced record;
  v_advance record;
begin
  if v_caller is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  if p_row < 0 or p_row > 9 or p_col < 0 or p_col > 9 then
    raise exception 'Invalid cell %, %', p_row, p_col using errcode = '22023';
  end if;

  if p_card is null or length(p_card) <> 2 then
    raise exception 'Invalid card %', p_card using errcode = '22023';
  end if;

  if substring(p_card from 1 for 1) = 'J' then
    raise exception 'Jacks are handled by a separate RPC' using errcode = '0A000';
  end if;

  select room_id, status, version, turn_seat, deck, discard, hands, board, sequences, team_cursor
    into v_room_id, v_status, v_version, v_turn_seat, v_deck, v_discard, v_hands, v_board, v_sequences, v_team_cursor
  from public.games
  where id = p_game_id
  for update;

  if v_room_id is null then
    raise exception 'Game not found' using errcode = 'P0002';
  end if;
  if v_status <> 'in_game' then
    raise exception 'Game is not in progress' using errcode = '22023';
  end if;
  if v_version <> p_client_version then
    raise exception 'Stale client version (server=%, client=%)', v_version, p_client_version
      using errcode = '40001';
  end if;

  select turn_seconds into v_turn_seconds
  from public.rooms where id = v_room_id;

  select seat_index, team
    into v_caller_seat, v_caller_team
  from public.room_players
  where room_id = v_room_id and user_id = v_caller;

  if v_caller_seat is null then
    raise exception 'Not a player in this game' using errcode = '42501';
  end if;
  if v_caller_seat <> v_turn_seat then
    raise exception 'Not your turn' using errcode = '42501';
  end if;
  if v_caller_team is null then
    raise exception 'Caller has no team assigned' using errcode = '22023';
  end if;

  v_caller_hand := coalesce(v_hands -> v_caller::text, '[]'::jsonb);

  select (ord - 1)::int into v_found_idx
  from jsonb_array_elements_text(v_caller_hand) with ordinality as t(card, ord)
  where card = p_card
  order by ord
  limit 1;

  if v_found_idx is null then
    raise exception 'Card not in hand' using errcode = '22023';
  end if;

  v_board_card := public.card_at(p_row, p_col);
  if v_board_card is null then
    raise exception 'Corner wilds require a jack RPC' using errcode = '22023';
  end if;
  if v_board_card <> p_card then
    raise exception 'Card does not match cell (card=%, cell=%)', p_card, v_board_card
      using errcode = '22023';
  end if;

  v_cell := v_board -> p_row -> p_col;
  if (v_cell ->> 'team') is not null then
    raise exception 'Cell already occupied' using errcode = '22023';
  end if;

  v_new_hand := v_caller_hand - v_found_idx;
  v_discard := v_discard || to_jsonb(p_card);

  if jsonb_array_length(v_deck) = 0 and jsonb_array_length(v_discard) > 0 then
    select coalesce(jsonb_agg(card order by random()), '[]'::jsonb) into v_deck
    from jsonb_array_elements_text(v_discard) as t(card);
    v_discard := '[]'::jsonb;
  end if;

  if jsonb_array_length(v_deck) > 0 then
    v_top_card := v_deck ->> 0;
    v_new_hand := v_new_hand || to_jsonb(v_top_card);
    v_deck := v_deck - 0;
  end if;

  v_hands := jsonb_set(v_hands, array[v_caller::text], v_new_hand);

  v_board := jsonb_set(
    v_board,
    array[p_row::text, p_col::text],
    jsonb_build_object('team', v_caller_team, 'sequence_ids', '[]'::jsonb)
  );

  v_prev_seq_count := jsonb_array_length(v_sequences);
  select rb.new_board, rb.new_sequences
    into v_rebalanced
  from public.assign_board_sequences(v_board, v_sequences) rb;
  v_board := v_rebalanced.new_board;
  v_sequences := v_rebalanced.new_sequences;

  v_required := public.win_threshold(v_room_id);
  select count(*) into v_team_seq_count
  from jsonb_array_elements(v_sequences) as s
  where (s ->> 'team')::int = v_caller_team;

  if v_team_seq_count >= v_required then
    v_new_status := 'finished';
    v_winner_team := v_caller_team;
  end if;

  if v_new_status = 'finished' then
    v_next_seat := v_turn_seat;
    v_new_cursor := v_team_cursor;
  else
    select nt.next_seat, nt.new_cursor
      into v_advance
    from public.next_turn_seat(v_room_id, v_turn_seat, v_team_cursor) nt;
    v_next_seat := v_advance.next_seat;
    v_new_cursor := v_advance.new_cursor;
  end if;

  v_new_version := v_version + 1;

  update public.games set
    version = v_new_version,
    status = v_new_status,
    winner_team = v_winner_team,
    deck = v_deck,
    discard = v_discard,
    hands = v_hands,
    board = v_board,
    sequences = v_sequences,
    turn_seat = v_next_seat,
    team_cursor = v_new_cursor,
    turn_deadline = case when v_new_status = 'in_game'
      then now() + (v_turn_seconds || ' seconds')::interval else null end,
    finished_at = case when v_new_status = 'finished' then now() else null end
  where id = p_game_id;

  insert into public.game_moves (
    game_id, version, user_id, action, card, tile_row, tile_col, payload
  ) values (
    p_game_id,
    v_new_version,
    v_caller,
    'place',
    p_card,
    p_row,
    p_col,
    jsonb_build_object(
      'team', v_caller_team,
      'drew', v_top_card,
      'new_sequences', greatest(0, jsonb_array_length(v_sequences) - v_prev_seq_count),
      'winner_team', v_winner_team
    )
  );

  return v_new_version;
end;
$function$
;

-- ── play_wild: regenerated from live definition, call site swapped ──
CREATE OR REPLACE FUNCTION public.play_wild(p_game_id uuid, p_client_version integer, p_card text, p_row integer, p_col integer)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_caller uuid := auth.uid();
  v_room_id uuid;
  v_status text;
  v_version int;
  v_turn_seat int;
  v_turn_seconds int;
  v_deck jsonb;
  v_discard jsonb;
  v_hands jsonb;
  v_board jsonb;
  v_sequences jsonb;
  v_team_cursor jsonb;
  v_caller_seat int;
  v_caller_team int;
  v_caller_hand jsonb;
  v_found_idx int;
  v_new_hand jsonb;
  v_top_card text;
  v_board_card text;
  v_cell jsonb;
  v_next_seat int;
  v_new_cursor jsonb;
  v_new_version int;
  v_prev_seq_count int;
  v_team_seq_count int;
  v_required int;
  v_new_status text := 'in_game';
  v_winner_team int := null;
  v_rebalanced record;
  v_advance record;
begin
  if v_caller is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  if p_row < 0 or p_row > 9 or p_col < 0 or p_col > 9 then
    raise exception 'Invalid cell %, %', p_row, p_col using errcode = '22023';
  end if;

  if p_card is null or (p_card <> 'JD' and p_card <> 'JC') then
    raise exception 'play_wild only accepts two-eyed jacks (JD, JC); got %', p_card
      using errcode = '22023';
  end if;

  select room_id, status, version, turn_seat, deck, discard, hands, board, sequences, team_cursor
    into v_room_id, v_status, v_version, v_turn_seat, v_deck, v_discard, v_hands, v_board, v_sequences, v_team_cursor
  from public.games
  where id = p_game_id
  for update;

  if v_room_id is null then
    raise exception 'Game not found' using errcode = 'P0002';
  end if;
  if v_status <> 'in_game' then
    raise exception 'Game is not in progress' using errcode = '22023';
  end if;
  if v_version <> p_client_version then
    raise exception 'Stale client version (server=%, client=%)', v_version, p_client_version
      using errcode = '40001';
  end if;

  select turn_seconds into v_turn_seconds
  from public.rooms where id = v_room_id;

  select seat_index, team
    into v_caller_seat, v_caller_team
  from public.room_players
  where room_id = v_room_id and user_id = v_caller;

  if v_caller_seat is null then
    raise exception 'Not a player in this game' using errcode = '42501';
  end if;
  if v_caller_seat <> v_turn_seat then
    raise exception 'Not your turn' using errcode = '42501';
  end if;
  if v_caller_team is null then
    raise exception 'Caller has no team assigned' using errcode = '22023';
  end if;

  v_caller_hand := coalesce(v_hands -> v_caller::text, '[]'::jsonb);

  select (ord - 1)::int into v_found_idx
  from jsonb_array_elements_text(v_caller_hand) with ordinality as t(card, ord)
  where card = p_card
  order by ord
  limit 1;

  if v_found_idx is null then
    raise exception 'Card not in hand' using errcode = '22023';
  end if;

  v_board_card := public.card_at(p_row, p_col);
  if v_board_card is null then
    raise exception 'Cannot place on a corner wild' using errcode = '22023';
  end if;

  v_cell := v_board -> p_row -> p_col;
  if (v_cell ->> 'team') is not null then
    raise exception 'Cell already occupied' using errcode = '22023';
  end if;

  v_new_hand := v_caller_hand - v_found_idx;
  v_discard := v_discard || to_jsonb(p_card);

  if jsonb_array_length(v_deck) = 0 and jsonb_array_length(v_discard) > 0 then
    select coalesce(jsonb_agg(card order by random()), '[]'::jsonb) into v_deck
    from jsonb_array_elements_text(v_discard) as t(card);
    v_discard := '[]'::jsonb;
  end if;

  if jsonb_array_length(v_deck) > 0 then
    v_top_card := v_deck ->> 0;
    v_new_hand := v_new_hand || to_jsonb(v_top_card);
    v_deck := v_deck - 0;
  end if;

  v_hands := jsonb_set(v_hands, array[v_caller::text], v_new_hand);

  v_board := jsonb_set(
    v_board,
    array[p_row::text, p_col::text],
    jsonb_build_object('team', v_caller_team, 'sequence_ids', '[]'::jsonb)
  );

  v_prev_seq_count := jsonb_array_length(v_sequences);
  select rb.new_board, rb.new_sequences
    into v_rebalanced
  from public.assign_board_sequences(v_board, v_sequences) rb;
  v_board := v_rebalanced.new_board;
  v_sequences := v_rebalanced.new_sequences;

  v_required := public.win_threshold(v_room_id);
  select count(*) into v_team_seq_count
  from jsonb_array_elements(v_sequences) as s
  where (s ->> 'team')::int = v_caller_team;

  if v_team_seq_count >= v_required then
    v_new_status := 'finished';
    v_winner_team := v_caller_team;
  end if;

  if v_new_status = 'finished' then
    v_next_seat := v_turn_seat;
    v_new_cursor := v_team_cursor;
  else
    select nt.next_seat, nt.new_cursor
      into v_advance
    from public.next_turn_seat(v_room_id, v_turn_seat, v_team_cursor) nt;
    v_next_seat := v_advance.next_seat;
    v_new_cursor := v_advance.new_cursor;
  end if;

  v_new_version := v_version + 1;

  update public.games set
    version = v_new_version,
    status = v_new_status,
    winner_team = v_winner_team,
    deck = v_deck,
    discard = v_discard,
    hands = v_hands,
    board = v_board,
    sequences = v_sequences,
    turn_seat = v_next_seat,
    team_cursor = v_new_cursor,
    turn_deadline = case when v_new_status = 'in_game'
      then now() + (v_turn_seconds || ' seconds')::interval else null end,
    finished_at = case when v_new_status = 'finished' then now() else null end
  where id = p_game_id;

  insert into public.game_moves (
    game_id, version, user_id, action, card, tile_row, tile_col, payload
  ) values (
    p_game_id,
    v_new_version,
    v_caller,
    'place',
    p_card,
    p_row,
    p_col,
    jsonb_build_object(
      'team', v_caller_team,
      'drew', v_top_card,
      'via', 'wild_jack',
      'new_sequences', greatest(0, jsonb_array_length(v_sequences) - v_prev_seq_count),
      'winner_team', v_winner_team
    )
  );

  return v_new_version;
end;
$function$
;

-- ── bot_take_turn: regenerated from live definition, call site swapped ──
CREATE OR REPLACE FUNCTION public.bot_take_turn(p_game_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_room_id uuid;
  v_status text;
  v_version int;
  v_turn_seat int;
  v_turn_seconds int;
  v_deck jsonb;
  v_discard jsonb;
  v_hands jsonb;
  v_board jsonb;
  v_sequences jsonb;
  v_team_cursor jsonb;
  v_bot_id uuid;
  v_bot_team int;
  v_is_bot boolean;
  v_difficulty text;
  v_bot_hand jsonb;
  v_dead_card text;
  v_card text;
  v_found_idx int;
  v_new_hand jsonb;
  v_top_card text;
  v_next_seat int;
  v_new_cursor jsonb;
  v_new_version int;
  v_prev_seq_count int;
  v_team_seq_count int;
  v_required int;
  v_new_status text := 'in_game';
  v_winner_team int := null;
  v_rebalanced record;
  v_advance record;
  v_topk_n int;
  v_cands jsonb;
  v_pick jsonb;
  v_cand jsonb;
  v_i int;
  v_kind text;
  v_pick_r int;
  v_pick_c int;
  v_board_after jsonb;
  v_opp_reply numeric;
  v_adj numeric;
  v_best_adj numeric;
  c_jack_worth     constant numeric := 2000;
  c_remove_worth   constant numeric := 4000;
  c_jack_hold      constant numeric := 1000000000;
  c_noise          constant numeric := 300;
  c_reply          constant numeric := 0.5;
  c_complete_guard constant numeric := 50000;  -- never penalise a completion in the 1-ply
begin
  select g.room_id, g.status, g.version, g.turn_seat, g.deck, g.discard,
         g.hands, g.board, g.sequences, g.team_cursor
    into v_room_id, v_status, v_version, v_turn_seat, v_deck, v_discard,
         v_hands, v_board, v_sequences, v_team_cursor
  from public.games g
  where g.id = p_game_id
  for update;

  if v_room_id is null or v_status <> 'in_game' then
    return -1;
  end if;

  select turn_seconds into v_turn_seconds from public.rooms where id = v_room_id;

  select rp.user_id, rp.team, pr.is_bot, coalesce(rp.bot_difficulty, 'medium')
    into v_bot_id, v_bot_team, v_is_bot, v_difficulty
  from public.room_players rp
  join public.profiles pr on pr.id = rp.user_id
  where rp.room_id = v_room_id and rp.seat_index = v_turn_seat;

  if v_bot_id is null or coalesce(v_is_bot, false) = false or v_bot_team is null then
    return -1;
  end if;

  v_bot_hand := coalesce(v_hands -> v_bot_id::text, '[]'::jsonb);

  ----------------------------------------------------------------
  -- Free dead-card swap (all tiers).
  ----------------------------------------------------------------
  select h.card into v_dead_card
  from jsonb_array_elements_text(v_bot_hand) as h(card)
  where substring(h.card from 1 for 1) <> 'J'
    and not exists (
      select 1 from generate_series(0, 9) as r, generate_series(0, 9) as c
      where public.card_at(r, c) = h.card
        and ((v_board -> r -> c) ->> 'team') is null
    )
  order by random()
  limit 1;

  if v_dead_card is not null then
    select (ord - 1)::int into v_found_idx
    from jsonb_array_elements_text(v_bot_hand) with ordinality as t(card, ord)
    where card = v_dead_card
    order by ord
    limit 1;

    v_new_hand := v_bot_hand - v_found_idx;
    v_discard := v_discard || to_jsonb(v_dead_card);
    if jsonb_array_length(v_deck) = 0 and jsonb_array_length(v_discard) > 0 then
      select coalesce(jsonb_agg(card order by random()), '[]'::jsonb) into v_deck
      from jsonb_array_elements_text(v_discard) as t(card);
      v_discard := '[]'::jsonb;
    end if;
    if jsonb_array_length(v_deck) > 0 then
      v_top_card := v_deck ->> 0;
      v_new_hand := v_new_hand || to_jsonb(v_top_card);
      v_deck := v_deck - 0;
    end if;
    v_hands := jsonb_set(v_hands, array[v_bot_id::text], v_new_hand);

    v_new_version := v_version + 1;
    update public.games set
      version = v_new_version, deck = v_deck, discard = v_discard, hands = v_hands
    where id = p_game_id;

    insert into public.game_moves (game_id, version, user_id, action, card, payload)
    values (p_game_id, v_new_version, v_bot_id, 'swap_dead', v_dead_card,
      jsonb_build_object('team', v_bot_team, 'drew', v_top_card, 'via', 'bot'));

    v_version := v_new_version;
    v_bot_hand := v_new_hand;
  end if;

  ----------------------------------------------------------------
  -- Candidate scoring. rookie: offense + noise (no defense/discipline).
  -- medium: offense + four-block + discipline. ace: + three-block.
  ----------------------------------------------------------------
  v_topk_n := case when v_difficulty = 'ace' then 5 else 1 end;

  select coalesce(jsonb_agg(c2 order by (c2 ->> 'score')::numeric desc), '[]'::jsonb)
    into v_cands
  from (
    select jsonb_build_object('kind', kind, 'card', card, 'r', r, 'c', c, 'score', score) as c2
    from (
      -- place
      select 'place'::text as kind, h.card as card, r, c,
        case v_difficulty
          when 'rookie' then public.bot_score_placement(v_board, v_bot_team, r, c) + random() * c_noise
          when 'ace' then public.bot_score_placement(v_board, v_bot_team, r, c)
                          + public.bot_opp_four_block(v_board, v_bot_team, r, c)
                          + public.bot_opp_three_block(v_board, v_bot_team, r, c)
          else public.bot_score_placement(v_board, v_bot_team, r, c)
               + public.bot_opp_four_block(v_board, v_bot_team, r, c)
        end as score
      from jsonb_array_elements_text(v_bot_hand) as h(card)
      cross join generate_series(0, 9) as r
      cross join generate_series(0, 9) as c
      where substring(h.card from 1 for 1) <> 'J'
        and public.card_at(r, c) = h.card
        and ((v_board -> r -> c) ->> 'team') is null

      union all
      -- wild (two-eyed jack), with hoard discipline
      select 'wild', h.card, r, c,
        case v_difficulty
          when 'rookie' then public.bot_score_placement(v_board, v_bot_team, r, c) + random() * c_noise
          else case
                 when public.bot_score_placement(v_board, v_bot_team, r, c)
                      + public.bot_opp_four_block(v_board, v_bot_team, r, c)
                      + case when v_difficulty = 'ace'
                             then public.bot_opp_three_block(v_board, v_bot_team, r, c) else 0 end
                      >= c_jack_worth
                 then public.bot_score_placement(v_board, v_bot_team, r, c)
                      + public.bot_opp_four_block(v_board, v_bot_team, r, c)
                      + case when v_difficulty = 'ace'
                             then public.bot_opp_three_block(v_board, v_bot_team, r, c) else 0 end
                 else public.bot_score_placement(v_board, v_bot_team, r, c)
                      + public.bot_opp_four_block(v_board, v_bot_team, r, c)
                      + case when v_difficulty = 'ace'
                             then public.bot_opp_three_block(v_board, v_bot_team, r, c) else 0 end
                      - c_jack_hold
               end
        end
      from jsonb_array_elements_text(v_bot_hand) as h(card)
      cross join generate_series(0, 9) as r
      cross join generate_series(0, 9) as c
      where h.card in ('JD', 'JC')
        and public.card_at(r, c) is not null
        and ((v_board -> r -> c) ->> 'team') is null

      union all
      -- remove (one-eyed jack), with discipline
      select 'remove', h.card, r, c,
        case v_difficulty
          when 'rookie' then public.bot_removal_value(v_board, v_bot_team, r, c) + random() * c_noise
          else case when public.bot_removal_value(v_board, v_bot_team, r, c) >= c_remove_worth
                    then public.bot_removal_value(v_board, v_bot_team, r, c)
                    else public.bot_removal_value(v_board, v_bot_team, r, c) - c_jack_hold
               end
        end
      from jsonb_array_elements_text(v_bot_hand) as h(card)
      cross join generate_series(0, 9) as r
      cross join generate_series(0, 9) as c
      where h.card in ('JS', 'JH')
        and public.card_at(r, c) is not null
        and ((v_board -> r -> c) ->> 'team') is not null
        and ((v_board -> r -> c) ->> 'team')::int <> v_bot_team
        and jsonb_array_length(
              coalesce((v_board -> r -> c) -> 'sequence_ids', '[]'::jsonb)
            ) = 0
    ) u
    order by score desc, random()
    limit v_topk_n
  ) z;

  if jsonb_array_length(v_cands) > 0 then
    if v_difficulty <> 'ace' then
      v_pick := v_cands -> 0;
    else
      v_best_adj := null;
      for v_i in 0 .. jsonb_array_length(v_cands) - 1 loop
        v_cand := v_cands -> v_i;
        v_kind := v_cand ->> 'kind';
        v_pick_r := (v_cand ->> 'r')::int;
        v_pick_c := (v_cand ->> 'c')::int;

        if v_kind = 'remove' then
          v_board_after := jsonb_set(v_board, array[v_pick_r::text, v_pick_c::text],
            jsonb_build_object('team', null, 'sequence_ids', jsonb_build_array()));
        else
          v_board_after := jsonb_set(v_board, array[v_pick_r::text, v_pick_c::text],
            jsonb_build_object('team', v_bot_team, 'sequence_ids', jsonb_build_array()));
        end if;

        select coalesce(max(public.bot_score_placement(v_board_after, opp.team, gr, gc)), 0)
          into v_opp_reply
        from (
          select distinct team from public.room_players
          where room_id = v_room_id and team is not null and team <> v_bot_team
        ) opp
        cross join generate_series(0, 9) as gr
        cross join generate_series(0, 9) as gc
        where public.card_at(gr, gc) is not null
          and ((v_board_after -> gr -> gc) ->> 'team') is null;

        -- completion guard: a winning/completing move is never down-weighted
        v_adj := (v_cand ->> 'score')::numeric
                 - case when (v_cand ->> 'score')::numeric >= c_complete_guard
                        then 0 else c_reply * v_opp_reply end;
        if v_best_adj is null or v_adj > v_best_adj then
          v_best_adj := v_adj;
          v_pick := v_cand;
        end if;
      end loop;
    end if;

    v_kind := v_pick ->> 'kind';
    v_card := v_pick ->> 'card';
    v_pick_r := (v_pick ->> 'r')::int;
    v_pick_c := (v_pick ->> 'c')::int;

    select (ord - 1)::int into v_found_idx
    from jsonb_array_elements_text(v_bot_hand) with ordinality as t(card, ord)
    where card = v_card
    order by ord
    limit 1;

    v_new_hand := v_bot_hand - v_found_idx;
    v_discard := v_discard || to_jsonb(v_card);

    if jsonb_array_length(v_deck) = 0 and jsonb_array_length(v_discard) > 0 then
      select coalesce(jsonb_agg(card order by random()), '[]'::jsonb) into v_deck
      from jsonb_array_elements_text(v_discard) as t(card);
      v_discard := '[]'::jsonb;
    end if;
    if jsonb_array_length(v_deck) > 0 then
      v_top_card := v_deck ->> 0;
      v_new_hand := v_new_hand || to_jsonb(v_top_card);
      v_deck := v_deck - 0;
    end if;
    v_hands := jsonb_set(v_hands, array[v_bot_id::text], v_new_hand);

    if v_kind in ('place', 'wild') then
      v_board := jsonb_set(
        v_board,
        array[v_pick_r::text, v_pick_c::text],
        jsonb_build_object('team', v_bot_team, 'sequence_ids', '[]'::jsonb)
      );

      v_prev_seq_count := jsonb_array_length(v_sequences);
      select rb.new_board, rb.new_sequences into v_rebalanced
      from public.assign_board_sequences(v_board, v_sequences) rb;
      v_board := v_rebalanced.new_board;
      v_sequences := v_rebalanced.new_sequences;

      v_required := public.win_threshold(v_room_id);
      select count(*) into v_team_seq_count
      from jsonb_array_elements(v_sequences) as s
      where (s ->> 'team')::int = v_bot_team;
      if v_team_seq_count >= v_required then
        v_new_status := 'finished';
        v_winner_team := v_bot_team;
      end if;
    else
      v_board := jsonb_set(
        v_board,
        array[v_pick_r::text, v_pick_c::text],
        jsonb_build_object('team', null, 'sequence_ids', '[]'::jsonb)
      );
    end if;

    if v_new_status = 'finished' then
      v_next_seat := v_turn_seat;
      v_new_cursor := v_team_cursor;
    else
      select nt.next_seat, nt.new_cursor into v_advance
      from public.next_turn_seat(v_room_id, v_turn_seat, v_team_cursor) nt;
      v_next_seat := v_advance.next_seat;
      v_new_cursor := v_advance.new_cursor;
    end if;

    v_new_version := v_version + 1;

    update public.games set
      version = v_new_version,
      status = v_new_status,
      winner_team = v_winner_team,
      deck = v_deck,
      discard = v_discard,
      hands = v_hands,
      board = v_board,
      sequences = v_sequences,
      turn_seat = v_next_seat,
      team_cursor = v_new_cursor,
      turn_deadline = case when v_new_status = 'in_game'
        then now() + (v_turn_seconds || ' seconds')::interval else null end,
      finished_at = case when v_new_status = 'finished' then now() else null end
    where id = p_game_id;

    insert into public.game_moves (
      game_id, version, user_id, action, card, tile_row, tile_col, payload
    ) values (
      p_game_id,
      v_new_version,
      v_bot_id,
      case when v_kind = 'remove' then 'remove' else 'place' end,
      v_card,
      v_pick_r,
      v_pick_c,
      jsonb_build_object(
        'team', v_bot_team,
        'drew', v_top_card,
        'via', case v_kind when 'wild' then 'bot_wild'
                           when 'remove' then 'bot_remove' else 'bot' end,
        'difficulty', v_difficulty,
        'new_sequences', case when v_kind in ('place', 'wild')
          then greatest(0, jsonb_array_length(v_sequences) - v_prev_seq_count)
          else 0 end,
        'winner_team', v_winner_team
      )
    );

    return v_new_version;
  end if;

  ----------------------------------------------------------------
  -- No legal move — forced discard + advance.
  ----------------------------------------------------------------
  if jsonb_array_length(v_bot_hand) > 0 then
    v_card := v_bot_hand ->> 0;
    v_new_hand := v_bot_hand - 0;
    v_discard := v_discard || to_jsonb(v_card);

    if jsonb_array_length(v_deck) = 0 and jsonb_array_length(v_discard) > 0 then
      select coalesce(jsonb_agg(card order by random()), '[]'::jsonb) into v_deck
      from jsonb_array_elements_text(v_discard) as t(card);
      v_discard := '[]'::jsonb;
    end if;
    if jsonb_array_length(v_deck) > 0 then
      v_top_card := v_deck ->> 0;
      v_new_hand := v_new_hand || to_jsonb(v_top_card);
      v_deck := v_deck - 0;
    end if;
    v_hands := jsonb_set(v_hands, array[v_bot_id::text], v_new_hand);
  end if;

  select nt.next_seat, nt.new_cursor into v_advance
  from public.next_turn_seat(v_room_id, v_turn_seat, v_team_cursor) nt;
  v_next_seat := v_advance.next_seat;
  v_new_cursor := v_advance.new_cursor;

  v_new_version := v_version + 1;

  update public.games set
    version = v_new_version,
    deck = v_deck,
    discard = v_discard,
    hands = v_hands,
    turn_seat = v_next_seat,
    team_cursor = v_new_cursor,
    turn_deadline = now() + (v_turn_seconds || ' seconds')::interval
  where id = p_game_id;

  insert into public.game_moves (
    game_id, version, user_id, action, card, payload
  ) values (
    p_game_id,
    v_new_version,
    v_bot_id,
    'auto_discard',
    v_card,
    jsonb_build_object('reason', 'bot_stuck', 'drew', v_top_card)
  );

  return v_new_version;
end;
$function$
;

-- ── redetect_sequences: regenerated from live definition, call site swapped ──
CREATE OR REPLACE FUNCTION public.redetect_sequences(p_game_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_caller uuid := auth.uid();
  v_room_id uuid;
  v_status text;
  v_version int;
  v_board jsonb;
  v_sequences jsonb;
  v_rebalanced record;
  v_team_seq_count int;
  v_required int;
  v_new_status text;
  v_winner_team int := null;
  v_new_version int;
  v_team int;
begin
  if v_caller is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  select room_id, status, version, board, sequences
    into v_room_id, v_status, v_version, v_board, v_sequences
  from public.games
  where id = p_game_id
  for update;

  if v_room_id is null then
    raise exception 'Game not found' using errcode = 'P0002';
  end if;
  -- Caller must be a member of the room (any seat) — same boundary as
  -- play_move authorization.
  if not exists (
    select 1 from public.room_players
    where room_id = v_room_id and user_id = v_caller
  ) then
    raise exception 'Not a player in this game' using errcode = '42501';
  end if;

  select rb.new_board, rb.new_sequences
    into v_rebalanced
  from public.assign_board_sequences(v_board, v_sequences) rb;

  v_required := public.win_threshold(v_room_id);
  v_new_status := v_status;

  -- Find any team that meets the win threshold after rebalance.
  for v_team in
    select distinct (s ->> 'team')::int
    from jsonb_array_elements(v_rebalanced.new_sequences) as s
  loop
    select count(*) into v_team_seq_count
    from jsonb_array_elements(v_rebalanced.new_sequences) as s
    where (s ->> 'team')::int = v_team;

    if v_team_seq_count >= v_required and v_winner_team is null then
      v_new_status := 'finished';
      v_winner_team := v_team;
    end if;
  end loop;

  v_new_version := v_version + 1;

  update public.games set
    version = v_new_version,
    status = v_new_status,
    winner_team = coalesce(v_winner_team, winner_team),
    board = v_rebalanced.new_board,
    sequences = v_rebalanced.new_sequences,
    turn_deadline = case when v_new_status = 'in_game'
      then turn_deadline else null end,
    finished_at = case when v_new_status = 'finished' and finished_at is null
      then now() else finished_at end
  where id = p_game_id;

  insert into public.game_moves (
    game_id, version, user_id, action, payload
  ) values (
    p_game_id,
    v_new_version,
    v_caller,
    'system',
    jsonb_build_object(
      'event', 'redetect_sequences',
      'seq_count_before', jsonb_array_length(v_sequences),
      'seq_count_after', jsonb_array_length(v_rebalanced.new_sequences),
      'winner_team', v_winner_team
    )
  );

  return jsonb_build_object(
    'sequences', v_rebalanced.new_sequences,
    'winner_team', v_winner_team,
    'status', v_new_status
  );
end;
$function$
;
