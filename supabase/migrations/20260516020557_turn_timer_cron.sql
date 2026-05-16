-- Phase 6.A — Per-turn timer + pg_cron auto-advance.
--
-- When a player's turn_deadline passes, auto-discard their top card (per
-- PRD invariant), draw a replacement, and advance the turn. A pg_cron
-- job ticks every 5 seconds and calls tick_expired_turns(), which finds
-- every in_game games row whose deadline has passed and rolls the turn
-- forward via auto_advance_turn().
--
-- The Postgres broadcast trigger from 3.E fires on the games row UPDATE,
-- so every connected client sees the auto-advance within a beat.

----------------------------------------------------------------
-- Enable pg_cron (idempotent — ignored if already on, or if the
-- environment doesn't permit it).
----------------------------------------------------------------

do $$
begin
  create extension if not exists pg_cron;
exception when others then
  raise notice 'pg_cron not available: %', sqlerrm;
end;
$$;

----------------------------------------------------------------
-- auto_advance_turn — runs on a single game row.
-- Returns the new version, or -1 if no-op (not expired / not in game).
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
  v_current_player_id uuid;
  v_current_hand jsonb;
  v_discarded_card text;
  v_top_card text;
  v_new_hand jsonb;
  v_next_seat int;
  v_new_version int;
begin
  select room_id, status, version, turn_seat, turn_deadline, deck, discard, hands
    into v_room_id, v_status, v_version, v_turn_seat, v_turn_deadline, v_deck, v_discard, v_hands
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
    select coalesce(
      (select min(seat_index) from public.room_players
         where room_id = v_room_id and seat_index > v_turn_seat),
      (select min(seat_index) from public.room_players
         where room_id = v_room_id)
    ) into v_next_seat;

    v_new_version := v_version + 1;
    update public.games set
      version = v_new_version,
      turn_seat = v_next_seat,
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

  select coalesce(
    (select min(seat_index) from public.room_players
       where room_id = v_room_id and seat_index > v_turn_seat),
    (select min(seat_index) from public.room_players
       where room_id = v_room_id)
  ) into v_next_seat;

  v_new_version := v_version + 1;

  update public.games set
    version = v_new_version,
    deck = v_deck,
    discard = v_discard,
    hands = v_hands,
    turn_seat = v_next_seat,
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

----------------------------------------------------------------
-- tick_expired_turns — find all expired-deadline games and roll
-- them forward. Caps at 100 games per tick to keep latency bounded.
----------------------------------------------------------------

create or replace function public.tick_expired_turns()
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
    select id from public.games
    where status = 'in_game' and turn_deadline < now()
    order by turn_deadline
    limit 100
  loop
    perform public.auto_advance_turn(v_game.id);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

----------------------------------------------------------------
-- Schedule the cron tick — every 5 seconds. Idempotent across
-- migration re-runs by un-scheduling any prior job with this name.
----------------------------------------------------------------

do $$
declare
  v_jobid bigint;
begin
  for v_jobid in select jobid from cron.job where jobname = 'sequence-tick-turns' loop
    perform cron.unschedule(v_jobid);
  end loop;
  perform cron.schedule(
    'sequence-tick-turns',
    '5 seconds',
    $sql$ select public.tick_expired_turns(); $sql$
  );
exception when others then
  raise notice 'Could not (re)schedule sequence-tick-turns: %', sqlerrm;
end;
$$;
