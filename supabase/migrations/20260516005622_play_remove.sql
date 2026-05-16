-- Phase 5.B — One-eyed jacks (anti-wild: remove an opponent's chip).
--
-- play_remove RPC. Same auth / version / turn / card-in-hand validation
-- as play_move and play_wild. Additional constraints:
--   - p_card must be JS or JH (one-eyed jack)
--   - target tile must be non-corner (you can't remove a corner)
--   - target cell must hold a chip
--   - that chip must NOT be the caller's team (no friendly fire)
--   - that chip must NOT already be part of a completed sequence
--     (sequence_ids array empty; populated by Phase 5.D)
-- On success: clear the cell, discard the jack, draw a replacement,
-- advance turn, log a 'remove' move ('remove' already in game_moves
-- CHECK constraint from 3.A).

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
  v_caller_seat int;
  v_caller_team int;
  v_caller_hand jsonb;
  v_found_idx int;
  v_new_hand jsonb;
  v_top_card text;
  v_board_card text;
  v_cell jsonb;
  v_cell_team int;
  v_cell_seq jsonb;
  v_next_seat int;
  v_new_version int;
begin
  if v_caller is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  if p_row < 0 or p_row > 9 or p_col < 0 or p_col > 9 then
    raise exception 'Invalid cell %, %', p_row, p_col using errcode = '22023';
  end if;

  if p_card is null or (p_card <> 'JS' and p_card <> 'JH') then
    raise exception 'play_remove only accepts one-eyed jacks (JS, JH); got %', p_card
      using errcode = '22023';
  end if;

  select room_id, status, version, turn_seat, deck, discard, hands, board
    into v_room_id, v_status, v_version, v_turn_seat, v_deck, v_discard, v_hands, v_board
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
    raise exception 'Cannot target a corner wild' using errcode = '22023';
  end if;

  v_cell := v_board -> p_row -> p_col;
  v_cell_team := (v_cell ->> 'team')::int;

  if v_cell_team is null then
    raise exception 'No chip to remove' using errcode = '22023';
  end if;
  if v_cell_team = v_caller_team then
    raise exception 'Cannot remove your own team''s chip' using errcode = '22023';
  end if;

  v_cell_seq := coalesce(v_cell -> 'sequence_ids', '[]'::jsonb);
  if jsonb_array_length(v_cell_seq) > 0 then
    raise exception 'Cannot remove a chip in a completed sequence'
      using errcode = '22023';
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

  -- Clear the target cell (team -> null, sequence_ids stays empty).
  v_board := jsonb_set(
    v_board,
    array[p_row::text, p_col::text],
    jsonb_build_object('team', null, 'sequence_ids', '[]'::jsonb)
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
    discard = v_discard,
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
    'remove',
    p_card,
    p_row,
    p_col,
    jsonb_build_object(
      'team', v_caller_team,
      'removed_team', v_cell_team,
      'drew', v_top_card
    )
  );

  return v_new_version;
end;
$$;

revoke all on function public.play_remove(uuid, int, text, int, int) from public;
grant execute on function public.play_remove(uuid, int, text, int, int) to authenticated;
