-- Phase 4.A — play_move RPC. First playable mutation. Handles ONLY normal
-- (non-jack) cards onto matching empty tiles. Wilds and anti-wilds (jacks)
-- and dead-card swap come in Phase 5.
--
-- Server validates, in order: auth, in_game, optimistic concurrency,
-- caller's turn, card-in-hand, not a jack, tile matches the layout, tile
-- empty. On success it mutates atomically: remove the card from the
-- caller's hand, draw the top of the deck onto the hand, place the chip,
-- bump version, advance turn_seat (wrap), refresh turn_deadline, append
-- a row to game_moves keyed by the new version.

----------------------------------------------------------------
-- card_at(row, col) — server-side mirror of BOARD_LAYOUT.
-- Returns null for the four corner wild tiles.
----------------------------------------------------------------

create or replace function public.card_at(p_row int, p_col int)
returns text
language sql
immutable
set search_path = ''
as $$
  select (array[
    array[null,  '2S', '3S', '4S', '5S', '6S', '7S', '8S', '9S', null ],
    array['6C', '5C', '4C', '3C', '2C', 'AH', 'KH', 'QH', 'TH', 'TS' ],
    array['7C', 'AS', '2D', '3D', '4D', '5D', '6D', '7D', '9H', 'QS' ],
    array['8C', 'KS', '6C', '5C', '4C', '3C', '2C', '8D', '8H', 'KS' ],
    array['9C', 'QS', '7C', '6H', '5H', '4H', 'AH', '9D', '7H', 'AS' ],
    array['TC', 'TS', '8C', '7H', '2H', '3H', 'KH', 'TD', '6H', '2D' ],
    array['QC', '9S', '9C', '8H', '9H', 'TH', 'QH', 'QD', '5H', '3D' ],
    array['KC', '8S', 'TC', 'QC', 'KC', 'AC', 'AD', 'KD', '4H', '4D' ],
    array['AC', '7S', '6S', '5S', '4S', '3S', '2S', '2H', '3H', '5D' ],
    array[null,  'AD', 'KD', 'QD', 'TD', '9D', '8D', '7D', '6D', null ]
  ]::text[][])[p_row + 1][p_col + 1];
$$;

----------------------------------------------------------------
-- play_move — places a chip on a matching empty tile.
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
  v_hands jsonb;
  v_board jsonb;
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

  select room_id, status, version, turn_seat, deck, hands, board
    into v_room_id, v_status, v_version, v_turn_seat, v_deck, v_hands, v_board
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

  select coalesce(
    (select min(seat_index) from public.room_players
       where room_id = v_room_id and seat_index > v_turn_seat),
    (select min(seat_index) from public.room_players
       where room_id = v_room_id)
  )
  into v_next_seat;

  v_new_version := v_version + 1;

  update public.games set
    version = v_new_version,
    deck = v_deck,
    hands = v_hands,
    board = v_board,
    turn_seat = v_next_seat,
    turn_deadline = now() + (v_turn_seconds || ' seconds')::interval
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
      'drew', v_top_card
    )
  );

  return v_new_version;
end;
$$;

revoke all on function public.play_move(uuid, int, text, int, int) from public;
grant execute on function public.play_move(uuid, int, text, int, int) to authenticated;
