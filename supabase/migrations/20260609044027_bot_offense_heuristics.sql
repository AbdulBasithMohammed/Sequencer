-- Phase 8.D — Bot offense heuristics. Replaces 8.C's random terminal-move
-- selection with a scored one. The ladder (win-now → complete-sequence →
-- double-threat → build-strongest-line) is encoded by the magnitudes of
-- the window weights, so a single ORDER BY score DESC realises it:
--
--   complete (>=5 live)         100000   -- also wins when at threshold
--   2 open-fours (double-threat)  2000    -- = 2 x open-four, naturally ranks
--   open-four (4 live, 1 gap)     1000       between complete and build
--   open-three (3 live)             30
--   pair (2 live)                    8
--   lone live chip                   2
--   + positional (windows * 0.1)        -- nudges ties toward central cells
--
-- Defense (blocking opponent fours), one-eyed-jack targeting, two-eyed-jack
-- discipline and dead-card swap are 8.E — so here removal scores a flat
-- floor (used only when nothing can be placed) and a two-eyed jack is just
-- scored as the best cell it can reach.

----------------------------------------------------------------
-- bot_score_placement(board, team, row, col):
--   Value to `team` of placing a chip at (row,col), via length-5 window
--   analysis. Corners count as every team's chip; a window containing any
--   opponent chip is dead (0). (row,col) is assumed empty + non-corner
--   (the only candidates the driver scores).
----------------------------------------------------------------

create or replace function public.bot_score_placement(
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
  -- 4 directions: horizontal, vertical, diag ↘, diag ↙
  v_dr int[] := array[0, 1, 1, 1];
  v_dc int[] := array[1, 0, 1, -1];
  c_complete  constant numeric := 100000;
  c_open_four constant numeric := 1000;
  c_three     constant numeric := 30;
  c_two       constant numeric := 8;
  c_one       constant numeric := 2;
  c_position  constant numeric := 0.1;
  d int; s int; k int;
  sr int; sc int; cr int; cc int;
  v_team_ct int; v_opp_ct int;
  v_cell_team text; v_is_corner boolean;
  v_score numeric := 0;
  v_windows int := 0;
begin
  for d in 1..4 loop
    -- Every length-5 window containing (row,col) starts 0..4 cells "before"
    -- it along this direction.
    for s in 0..4 loop
      sr := p_row - s * v_dr[d];
      sc := p_col - s * v_dc[d];
      -- Both endpoints in-bounds ⇒ the whole straight window is in-bounds.
      if sr < 0 or sr > 9 or sc < 0 or sc > 9 then
        continue;
      end if;
      if (sr + 4 * v_dr[d]) < 0 or (sr + 4 * v_dr[d]) > 9
         or (sc + 4 * v_dc[d]) < 0 or (sc + 4 * v_dc[d]) > 9 then
        continue;
      end if;

      v_team_ct := 0;
      v_opp_ct := 0;
      for k in 0..4 loop
        cr := sr + k * v_dr[d];
        cc := sc + k * v_dc[d];
        v_is_corner := (cr = 0 or cr = 9) and (cc = 0 or cc = 9);
        if cr = p_row and cc = p_col then
          v_team_ct := v_team_ct + 1;           -- the new chip
        elsif v_is_corner then
          v_team_ct := v_team_ct + 1;           -- corner: free for all teams
        else
          v_cell_team := (p_board -> cr -> cc) ->> 'team';
          if v_cell_team is null then
            null;                               -- empty
          elsif v_cell_team::int = p_team then
            v_team_ct := v_team_ct + 1;
          else
            v_opp_ct := v_opp_ct + 1;
          end if;
        end if;
      end loop;

      v_windows := v_windows + 1;
      if v_opp_ct = 0 then
        v_score := v_score + case
          when v_team_ct >= 5 then c_complete
          when v_team_ct = 4 then c_open_four
          when v_team_ct = 3 then c_three
          when v_team_ct = 2 then c_two
          else c_one
        end;
      end if;
    end loop;
  end loop;

  return v_score + v_windows * c_position;
end;
$$;

revoke all on function public.bot_score_placement(jsonb, int, int, int) from public;

----------------------------------------------------------------
-- bot_take_turn — same actuator as 8.C, but the candidate pick is now
-- ORDER BY score DESC, random() (random only breaks ties). Place/wild are
-- scored by bot_score_placement; remove gets a flat floor (8.E makes it
-- smart). Everything below the candidate query is unchanged from 8.C.
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
  c_remove_floor constant numeric := 1;
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
  -- Best-scoring legal terminal move (random only on ties).
  ----------------------------------------------------------------
  select kind, card, r, c
    into v_choice
  from (
    select 'place'::text as kind, h.card as card, r, c,
           public.bot_score_placement(v_board, v_bot_team, r, c) as score
    from jsonb_array_elements_text(v_bot_hand) as h(card)
    cross join generate_series(0, 9) as r
    cross join generate_series(0, 9) as c
    where substring(h.card from 1 for 1) <> 'J'
      and public.card_at(r, c) = h.card
      and ((v_board -> r -> c) ->> 'team') is null

    union all
    select 'wild', h.card, r, c,
           public.bot_score_placement(v_board, v_bot_team, r, c)
    from jsonb_array_elements_text(v_bot_hand) as h(card)
    cross join generate_series(0, 9) as r
    cross join generate_series(0, 9) as c
    where h.card in ('JD', 'JC')
      and public.card_at(r, c) is not null
      and ((v_board -> r -> c) ->> 'team') is null

    union all
    select 'remove', h.card, r, c, c_remove_floor
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
