-- Phase 3.B — start_game replaces the minimal 2.D version. It now actually
-- shuffles two decks (104 cards, no jokers), deals each seated player a hand
-- per the PRD §6 size table, stashes the remainder in `deck`, initializes
-- the board, sets turn_seat=0, sets turn_deadline=now()+turn_seconds, and
-- writes the deal as a 'system' move at version 1.
--
-- Card encoding: 2-char strings. Rank (A,2-9,T,J,Q,K) + suit (D,C,H,S).
-- "T" instead of "10" so every card is exactly 2 chars (cheaper to render
-- and easier to switch on).

----------------------------------------------------------------
-- hand_size(player_count) — canonical Sequence hand sizes.
----------------------------------------------------------------

create or replace function public.hand_size(p_player_count int)
returns int
language sql
immutable
set search_path = ''
as $$
  select case p_player_count
    when 2  then 7
    when 3  then 6
    when 4  then 6
    when 6  then 5
    when 8  then 4
    when 10 then 3
    when 12 then 3
    else null
  end;
$$;

----------------------------------------------------------------
-- build_deck() — 104 shuffled cards (two standard decks, no jokers).
----------------------------------------------------------------

create or replace function public.build_deck()
returns jsonb
language sql
volatile
set search_path = ''
as $$
  select jsonb_agg(rank || suit order by random())
  from
    unnest(array['A','2','3','4','5','6','7','8','9','T','J','Q','K']) as r(rank)
    cross join
    unnest(array['D','C','H','S']) as s(suit)
    cross join
    generate_series(1, 2) as g(deck_idx);
$$;

----------------------------------------------------------------
-- empty_board() — 10x10 of {team: null, sequence_ids: []}.
----------------------------------------------------------------

create or replace function public.empty_board()
returns jsonb
language sql
immutable
set search_path = ''
as $$
  with cells as (
    select row_idx, col_idx, '{"team": null, "sequence_ids": []}'::jsonb as cell
    from generate_series(0, 9) row_idx,
         generate_series(0, 9) col_idx
  ),
  rows as (
    select row_idx, jsonb_agg(cell order by col_idx) as row
    from cells
    group by row_idx
  )
  select jsonb_agg(row order by row_idx)
  from rows;
$$;

----------------------------------------------------------------
-- start_game(code) — replaces the 2.D placeholder with full state.
----------------------------------------------------------------

create or replace function public.start_game(p_code text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller uuid := auth.uid();
  v_room_id uuid;
  v_host_id uuid;
  v_status text;
  v_turn_seconds int;
  v_total int;
  v_non_host_total int;
  v_non_host_ready int;
  v_hand_size int;
  v_deck jsonb;
  v_hands jsonb := '{}'::jsonb;
  v_player record;
  v_player_hand jsonb;
  v_offset int := 0;
  v_game_id uuid;
begin
  if v_caller is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  select id, host_id, status, turn_seconds
    into v_room_id, v_host_id, v_status, v_turn_seconds
  from public.rooms
  where code = upper(p_code);

  if v_room_id is null then
    raise exception 'Room not found' using errcode = 'P0002';
  end if;
  if v_caller <> v_host_id then
    raise exception 'Only the host can start the game' using errcode = '42501';
  end if;
  if v_status <> 'waiting' then
    raise exception 'Room is not in the waiting state' using errcode = '22023';
  end if;

  select
    count(*),
    count(*) filter (where user_id <> v_host_id),
    count(*) filter (where user_id <> v_host_id and ready)
  into v_total, v_non_host_total, v_non_host_ready
  from public.room_players
  where room_id = v_room_id;

  if v_total < 2 then
    raise exception 'Need at least 2 players to start' using errcode = '22023';
  end if;
  if v_non_host_ready <> v_non_host_total then
    raise exception 'Not all players are ready' using errcode = '22023';
  end if;

  v_hand_size := public.hand_size(v_total);
  if v_hand_size is null then
    raise exception 'Unsupported player count: %', v_total using errcode = '22023';
  end if;

  -- Shuffle 104 cards.
  v_deck := public.build_deck();

  -- Deal hand_size cards to each player in seat order. Cards 1..hand_size
  -- go to seat 0, hand_size+1..2*hand_size to seat 1, etc. Anything past
  -- that stays in v_deck as the draw pile.
  for v_player in
    select user_id, seat_index
    from public.room_players
    where room_id = v_room_id
    order by seat_index
  loop
    select coalesce(jsonb_agg(card order by ord), '[]'::jsonb)
    into v_player_hand
    from jsonb_array_elements_text(v_deck) with ordinality as t(card, ord)
    where ord > v_offset and ord <= v_offset + v_hand_size;

    v_hands := v_hands
      || jsonb_build_object(v_player.user_id::text, v_player_hand);
    v_offset := v_offset + v_hand_size;
  end loop;

  -- Trim dealt cards off the front of the deck.
  select coalesce(jsonb_agg(card order by ord), '[]'::jsonb)
  into v_deck
  from jsonb_array_elements_text(v_deck) with ordinality as t(card, ord)
  where ord > v_offset;

  -- Insert the full initial state. version=1 = first state mutation.
  insert into public.games (
    room_id,
    host_id,
    status,
    version,
    deck,
    hands,
    board,
    turn_seat,
    turn_deadline
  ) values (
    v_room_id,
    v_host_id,
    'in_game',
    1,
    v_deck,
    v_hands,
    public.empty_board(),
    0,
    now() + (v_turn_seconds || ' seconds')::interval
  )
  returning id into v_game_id;

  -- Log the deal as a system move at version 1.
  insert into public.game_moves (
    game_id, version, user_id, action, payload
  ) values (
    v_game_id,
    1,
    null,
    'system',
    jsonb_build_object(
      'event', 'deal',
      'player_count', v_total,
      'hand_size', v_hand_size,
      'turn_seconds', v_turn_seconds
    )
  );

  -- Flip the room into 'in_game'.
  update public.rooms set status = 'in_game' where id = v_room_id;

  return v_game_id;
end;
$$;
