-- Phase 8.F (part 2) — Make Ace genuinely distinct from Medium.
--
-- Medium already blocks opponent open-FOURS via its static score, so a bare
-- 1-ply check barely changes Ace's single-move picks. Ace's edge is now
-- ANTICIPATION: it also blocks opponent open-THREES (a threat Medium walks
-- past in favour of its own build). That gives a clean, observable tier
-- gap: on the same open-three board, Medium builds, Ace blocks.
--
-- Also hardens the 1-ply re-rank with a completion guard: a candidate that
-- already scores like a completion is never penalised by the opponent
-- reply, so Ace can't ever talk itself out of a winning move.

----------------------------------------------------------------
-- bot_opp_three_block(board, our_team, row, col):
--   Anticipatory defense value of placing OUR chip on empty (row,col):
--   1500 per opponent OPEN-THREE it disrupts (a live window with exactly
--   3 opponent chips/corners, 2 gaps, one of them this cell). Tuned above
--   a typical own open-four (~1080) so Ace prefers disrupting a building
--   opponent over padding its own line. Ace-only.
----------------------------------------------------------------

create or replace function public.bot_opp_three_block(
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
  c_three_block constant numeric := 1500;
  d int; s int; k int;
  sr int; sc int; cr int; cc int;
  v_opp_team int; v_opp_ct int; v_corner_ct int; v_our_ct int; v_empty_ct int;
  v_multi boolean; v_cell_team text; v_is_corner boolean;
  v_count int := 0;
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

      -- open-three: 3 opponent (+corner) chips, exactly one other gap, ours absent
      if v_our_ct = 0 and not v_multi and v_opp_team is not null
         and v_empty_ct = 1 and (v_opp_ct + v_corner_ct) = 3 then
        v_count := v_count + 1;
      end if;
    end loop;
  end loop;

  return v_count * c_three_block;
end;
$$;

revoke all on function public.bot_opp_three_block(jsonb, int, int, int) from public;

----------------------------------------------------------------
-- bot_take_turn — Ace now adds bot_opp_three_block to placement/wild
-- scores; the 1-ply gets a completion guard. Everything else is the
-- 8.F bot_take_turn.
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
$$;

revoke all on function public.bot_take_turn(uuid) from public;
