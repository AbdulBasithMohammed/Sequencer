-- Phase 8.C — Bot turn driver (random-legal).
--
-- A bot never authenticates and never calls a play RPC. Like
-- auto_advance_turn, a server-side function acts on its behalf, driven by
-- pg_cron. bot_take_turn() picks a UNIFORMLY RANDOM legal terminal move
-- (place / wild / remove) for the bot seated at the current turn and
-- applies it with the same mutation logic the human RPCs use (shared
-- helpers: card_at, rebalance_board_sequences, win_threshold,
-- next_turn_seat). If the bot has no legal move at all it forced-discards
-- and advances (mirrors auto_advance_turn) so the game can never wedge.
--
-- Smart play — line scoring, blocking, jack discipline, dead-card swap —
-- lands in 8.D/8.E. This step only proves the actuator: a bot seat takes
-- real turns automatically and everyone sees it via realtime.

----------------------------------------------------------------
-- Think delay: how long after its turn starts a bot waits before moving,
-- so play feels natural and humans can watch. Named constant per CLAUDE.md.
----------------------------------------------------------------

create or replace function public.bot_think_seconds()
returns int
language sql
immutable
set search_path = ''
as $$ select 2 $$;

----------------------------------------------------------------
-- bot_take_turn(game) — act as the bot at the current seat.
-- Returns the new version, or -1 if it's not a bot's turn / no-op.
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

  -- The seat whose turn it is must be a bot.
  select rp.user_id, rp.team, pr.is_bot
    into v_bot_id, v_bot_team, v_is_bot
  from public.room_players rp
  join public.profiles pr on pr.id = rp.user_id
  where rp.room_id = v_room_id and rp.seat_index = v_turn_seat;

  if v_bot_id is null or coalesce(v_is_bot, false) = false or v_bot_team is null then
    return -1;  -- not a (well-formed) bot turn; leave it alone
  end if;

  v_bot_hand := coalesce(v_hands -> v_bot_id::text, '[]'::jsonb);

  ----------------------------------------------------------------
  -- 1) Pick a uniformly random legal terminal move.
  --    place  : non-jack onto a matching empty cell
  --    wild   : two-eyed jack (JD/JC) onto any empty non-corner cell
  --    remove : one-eyed jack (JS/JH) onto an opponent chip not yet in a
  --             completed sequence
  ----------------------------------------------------------------
  select kind, card, r, c
    into v_choice
  from (
    select 'place'::text as kind, h.card as card, r, c
    from jsonb_array_elements_text(v_bot_hand) as h(card)
    cross join generate_series(0, 9) as r
    cross join generate_series(0, 9) as c
    where substring(h.card from 1 for 1) <> 'J'
      and public.card_at(r, c) = h.card
      and ((v_board -> r -> c) ->> 'team') is null

    union all
    select 'wild', h.card, r, c
    from jsonb_array_elements_text(v_bot_hand) as h(card)
    cross join generate_series(0, 9) as r
    cross join generate_series(0, 9) as c
    where h.card in ('JD', 'JC')
      and public.card_at(r, c) is not null
      and ((v_board -> r -> c) ->> 'team') is null

    union all
    select 'remove', h.card, r, c
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
  order by random()
  limit 1;

  if v_choice.kind is not null then
    v_card := v_choice.card;

    -- Pull the chosen card (first occurrence) out of the hand.
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
      -- remove: clear the opponent's cell
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
  -- 2) No legal move at all (astronomically rare: every non-jack dead,
  --    no two-eyed jack, one-eyed jacks have no target). Forced discard +
  --    advance, exactly like auto_advance_turn — never wedge.
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

----------------------------------------------------------------
-- tick_bot_turns — find in_game games whose current seat is a bot and
-- whose think delay has elapsed, and move for them. Think delay is
-- measured from turn start (= turn_deadline - turn_seconds), so a bot
-- always acts well before its AFK deadline. Capped per tick.
----------------------------------------------------------------

create or replace function public.tick_bot_turns()
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_game record;
  v_count int := 0;
begin
  for v_game in
    select g.id
    from public.games g
    join public.rooms r on r.id = g.room_id
    join public.room_players rp
      on rp.room_id = g.room_id and rp.seat_index = g.turn_seat
    join public.profiles pr on pr.id = rp.user_id
    where g.status = 'in_game'
      and pr.is_bot
      and g.turn_deadline is not null
      and now() >= g.turn_deadline
                   - (r.turn_seconds || ' seconds')::interval
                   + (public.bot_think_seconds() || ' seconds')::interval
    order by g.turn_deadline
    limit 50
  loop
    perform public.bot_take_turn(v_game.id);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

revoke all on function public.tick_bot_turns() from public;

----------------------------------------------------------------
-- Schedule the bot tick every 2 seconds (snappier than the 5s AFK tick
-- so bot moves feel responsive). Idempotent across re-runs.
----------------------------------------------------------------

do $$
declare
  v_jobid bigint;
begin
  for v_jobid in select jobid from cron.job where jobname = 'sequence-tick-bots' loop
    perform cron.unschedule(v_jobid);
  end loop;
  perform cron.schedule(
    'sequence-tick-bots',
    '2 seconds',
    $sql$ select public.tick_bot_turns(); $sql$
  );
exception when others then
  raise notice 'Could not (re)schedule sequence-tick-bots: %', sqlerrm;
end;
$$;
