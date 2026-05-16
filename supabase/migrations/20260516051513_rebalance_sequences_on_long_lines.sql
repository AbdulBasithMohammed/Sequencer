-- Rebalance sequences when a long line forms.
--
-- The prior detect_new_sequences only looked at 5-windows through the
-- placed chip and rejected windows that overlapped an existing sequence
-- by more than 1 chip. That made the (legal!) "2 sequences in a single
-- line of 9 or 10 chips" case undetectable when the existing sequence
-- sat in the middle: every candidate window overlapped it by 2+.
--
-- Fix: after each placement, recompute the full sequence list from
-- scratch by scanning every line on the board. For each maximal run of
-- same-team chips (corners count as wild), partition it into the max
-- number of legal 5-windows. A line of L same-team chips holds
-- N = floor((L-1)/4) sequences:
--   L=5..8   → 1 sequence
--   L=9      → 2 sequences sharing 1 chip (4-stride)
--   L=10     → 2 sequences sharing 0 chips (5-stride)
-- Existing sequences whose cells no longer match the recomputed
-- partition get re-anchored (lower-coordinate end keeps the lowest ID).
-- IDs renumber from 1 each turn; nothing external references them.

----------------------------------------------------------------
-- Helper: partition a run of cells into legal sequences.
-- Cells are passed in order along the line. Returns array of
-- {team, cells} objects.
----------------------------------------------------------------

create or replace function public.partition_run_into_sequences(
  p_cells jsonb,
  p_team int
)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_len int;
  v_n int;
  v_stride int;
  v_seqs jsonb := '[]'::jsonb;
  v_i int;
  v_start int;
  v_seq_cells jsonb;
  v_j int;
begin
  v_len := jsonb_array_length(p_cells);
  if v_len < 5 or p_team is null then
    return v_seqs;
  end if;

  v_n := (v_len - 1) / 4;
  if v_n > 2 then v_n := 2; end if;  -- 10x10 board: max 2 per line

  -- Prefer non-overlapping (stride 5) if it fits, else 1-chip overlap.
  if v_len >= 5 * v_n then
    v_stride := 5;
  else
    v_stride := 4;
  end if;

  for v_i in 0 .. (v_n - 1) loop
    v_start := v_i * v_stride;
    v_seq_cells := '[]'::jsonb;
    for v_j in 0 .. 4 loop
      v_seq_cells := v_seq_cells || (p_cells -> (v_start + v_j));
    end loop;
    v_seqs := v_seqs ||
      jsonb_build_object('team', p_team, 'cells', v_seq_cells);
  end loop;

  return v_seqs;
end;
$$;

----------------------------------------------------------------
-- Helper: walk one line and yield maximal same-team runs.
-- Corners (card_at = null) are wild — they extend whichever team's
-- run they're adjacent to. A corner before the first chip is held
-- "pending" until a team chip appears.
----------------------------------------------------------------

create or replace function public.line_runs(
  p_board jsonb,
  p_start_r int,
  p_start_c int,
  p_dr int,
  p_dc int
)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_runs jsonb := '[]'::jsonb;
  v_run_cells jsonb := '[]'::jsonb;
  v_run_team int := null;
  v_pending_corners jsonb := '[]'::jsonb;
  v_r int := p_start_r;
  v_c int := p_start_c;
  v_card text;
  v_cell jsonb;
  v_cell_team int;
begin
  while v_r >= 0 and v_r <= 9 and v_c >= 0 and v_c <= 9 loop
    v_card := public.card_at(v_r, v_c);

    if v_card is null then
      -- corner: wild
      if v_run_team is null then
        v_pending_corners := v_pending_corners ||
          jsonb_build_object('row', v_r, 'col', v_c);
      else
        v_run_cells := v_run_cells ||
          jsonb_build_object('row', v_r, 'col', v_c);
      end if;
    else
      v_cell := p_board -> v_r -> v_c;
      v_cell_team := (v_cell ->> 'team')::int;

      if v_cell_team is null then
        -- empty cell ends the run
        if jsonb_array_length(v_run_cells) >= 5 then
          v_runs := v_runs ||
            jsonb_build_object('team', v_run_team, 'cells', v_run_cells);
        end if;
        v_run_cells := '[]'::jsonb;
        v_run_team := null;
        v_pending_corners := '[]'::jsonb;
      elsif v_run_team is null then
        -- first chip in a new run; absorb pending corners
        v_run_team := v_cell_team;
        v_run_cells := v_pending_corners ||
          jsonb_build_object('row', v_r, 'col', v_c);
        v_pending_corners := '[]'::jsonb;
      elsif v_cell_team = v_run_team then
        v_run_cells := v_run_cells ||
          jsonb_build_object('row', v_r, 'col', v_c);
      else
        -- team switch: flush old run, start new
        if jsonb_array_length(v_run_cells) >= 5 then
          v_runs := v_runs ||
            jsonb_build_object('team', v_run_team, 'cells', v_run_cells);
        end if;
        v_run_team := v_cell_team;
        v_run_cells := jsonb_build_array(
          jsonb_build_object('row', v_r, 'col', v_c)
        );
        v_pending_corners := '[]'::jsonb;
      end if;
    end if;

    v_r := v_r + p_dr;
    v_c := v_c + p_dc;
  end loop;

  -- flush at end of line
  if jsonb_array_length(v_run_cells) >= 5 then
    v_runs := v_runs ||
      jsonb_build_object('team', v_run_team, 'cells', v_run_cells);
  end if;

  return v_runs;
end;
$$;

----------------------------------------------------------------
-- Scan every line in every direction; partition each run; return
-- the canonical list of sequences (no IDs assigned yet).
----------------------------------------------------------------

create or replace function public.compute_all_sequences(p_board jsonb)
returns jsonb
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_all jsonb := '[]'::jsonb;
  v_i int;
  v_runs jsonb;
  v_run jsonb;
  v_seqs jsonb;
begin
  -- horizontal (row-fixed)
  for v_i in 0..9 loop
    v_runs := public.line_runs(p_board, v_i, 0, 0, 1);
    for v_run in select * from jsonb_array_elements(v_runs) loop
      v_seqs := public.partition_run_into_sequences(
        v_run -> 'cells', (v_run ->> 'team')::int
      );
      v_all := v_all || v_seqs;
    end loop;
  end loop;

  -- vertical (col-fixed)
  for v_i in 0..9 loop
    v_runs := public.line_runs(p_board, 0, v_i, 1, 0);
    for v_run in select * from jsonb_array_elements(v_runs) loop
      v_seqs := public.partition_run_into_sequences(
        v_run -> 'cells', (v_run ->> 'team')::int
      );
      v_all := v_all || v_seqs;
    end loop;
  end loop;

  -- diag down-right: starts on top row + left column (skip (0,0) dup)
  for v_i in 0..9 loop
    v_runs := public.line_runs(p_board, 0, v_i, 1, 1);
    for v_run in select * from jsonb_array_elements(v_runs) loop
      v_seqs := public.partition_run_into_sequences(
        v_run -> 'cells', (v_run ->> 'team')::int
      );
      v_all := v_all || v_seqs;
    end loop;
  end loop;
  for v_i in 1..9 loop
    v_runs := public.line_runs(p_board, v_i, 0, 1, 1);
    for v_run in select * from jsonb_array_elements(v_runs) loop
      v_seqs := public.partition_run_into_sequences(
        v_run -> 'cells', (v_run ->> 'team')::int
      );
      v_all := v_all || v_seqs;
    end loop;
  end loop;

  -- diag down-left: starts on top row + right column (skip (0,9) dup)
  for v_i in 0..9 loop
    v_runs := public.line_runs(p_board, 0, v_i, 1, -1);
    for v_run in select * from jsonb_array_elements(v_runs) loop
      v_seqs := public.partition_run_into_sequences(
        v_run -> 'cells', (v_run ->> 'team')::int
      );
      v_all := v_all || v_seqs;
    end loop;
  end loop;
  for v_i in 1..9 loop
    v_runs := public.line_runs(p_board, v_i, 9, 1, -1);
    for v_run in select * from jsonb_array_elements(v_runs) loop
      v_seqs := public.partition_run_into_sequences(
        v_run -> 'cells', (v_run ->> 'team')::int
      );
      v_all := v_all || v_seqs;
    end loop;
  end loop;

  return v_all;
end;
$$;

----------------------------------------------------------------
-- Helper: apply a recomputed sequence list to a board (resets every
-- chip's sequence_ids and writes new ones). Returns the new board
-- and sequences-with-ids tuple. Used by play_move, play_wild, and
-- redetect_sequences.
----------------------------------------------------------------

create or replace function public.rebalance_board_sequences(p_board jsonb)
returns table(new_board jsonb, new_sequences jsonb)
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_computed jsonb;
  v_assigned jsonb := '[]'::jsonb;
  v_seq jsonb;
  v_cell jsonb;
  v_r int;
  v_c int;
  v_id int := 1;
  v_board jsonb := p_board;
  v_existing_seq_ids jsonb;
begin
  v_computed := public.compute_all_sequences(p_board);

  -- Reset every placed chip's sequence_ids to [].
  for v_r in 0..9 loop
    for v_c in 0..9 loop
      if public.card_at(v_r, v_c) is not null then
        if (v_board -> v_r -> v_c ->> 'team') is not null then
          v_board := jsonb_set(
            v_board,
            array[v_r::text, v_c::text, 'sequence_ids'],
            '[]'::jsonb
          );
        end if;
      end if;
    end loop;
  end loop;

  -- Assign IDs and write sequence_ids onto each chip.
  for v_seq in select * from jsonb_array_elements(v_computed) loop
    v_assigned := v_assigned || jsonb_build_object(
      'id', v_id,
      'team', (v_seq ->> 'team')::int,
      'cells', v_seq -> 'cells'
    );
    for v_cell in select * from jsonb_array_elements(v_seq -> 'cells') loop
      v_r := (v_cell ->> 'row')::int;
      v_c := (v_cell ->> 'col')::int;
      -- Skip corners (no chip-level sequence tracking).
      if public.card_at(v_r, v_c) is not null then
        v_existing_seq_ids := coalesce(
          v_board -> v_r -> v_c -> 'sequence_ids',
          '[]'::jsonb
        );
        v_board := jsonb_set(
          v_board,
          array[v_r::text, v_c::text, 'sequence_ids'],
          v_existing_seq_ids || to_jsonb(v_id)
        );
      end if;
    end loop;
    v_id := v_id + 1;
  end loop;

  new_board := v_board;
  new_sequences := v_assigned;
  return next;
end;
$$;

----------------------------------------------------------------
-- play_move v4: place chip → rebalance entire board's sequences
-- → win check.
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
  v_prev_seq_count int;
  v_team_seq_count int;
  v_required int;
  v_new_status text := 'in_game';
  v_winner_team int := null;
  v_rebalanced record;
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

  v_board := jsonb_set(
    v_board,
    array[p_row::text, p_col::text],
    jsonb_build_object('team', v_caller_team, 'sequence_ids', '[]'::jsonb)
  );

  -- Recompute every sequence on the board after placement.
  v_prev_seq_count := jsonb_array_length(v_sequences);
  select rb.new_board, rb.new_sequences
    into v_rebalanced
  from public.rebalance_board_sequences(v_board) rb;
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
      'new_sequences', greatest(0, jsonb_array_length(v_sequences) - v_prev_seq_count),
      'winner_team', v_winner_team
    )
  );

  return v_new_version;
end;
$$;

----------------------------------------------------------------
-- play_wild v3: same change — recompute sequences after placement.
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
  v_prev_seq_count int;
  v_team_seq_count int;
  v_required int;
  v_new_status text := 'in_game';
  v_winner_team int := null;
  v_rebalanced record;
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

  v_prev_seq_count := jsonb_array_length(v_sequences);
  select rb.new_board, rb.new_sequences
    into v_rebalanced
  from public.rebalance_board_sequences(v_board) rb;
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
      'new_sequences', greatest(0, jsonb_array_length(v_sequences) - v_prev_seq_count),
      'winner_team', v_winner_team
    )
  );

  return v_new_version;
end;
$$;

----------------------------------------------------------------
-- redetect_sequences: retroactively rebalance an in-progress game.
-- Useful one-off for games created before this migration shipped
-- where a long-line second sequence was missed.
----------------------------------------------------------------

create or replace function public.redetect_sequences(p_game_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
  from public.rebalance_board_sequences(v_board) rb;

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
$$;
