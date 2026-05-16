-- Phase 5.C — Dead-card swap.
--
-- swap_dead_card(p_game_id, p_client_version, p_card)
-- Per Goliath rules §"DEAD CARD": if both board positions of a card in
-- your hand are already claimed, you may discard it and draw a
-- replacement on your turn, then play normally. We DON'T advance turn
-- here — the player still owes their main move.
--
-- Constraints:
--   - auth / in_game / version / turn / card-in-hand (same as plays)
--   - card must NOT be a Jack (jacks always have a way to play)
--   - both board positions of this card must be occupied (team != null)

create or replace function public.swap_dead_card(
  p_game_id uuid,
  p_client_version int,
  p_card text
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
  v_empty_positions int;
  v_new_version int;
begin
  if v_caller is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  if p_card is null or length(p_card) <> 2 then
    raise exception 'Invalid card %', p_card using errcode = '22023';
  end if;

  if substring(p_card from 1 for 1) = 'J' then
    raise exception 'Jacks are never dead (they always have a play)'
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

  v_caller_hand := coalesce(v_hands -> v_caller::text, '[]'::jsonb);

  select (ord - 1)::int into v_found_idx
  from jsonb_array_elements_text(v_caller_hand) with ordinality as t(card, ord)
  where card = p_card
  order by ord
  limit 1;

  if v_found_idx is null then
    raise exception 'Card not in hand' using errcode = '22023';
  end if;

  -- Both board positions of this card must be claimed (no opening).
  select count(*) into v_empty_positions
  from generate_series(0, 9) as r,
       generate_series(0, 9) as c
  where public.card_at(r, c) = p_card
    and ((v_board -> r -> c) ->> 'team') is null;

  if v_empty_positions > 0 then
    raise exception 'Card is not dead (% open position(s) remain)', v_empty_positions
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

  v_new_version := v_version + 1;

  -- NOTE: turn_seat does NOT advance — the player still owes their move.
  -- turn_deadline isn't refreshed either; the swap is meant to be quick.
  update public.games set
    version = v_new_version,
    deck = v_deck,
    discard = v_discard,
    hands = v_hands
  where id = p_game_id;

  insert into public.game_moves (
    game_id, version, user_id, action, card, payload
  ) values (
    p_game_id,
    v_new_version,
    v_caller,
    'swap_dead',
    p_card,
    jsonb_build_object(
      'team', v_caller_team,
      'drew', v_top_card
    )
  );

  return v_new_version;
end;
$$;

revoke all on function public.swap_dead_card(uuid, int, text) from public;
grant execute on function public.swap_dead_card(uuid, int, text) to authenticated;
