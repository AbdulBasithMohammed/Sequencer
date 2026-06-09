-- Phase 8.E — Bot defense + jack/dead-card discipline.
--
-- Adds three things on top of 8.D's offense:
--   1. Defense. Placing on the gap of an opponent open-four (or three) is
--      worth a big block bonus; a one-eyed jack that removes a chip out of
--      an opponent open-four is worth nearly as much. Both fold into the
--      same candidate score so the existing ORDER BY score DESC realises
--      "win → complete → block → build".
--   2. Jack discipline. Two-eyed jacks are hoarded — a wild scores its
--      cell value only when that clears the "worth a jack" bar (block /
--      double-threat / complete); otherwise it's penalised so a normal
--      card is played and the jack kept. One-eyed jacks are held unless
--      they break a real (open-four) threat.
--   3. Dead-card swap. Before choosing a move the bot takes its one free
--      swap of a dead card (both board copies covered) for a fresh draw,
--      which can even enable a better play that same turn.
--
-- Defensive weights share C_BLOCK with placement so block-by-place and
-- break-by-remove are directly comparable (place-block edges out remove,
-- so the bot blocks with a card when it can and only spends the jack when
-- it can't).

----------------------------------------------------------------
-- bot_opp_four_block(board, our_team, row, col):
--   Defensive value of placing OUR chip on the empty cell (row,col): how
--   many opponent open-fours it plugs (the cell is the sole gap), plus a
--   small credit for disrupting opponent open-threes. Corners count for
--   the opponent too.
----------------------------------------------------------------

create or replace function public.bot_opp_four_block(
  p_board jsonb,
  p_team int,
  p_row int,
  p_col int
)
returns numeric
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_dr int[] := array[0, 1, 1, 1];
  v_dc int[] := array[1, 0, 1, -1];
  c_block       constant numeric := 5000;
  c_block_three constant numeric := 150;
  d int; s int; k int;
  sr int; sc int; cr int; cc int;
  v_opp_team int; v_opp_ct int; v_corner_ct int; v_our_ct int; v_empty_ct int;
  v_multi boolean; v_cell_team text; v_is_corner boolean;
  v_score numeric := 0;
begin
  for d in 1..4 loop
    for s in 0..4 loop
      sr := p_row - s * v_dr[d];
      sc := p_col - s * v_dc[d];
      if sr < 0 or sr > 9 or sc < 0 or sc > 9 then continue; end if;
      if (sr + 4 * v_dr[d]) < 0 or (sr + 4 * v_dr[d]) > 9
         or (sc + 4 * v_dc[d]) < 0 or (sc + 4 * v_dc[d]) > 9 then continue; end if;

      v_opp_team := null; v_opp_ct := 0; v_corner_ct := 0;
      v_our_ct := 0; v_empty_ct := 0; v_multi := false;
      for k in 0..4 loop
        cr := sr + k * v_dr[d];
        cc := sc + k * v_dc[d];
        if cr = p_row and cc = p_col then
          continue;  -- the gap we'd fill
        end if;
        v_is_corner := (cr = 0 or cr = 9) and (cc = 0 or cc = 9);
        if v_is_corner then
          v_corner_ct := v_corner_ct + 1;
        else
          v_cell_team := (p_board -> cr -> cc) ->> 'team';
          if v_cell_team is null then
            v_empty_ct := v_empty_ct + 1;
          elsif v_cell_team::int = p_team then
            v_our_ct := v_our_ct + 1;
          elsif v_opp_team is null then
            v_opp_team := v_cell_team::int; v_opp_ct := 1;
          elsif v_cell_team::int = v_opp_team then
            v_opp_ct := v_opp_ct + 1;
          else
            v_multi := true;
          end if;
        end if;
      end loop;

      if v_our_ct = 0 and not v_multi and v_opp_team is not null then
        if v_empty_ct = 0 and (v_opp_ct + v_corner_ct) = 4 then
          v_score := v_score + c_block;          -- opponent open-four, gap here
        elsif v_empty_ct = 1 and (v_opp_ct + v_corner_ct) = 3 then
          v_score := v_score + c_block_three;    -- opponent open-three
        end if;
      end if;
    end loop;
  end loop;

  return v_score;
end;
$$;

revoke all on function public.bot_opp_four_block(jsonb, int, int, int) from public;

----------------------------------------------------------------
-- bot_removal_value(board, our_team, row, col):
--   Value of removing the opponent chip at (row,col) with a one-eyed jack.
--   High when the chip sits in an opponent open-four (removal breaks it),
--   small for a three. 0 if the cell isn't an opponent chip. Slightly
--   below C_BLOCK so a card-block is preferred over spending the jack.
----------------------------------------------------------------

create or replace function public.bot_removal_value(
  p_board jsonb,
  p_team int,
  p_row int,
  p_col int
)
returns numeric
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_dr int[] := array[0, 1, 1, 1];
  v_dc int[] := array[1, 0, 1, -1];
  c_remove_four  constant numeric := 4500;
  c_remove_three constant numeric := 150;
  v_owner int;
  d int; s int; k int;
  sr int; sc int; cr int; cc int;
  v_x_ct int; v_other_ct int;
  v_cell_team text; v_is_corner boolean;
  v_score numeric := 0;
begin
  v_owner := nullif((p_board -> p_row -> p_col) ->> 'team', '')::int;
  if v_owner is null or v_owner = p_team then
    return 0;  -- not an opponent chip
  end if;

  for d in 1..4 loop
    for s in 0..4 loop
      sr := p_row - s * v_dr[d];
      sc := p_col - s * v_dc[d];
      if sr < 0 or sr > 9 or sc < 0 or sc > 9 then continue; end if;
      if (sr + 4 * v_dr[d]) < 0 or (sr + 4 * v_dr[d]) > 9
         or (sc + 4 * v_dc[d]) < 0 or (sc + 4 * v_dc[d]) > 9 then continue; end if;

      v_x_ct := 0; v_other_ct := 0;
      for k in 0..4 loop
        cr := sr + k * v_dr[d];
        cc := sc + k * v_dc[d];
        v_is_corner := (cr = 0 or cr = 9) and (cc = 0 or cc = 9);
        if cr = p_row and cc = p_col then
          v_x_ct := v_x_ct + 1;            -- the chip we'd remove (owner's)
        elsif v_is_corner then
          v_x_ct := v_x_ct + 1;            -- corner counts for the owner
        else
          v_cell_team := (p_board -> cr -> cc) ->> 'team';
          if v_cell_team is null then
            null;
          elsif v_cell_team::int = v_owner then
            v_x_ct := v_x_ct + 1;
          else
            v_other_ct := v_other_ct + 1;
          end if;
        end if;
      end loop;

      if v_other_ct = 0 then
        if v_x_ct >= 4 then
          v_score := v_score + c_remove_four;   -- breaking an open-four (or 5)
        elsif v_x_ct = 3 then
          v_score := v_score + c_remove_three;
        end if;
      end if;
    end loop;
  end loop;

  return v_score;
end;
$$;

revoke all on function public.bot_removal_value(jsonb, int, int, int) from public;

----------------------------------------------------------------
-- bot_take_turn — adds (a) a free dead-card swap pre-step, (b) defensive
-- scoring + jack discipline in the candidate pick. Actuator below the
-- pick is unchanged from 8.D.
----------------------------------------------------------------

create or replace function public.bot_take_turn(p_game_id uuid)
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
  v_bot_hand jsonb;
  v_dead_card text;
  v_choice record;
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
  -- Discipline thresholds (named, per CLAUDE.md).
  c_jack_worth   constant numeric := 2000;        -- a two-eyed jack is worth spending at/above this
  c_remove_worth constant numeric := 4000;        -- a one-eyed jack is worth spending at/above this
  c_jack_hold    constant numeric := 1000000000;  -- penalty that effectively hoards the jack
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

  select rp.user_id, rp.team, pr.is_bot
    into v_bot_id, v_bot_team, v_is_bot
  from public.room_players rp
  join public.profiles pr on pr.id = rp.user_id
  where rp.room_id = v_room_id and rp.seat_index = v_turn_seat;

  if v_bot_id is null or coalesce(v_is_bot, false) = false or v_bot_team is null then
    return -1;
  end if;

  v_bot_hand := coalesce(v_hands -> v_bot_id::text, '[]'::jsonb);

  ----------------------------------------------------------------
  -- Free dead-card swap (one per turn): a non-jack whose BOTH board cells
  -- are covered is unplayable — trade it for a fresh draw before moving.
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
      version = v_new_version,
      deck = v_deck,
      discard = v_discard,
      hands = v_hands
    where id = p_game_id;  -- turn NOT advanced; the bot still owes its move

    insert into public.game_moves (game_id, version, user_id, action, card, payload)
    values (p_game_id, v_new_version, v_bot_id, 'swap_dead', v_dead_card,
      jsonb_build_object('team', v_bot_team, 'drew', v_top_card, 'via', 'bot'));

    -- Adopt the post-swap state for the rest of this turn.
    v_version := v_new_version;
    v_bot_hand := v_new_hand;
  end if;

  ----------------------------------------------------------------
  -- Best legal terminal move. Placement = offense + defense. Two-eyed
  -- jacks (wild) and one-eyed jacks (remove) are penalised below their
  -- "worth it" bar so they're hoarded. random() only breaks ties.
  ----------------------------------------------------------------
  select kind, card, r, c
    into v_choice
  from (
    select 'place'::text as kind, h.card as card, r, c,
           public.bot_score_placement(v_board, v_bot_team, r, c)
             + public.bot_opp_four_block(v_board, v_bot_team, r, c) as score
    from jsonb_array_elements_text(v_bot_hand) as h(card)
    cross join generate_series(0, 9) as r
    cross join generate_series(0, 9) as c
    where substring(h.card from 1 for 1) <> 'J'
      and public.card_at(r, c) = h.card
      and ((v_board -> r -> c) ->> 'team') is null

    union all
    select 'wild', h.card, r, c,
           case
             when public.bot_score_placement(v_board, v_bot_team, r, c)
                  + public.bot_opp_four_block(v_board, v_bot_team, r, c)
                  >= c_jack_worth
             then public.bot_score_placement(v_board, v_bot_team, r, c)
                  + public.bot_opp_four_block(v_board, v_bot_team, r, c)
             else public.bot_score_placement(v_board, v_bot_team, r, c)
                  + public.bot_opp_four_block(v_board, v_bot_team, r, c)
                  - c_jack_hold
           end
    from jsonb_array_elements_text(v_bot_hand) as h(card)
    cross join generate_series(0, 9) as r
    cross join generate_series(0, 9) as c
    where h.card in ('JD', 'JC')
      and public.card_at(r, c) is not null
      and ((v_board -> r -> c) ->> 'team') is null

    union all
    select 'remove', h.card, r, c,
           case
             when public.bot_removal_value(v_board, v_bot_team, r, c) >= c_remove_worth
             then public.bot_removal_value(v_board, v_bot_team, r, c)
             else public.bot_removal_value(v_board, v_bot_team, r, c) - c_jack_hold
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
  ) cands
  order by score desc, random()
  limit 1;

  if v_choice.kind is not null then
    v_card := v_choice.card;

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

    if v_choice.kind in ('place', 'wild') then
      v_board := jsonb_set(
        v_board,
        array[v_choice.r::text, v_choice.c::text],
        jsonb_build_object('team', v_bot_team, 'sequence_ids', '[]'::jsonb)
      );

      v_prev_seq_count := jsonb_array_length(v_sequences);
      select rb.new_board, rb.new_sequences into v_rebalanced
      from public.rebalance_board_sequences(v_board) rb;
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
        array[v_choice.r::text, v_choice.c::text],
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
      case when v_choice.kind = 'remove' then 'remove' else 'place' end,
      v_card,
      v_choice.r,
      v_choice.c,
      jsonb_build_object(
        'team', v_bot_team,
        'drew', v_top_card,
        'via', case v_choice.kind
                 when 'wild' then 'bot_wild'
                 when 'remove' then 'bot_remove'
                 else 'bot' end,
        'new_sequences', case when v_choice.kind in ('place', 'wild')
          then greatest(0, jsonb_array_length(v_sequences) - v_prev_seq_count)
          else 0 end,
        'winner_team', v_winner_team
      )
    );

    return v_new_version;
  end if;

  ----------------------------------------------------------------
  -- No legal move — forced discard + advance (mirrors auto_advance_turn).
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
$$;

revoke all on function public.bot_take_turn(uuid) from public;
