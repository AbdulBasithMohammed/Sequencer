-- Team-alternating turn order.
--
-- Previously: next turn = next-greater seat_index, wrapping. That gave
-- correct alternation only when seats happened to be interleaved by team.
-- If players changed teams via set_team or if teams were unbalanced, the
-- order broke (e.g. T1,T2,T2,T1 for 2v2; T1,T2,T2 for 1v2).
--
-- New rule: turns alternate across teams in canonical order (1, 2, [3]).
-- Within each team, players cycle round-robin by seat_index. With an
-- unbalanced team (1v2), the lone player goes every other turn, while the
-- two players on the other team alternate between their own turns:
--   T1A → T2X → T1A → T2Y → T1A → T2X → ...
--
-- Implementation: a jsonb cursor on games tracks "last seat that played
-- per team": {"1": 0, "2": 3}. After each move, advance the cursor for
-- the team that just played and pick the next team's next seat
-- (smallest seat in that team > its last-used, wrapping to smallest).

alter table public.games
  add column if not exists team_cursor jsonb not null default '{}'::jsonb;

----------------------------------------------------------------
-- next_turn_seat(room, current_seat, cursor)
--   Returns (next_seat int, new_cursor jsonb).
-- Assumes current_seat is the seat that JUST played.
----------------------------------------------------------------

create or replace function public.next_turn_seat(
  p_room_id uuid,
  p_current_seat int,
  p_cursor jsonb
) returns table(next_seat int, new_cursor jsonb)
language plpgsql
stable
set search_path = ''
as $$
declare
  v_current_team int;
  v_teams int[];
  v_idx int;
  v_next_team int;
  v_last_used int;
  v_next_seat int;
  v_cursor jsonb;
begin
  v_cursor := coalesce(p_cursor, '{}'::jsonb);

  -- Team of the player who just played.
  select team into v_current_team
  from public.room_players
  where room_id = p_room_id and seat_index = p_current_seat;

  if v_current_team is null then
    -- No player at this seat (rare). Fall back to legacy walk so the
    -- game never wedges.
    select coalesce(
      (select min(seat_index) from public.room_players
         where room_id = p_room_id and seat_index > p_current_seat),
      (select min(seat_index) from public.room_players
         where room_id = p_room_id)
    ) into v_next_seat;
    return query select v_next_seat, v_cursor;
    return;
  end if;

  -- Stamp the cursor with this team's freshly-played seat.
  v_cursor := jsonb_set(
    v_cursor,
    array[v_current_team::text],
    to_jsonb(p_current_seat),
    true
  );

  -- Teams present in the room, in canonical order (1,2,3) — but only
  -- those that actually have at least one seated player.
  select coalesce(array_agg(distinct team order by team), array[]::int[])
    into v_teams
  from public.room_players
  where room_id = p_room_id and team is not null;

  if array_length(v_teams, 1) is null or array_length(v_teams, 1) = 0 then
    return query select p_current_seat, v_cursor;
    return;
  end if;

  -- Find position of current team in the canonical list.
  v_idx := array_position(v_teams, v_current_team);
  if v_idx is null then
    v_idx := 1;
  end if;

  -- Next team (wrap).
  v_next_team := v_teams[(v_idx % array_length(v_teams, 1)) + 1];

  -- Last seat used for that team — null if it has never played.
  v_last_used := nullif(v_cursor ->> v_next_team::text, '')::int;

  -- Smallest seat in the next team strictly greater than its last-used,
  -- wrapping to its smallest seat if nothing greater (or never played).
  select coalesce(
    (select min(seat_index) from public.room_players
       where room_id = p_room_id
         and team = v_next_team
         and (v_last_used is null or seat_index > v_last_used)),
    (select min(seat_index) from public.room_players
       where room_id = p_room_id and team = v_next_team)
  ) into v_next_seat;

  -- Defensive fallback if the next team has no seated player.
  if v_next_seat is null then
    select coalesce(
      (select min(seat_index) from public.room_players
         where room_id = p_room_id and seat_index > p_current_seat),
      (select min(seat_index) from public.room_players
         where room_id = p_room_id)
    ) into v_next_seat;
  end if;

  return query select v_next_seat, v_cursor;
end;
$$;

grant execute on function public.next_turn_seat(uuid, int, jsonb) to authenticated;

----------------------------------------------------------------
-- play_move: use next_turn_seat for turn rotation.
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
$$;

----------------------------------------------------------------
-- play_wild: same turn-rotation change.
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
$$;

----------------------------------------------------------------
-- play_remove: same turn-rotation change.
----------------------------------------------------------------

create or replace function public.play_remove(
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
  v_team_cursor jsonb;
  v_caller_seat int;
  v_caller_team int;
  v_caller_hand jsonb;
  v_found_idx int;
  v_new_hand jsonb;
  v_top_card text;
  v_cell jsonb;
  v_cell_team int;
  v_cell_seq_ids jsonb;
  v_next_seat int;
  v_new_cursor jsonb;
  v_new_version int;
  v_advance record;
begin
  if v_caller is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  if p_row < 0 or p_row > 9 or p_col < 0 or p_col > 9 then
    raise exception 'Invalid cell %, %', p_row, p_col using errcode = '22023';
  end if;

  if p_card is null or (p_card <> 'JH' and p_card <> 'JS') then
    raise exception 'play_remove only accepts one-eyed jacks (JH, JS); got %', p_card
      using errcode = '22023';
  end if;

  select room_id, status, version, turn_seat, deck, discard, hands, board, team_cursor
    into v_room_id, v_status, v_version, v_turn_seat, v_deck, v_discard, v_hands, v_board, v_team_cursor
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

  v_cell := v_board -> p_row -> p_col;
  v_cell_team := (v_cell ->> 'team')::int;
  v_cell_seq_ids := coalesce(v_cell -> 'sequence_ids', '[]'::jsonb);

  if v_cell_team is null then
    raise exception 'Cell is empty' using errcode = '22023';
  end if;
  if v_cell_team = v_caller_team then
    raise exception 'Cannot remove your own chip' using errcode = '22023';
  end if;
  if jsonb_array_length(v_cell_seq_ids) > 0 then
    raise exception 'Chip is part of a completed sequence' using errcode = '22023';
  end if;
  if public.card_at(p_row, p_col) is null then
    raise exception 'Corner cells have no chip' using errcode = '22023';
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
    jsonb_build_object('team', null, 'sequence_ids', '[]'::jsonb)
  );

  select nt.next_seat, nt.new_cursor
    into v_advance
  from public.next_turn_seat(v_room_id, v_turn_seat, v_team_cursor) nt;
  v_next_seat := v_advance.next_seat;
  v_new_cursor := v_advance.new_cursor;

  v_new_version := v_version + 1;

  update public.games set
    version = v_new_version,
    deck = v_deck,
    discard = v_discard,
    hands = v_hands,
    board = v_board,
    turn_seat = v_next_seat,
    team_cursor = v_new_cursor,
    turn_deadline = now() + (v_turn_seconds || ' seconds')::interval
  where id = p_game_id;

  insert into public.game_moves (
    game_id, version, user_id, action, card, tile_row, tile_col, payload
  ) values (
    p_game_id,
    v_new_version,
    v_caller,
    'remove',
    p_card,
    p_row,
    p_col,
    jsonb_build_object(
      'removed_team', v_cell_team,
      'drew', v_top_card
    )
  );

  return v_new_version;
end;
$$;

----------------------------------------------------------------
-- auto_advance_turn: same turn-rotation change.
----------------------------------------------------------------

create or replace function public.auto_advance_turn(p_game_id uuid)
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_room_id uuid;
  v_status text;
  v_version int;
  v_turn_seat int;
  v_turn_deadline timestamptz;
  v_turn_seconds int;
  v_deck jsonb;
  v_discard jsonb;
  v_hands jsonb;
  v_team_cursor jsonb;
  v_current_player_id uuid;
  v_current_hand jsonb;
  v_discarded_card text;
  v_top_card text;
  v_new_hand jsonb;
  v_next_seat int;
  v_new_cursor jsonb;
  v_new_version int;
  v_advance record;
begin
  select room_id, status, version, turn_seat, turn_deadline, deck, discard, hands, team_cursor
    into v_room_id, v_status, v_version, v_turn_seat, v_turn_deadline, v_deck, v_discard, v_hands, v_team_cursor
  from public.games
  where id = p_game_id
  for update;

  if v_room_id is null or v_status <> 'in_game' then
    return -1;
  end if;
  if v_turn_deadline is null or v_turn_deadline > now() then
    return -1;
  end if;

  select turn_seconds into v_turn_seconds from public.rooms where id = v_room_id;

  select user_id into v_current_player_id
  from public.room_players
  where room_id = v_room_id and seat_index = v_turn_seat;

  -- No player at this seat: still advance and refresh deadline.
  if v_current_player_id is null then
    select nt.next_seat, nt.new_cursor
      into v_advance
    from public.next_turn_seat(v_room_id, v_turn_seat, v_team_cursor) nt;
    v_next_seat := v_advance.next_seat;
    v_new_cursor := v_advance.new_cursor;

    v_new_version := v_version + 1;
    update public.games set
      version = v_new_version,
      turn_seat = v_next_seat,
      team_cursor = v_new_cursor,
      turn_deadline = now() + (v_turn_seconds || ' seconds')::interval
    where id = p_game_id;
    return v_new_version;
  end if;

  v_current_hand := coalesce(v_hands -> v_current_player_id::text, '[]'::jsonb);

  -- Auto-discard the top card of the AFK player's hand (per PRD).
  if jsonb_array_length(v_current_hand) > 0 then
    v_discarded_card := v_current_hand ->> 0;
    v_new_hand := v_current_hand - 0;
    v_discard := v_discard || to_jsonb(v_discarded_card);

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

    v_hands := jsonb_set(v_hands, array[v_current_player_id::text], v_new_hand);
  end if;

  select nt.next_seat, nt.new_cursor
    into v_advance
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
    v_current_player_id,
    'auto_discard',
    v_discarded_card,
    jsonb_build_object(
      'reason', 'turn_timeout',
      'drew', v_top_card
    )
  );

  return v_new_version;
end;
$$;
