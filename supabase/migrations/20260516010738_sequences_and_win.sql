-- Phase 5.D + 5.E — Sequence detection and win condition.
--
-- 5.D: detect_new_sequences(board, team, row, col) returns the set of
-- newly-formed 5-in-a-row sequences passing through the just-placed
-- chip. Rules:
--   - same-team chips OR corner-wilds in a horizontal/vertical/diagonal
--     run of exactly 5
--   - corners count for any team (free) and have no chip-level limits
--   - a normal chip can be part of at most 2 sequences total
--   - a new sequence may reuse AT MOST ONE chip that's already in a
--     completed sequence (the "shared chip" rule)
--
-- 5.E: after appending newly-detected sequences, the play_* RPCs count
-- the team's total sequences and flip status='finished' + winner_team
-- when the threshold is met (2 sequences in 2-team games, 1 sequence in
-- 3-team games). Once finished, no further plays are accepted by any
-- RPC (the 'in_game' status check rejects them).
--
-- play_remove is NOT updated here — removing a chip doesn't form a new
-- sequence (it can only happen on chips outside completed sequences),
-- and we never auto-revoke sequences when a chip is removed.

----------------------------------------------------------------
-- 5.D — detect_new_sequences
----------------------------------------------------------------

create or replace function public.detect_new_sequences(
  p_board jsonb,
  p_team int,
  p_row int,
  p_col int
)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_dr int[] := array[0, 1, 1, 1];
  v_dc int[] := array[1, 0, 1, -1];
  v_dir int;
  v_offset int;
  v_i int;
  v_cr int;
  v_cc int;
  v_cell jsonb;
  v_cell_card text;
  v_cell_team int;
  v_cell_seq_count int;
  v_window_valid boolean;
  v_chips_in_existing int;
  v_seq_cells jsonb;
  v_new_sequences jsonb := '[]'::jsonb;
begin
  for v_dir in 1..4 loop
    for v_offset in -4..0 loop
      v_window_valid := true;
      v_chips_in_existing := 0;
      v_seq_cells := '[]'::jsonb;

      for v_i in 0..4 loop
        v_cr := p_row + (v_offset + v_i) * v_dr[v_dir];
        v_cc := p_col + (v_offset + v_i) * v_dc[v_dir];

        if v_cr < 0 or v_cr > 9 or v_cc < 0 or v_cc > 9 then
          v_window_valid := false;
          exit;
        end if;

        v_cell := p_board -> v_cr -> v_cc;
        v_cell_card := public.card_at(v_cr, v_cc);

        if v_cell_card is null then
          -- corner: free for any team, no limits
          null;
        else
          v_cell_team := (v_cell ->> 'team')::int;
          if v_cell_team is null or v_cell_team <> p_team then
            v_window_valid := false;
            exit;
          end if;
          v_cell_seq_count := jsonb_array_length(
            coalesce(v_cell -> 'sequence_ids', '[]'::jsonb)
          );
          -- A chip is already in 2 sequences — cannot join a 3rd.
          if v_cell_seq_count >= 2 then
            v_window_valid := false;
            exit;
          end if;
          if v_cell_seq_count > 0 then
            v_chips_in_existing := v_chips_in_existing + 1;
          end if;
        end if;

        v_seq_cells := v_seq_cells || jsonb_build_object('row', v_cr, 'col', v_cc);
      end loop;

      -- Shared-chip rule: a new sequence may reuse at most 1 existing.
      if v_window_valid and v_chips_in_existing <= 1 then
        v_new_sequences := v_new_sequences || jsonb_build_object(
          'cells', v_seq_cells
        );
      end if;
    end loop;
  end loop;

  return v_new_sequences;
end;
$$;

----------------------------------------------------------------
-- Helper to count required-sequences-to-win for a room.
----------------------------------------------------------------

create or replace function public.win_threshold(p_room_id uuid)
returns int
language sql
stable
set search_path = ''
as $$
  select case
    when (select count(distinct team) from public.room_players
            where room_id = p_room_id and team is not null) = 3
      then 1
    else 2
  end;
$$;

----------------------------------------------------------------
-- play_move v3 — adds sequence detection + win check.
----------------------------------------------------------------

create or replace function public.play_move(
  p_game_id uuid,
  p_client_version int,
  p_card text,
  p_row int,
  p_col int
)
returns int
language plpgsql
security definer
set search_path = ''
as $$
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
  v_caller_seat int;
  v_caller_team int;
  v_caller_hand jsonb;
  v_found_idx int;
  v_new_hand jsonb;
  v_top_card text;
  v_board_card text;
  v_cell jsonb;
  v_next_seat int;
  v_new_version int;
  v_new_seqs jsonb;
  v_seq_obj jsonb;
  v_cell_obj jsonb;
  v_cr int;
  v_cc int;
  v_seq_id int;
  v_existing_seq_ids jsonb;
  v_team_seq_count int;
  v_required int;
  v_new_status text := 'in_game';
  v_winner_team int := null;
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

  select room_id, status, version, turn_seat, deck, discard, hands, board, sequences
    into v_room_id, v_status, v_version, v_turn_seat, v_deck, v_discard, v_hands, v_board, v_sequences
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

  -- Place chip first so detect_new_sequences sees the updated board.
  v_board := jsonb_set(
    v_board,
    array[p_row::text, p_col::text],
    jsonb_build_object('team', v_caller_team, 'sequence_ids', '[]'::jsonb)
  );

  -- 5.D: detect new sequences passing through (p_row, p_col).
  v_new_seqs := public.detect_new_sequences(v_board, v_caller_team, p_row, p_col);

  if jsonb_array_length(v_new_seqs) > 0 then
    for v_seq_obj in select * from jsonb_array_elements(v_new_seqs) loop
      v_seq_id := jsonb_array_length(v_sequences) + 1;
      v_sequences := v_sequences || jsonb_build_object(
        'id', v_seq_id,
        'team', v_caller_team,
        'cells', v_seq_obj -> 'cells'
      );
      for v_cell_obj in select * from jsonb_array_elements(v_seq_obj -> 'cells') loop
        v_cr := (v_cell_obj ->> 'row')::int;
        v_cc := (v_cell_obj ->> 'col')::int;
        -- Skip corners (no chip-level sequence tracking on them).
        if public.card_at(v_cr, v_cc) is not null then
          v_existing_seq_ids := coalesce(
            v_board -> v_cr -> v_cc -> 'sequence_ids',
            '[]'::jsonb
          );
          v_board := jsonb_set(
            v_board,
            array[v_cr::text, v_cc::text, 'sequence_ids'],
            v_existing_seq_ids || to_jsonb(v_seq_id)
          );
        end if;
      end loop;
    end loop;

    -- 5.E: win check.
    v_required := public.win_threshold(v_room_id);
    select count(*) into v_team_seq_count
    from jsonb_array_elements(v_sequences) as s
    where (s ->> 'team')::int = v_caller_team;

    if v_team_seq_count >= v_required then
      v_new_status := 'finished';
      v_winner_team := v_caller_team;
    end if;
  end if;

  if v_new_status = 'finished' then
    v_next_seat := v_turn_seat; -- stays at the winner's seat
  else
    select coalesce(
      (select min(seat_index) from public.room_players
         where room_id = v_room_id and seat_index > v_turn_seat),
      (select min(seat_index) from public.room_players
         where room_id = v_room_id)
    )
    into v_next_seat;
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
      'new_sequences', jsonb_array_length(v_new_seqs),
      'winner_team', v_winner_team
    )
  );

  return v_new_version;
end;
$$;

----------------------------------------------------------------
-- play_wild v2 — adds sequence detection + win check.
----------------------------------------------------------------

create or replace function public.play_wild(
  p_game_id uuid,
  p_client_version int,
  p_card text,
  p_row int,
  p_col int
)
returns int
language plpgsql
security definer
set search_path = ''
as $$
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
  v_caller_seat int;
  v_caller_team int;
  v_caller_hand jsonb;
  v_found_idx int;
  v_new_hand jsonb;
  v_top_card text;
  v_board_card text;
  v_cell jsonb;
  v_next_seat int;
  v_new_version int;
  v_new_seqs jsonb;
  v_seq_obj jsonb;
  v_cell_obj jsonb;
  v_cr int;
  v_cc int;
  v_seq_id int;
  v_existing_seq_ids jsonb;
  v_team_seq_count int;
  v_required int;
  v_new_status text := 'in_game';
  v_winner_team int := null;
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

  select room_id, status, version, turn_seat, deck, discard, hands, board, sequences
    into v_room_id, v_status, v_version, v_turn_seat, v_deck, v_discard, v_hands, v_board, v_sequences
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

  v_new_seqs := public.detect_new_sequences(v_board, v_caller_team, p_row, p_col);

  if jsonb_array_length(v_new_seqs) > 0 then
    for v_seq_obj in select * from jsonb_array_elements(v_new_seqs) loop
      v_seq_id := jsonb_array_length(v_sequences) + 1;
      v_sequences := v_sequences || jsonb_build_object(
        'id', v_seq_id,
        'team', v_caller_team,
        'cells', v_seq_obj -> 'cells'
      );
      for v_cell_obj in select * from jsonb_array_elements(v_seq_obj -> 'cells') loop
        v_cr := (v_cell_obj ->> 'row')::int;
        v_cc := (v_cell_obj ->> 'col')::int;
        if public.card_at(v_cr, v_cc) is not null then
          v_existing_seq_ids := coalesce(
            v_board -> v_cr -> v_cc -> 'sequence_ids',
            '[]'::jsonb
          );
          v_board := jsonb_set(
            v_board,
            array[v_cr::text, v_cc::text, 'sequence_ids'],
            v_existing_seq_ids || to_jsonb(v_seq_id)
          );
        end if;
      end loop;
    end loop;

    v_required := public.win_threshold(v_room_id);
    select count(*) into v_team_seq_count
    from jsonb_array_elements(v_sequences) as s
    where (s ->> 'team')::int = v_caller_team;

    if v_team_seq_count >= v_required then
      v_new_status := 'finished';
      v_winner_team := v_caller_team;
    end if;
  end if;

  if v_new_status = 'finished' then
    v_next_seat := v_turn_seat;
  else
    select coalesce(
      (select min(seat_index) from public.room_players
         where room_id = v_room_id and seat_index > v_turn_seat),
      (select min(seat_index) from public.room_players
         where room_id = v_room_id)
    )
    into v_next_seat;
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
      'new_sequences', jsonb_array_length(v_new_seqs),
      'winner_team', v_winner_team
    )
  );

  return v_new_version;
end;
$$;
