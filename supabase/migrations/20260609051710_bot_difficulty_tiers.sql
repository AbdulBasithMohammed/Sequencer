-- Phase 8.F — Bot difficulty tiers (rookie / medium / ace).
--
-- One ladder, three toggles read from room_players.bot_difficulty:
--   rookie : offense only (no block term), greedy jacks (no hoard penalty),
--            and per-candidate score noise → makes real mistakes, never
--            defends, wastes jacks.
--   medium : the full 8.E behaviour (offense + defense + jack/dead-card
--            discipline). No noise, no lookahead.
--   ace    : medium scoring + a 1-ply opponent-reply check — its top few
--            candidates are re-ranked by (my score − ½ · opponent's best
--            immediate reply on the resulting board), so it avoids moves
--            that hand the opponent a completion and leans harder into
--            blocking than the static score alone would.
--
-- Also adds set_bot_difficulty so the host can tune each bot in the lobby.

----------------------------------------------------------------
-- set_bot_difficulty(room, seat, difficulty) — host-only, waiting-only.
----------------------------------------------------------------

create or replace function public.set_bot_difficulty(
  p_room_id uuid,
  p_seat int,
  p_difficulty text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller uuid := auth.uid();
  v_room public.rooms;
begin
  if v_caller is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  if p_difficulty not in ('rookie', 'medium', 'ace') then
    raise exception 'Invalid difficulty: %', p_difficulty using errcode = '22023';
  end if;

  select * into v_room from public.rooms where id = p_room_id;
  if not found then
    raise exception 'Room not found' using errcode = 'P0002';
  end if;
  if v_caller <> v_room.host_id then
    raise exception 'Only the host can set bot difficulty' using errcode = '42501';
  end if;
  if v_room.status <> 'waiting' then
    raise exception 'Bots can only be tuned while the room is waiting'
      using errcode = '22023';
  end if;

  update public.room_players rp
  set bot_difficulty = p_difficulty
  from public.profiles pr
  where rp.room_id = p_room_id
    and rp.seat_index = p_seat
    and pr.id = rp.user_id
    and pr.is_bot;

  if not found then
    raise exception 'No bot at seat %', p_seat using errcode = 'P0002';
  end if;
end;
$$;

revoke all on function public.set_bot_difficulty(uuid, int, text) from public;
grant execute on function public.set_bot_difficulty(uuid, int, text) to authenticated;

----------------------------------------------------------------
-- bot_take_turn — difficulty-aware. Swap pre-step + apply body are
-- unchanged from 8.E; the candidate scoring is now tier-dependent and
-- ace adds a bounded 1-ply re-rank.
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
  -- candidate selection
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
  -- named tuning constants
  c_jack_worth   constant numeric := 2000;
  c_remove_worth constant numeric := 4000;
  c_jack_hold    constant numeric := 1000000000;
  c_noise        constant numeric := 300;       -- rookie score jitter
  c_reply        constant numeric := 0.5;        -- ace opponent-reply weight
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
  -- Free dead-card swap (all tiers — it's a pure-upside free action).
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
  -- Gather top-K legal candidates with tier-dependent base scoring.
  -- K = 5 for ace (it re-ranks them), 1 otherwise.
  ----------------------------------------------------------------
  v_topk_n := case when v_difficulty = 'ace' then 5 else 1 end;

  select coalesce(jsonb_agg(c2 order by (c2 ->> 'score')::numeric desc), '[]'::jsonb)
    into v_cands
  from (
    select jsonb_build_object('kind', kind, 'card', card, 'r', r, 'c', c, 'score', score) as c2
    from (
      -- place
      select 'place'::text as kind, h.card as card, r, c,
        case when v_difficulty = 'rookie'
          then public.bot_score_placement(v_board, v_bot_team, r, c) + random() * c_noise
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
      -- wild (two-eyed jack)
      select 'wild', h.card, r, c,
        case when v_difficulty = 'rookie'
          then public.bot_score_placement(v_board, v_bot_team, r, c) + random() * c_noise
          else case when public.bot_score_placement(v_board, v_bot_team, r, c)
                         + public.bot_opp_four_block(v_board, v_bot_team, r, c) >= c_jack_worth
                    then public.bot_score_placement(v_board, v_bot_team, r, c)
                         + public.bot_opp_four_block(v_board, v_bot_team, r, c)
                    else public.bot_score_placement(v_board, v_bot_team, r, c)
                         + public.bot_opp_four_block(v_board, v_bot_team, r, c) - c_jack_hold
               end
        end
      from jsonb_array_elements_text(v_bot_hand) as h(card)
      cross join generate_series(0, 9) as r
      cross join generate_series(0, 9) as c
      where h.card in ('JD', 'JC')
        and public.card_at(r, c) is not null
        and ((v_board -> r -> c) ->> 'team') is null

      union all
      -- remove (one-eyed jack)
      select 'remove', h.card, r, c,
        case when v_difficulty = 'rookie'
          then public.bot_removal_value(v_board, v_bot_team, r, c) + random() * c_noise
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
      -- 1-ply: penalise each candidate by the opponent's best immediate
      -- reply on the resulting board (assume the opponent can play any
      -- empty cell — conservative defense).
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

        v_adj := (v_cand ->> 'score')::numeric - c_reply * v_opp_reply;
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
