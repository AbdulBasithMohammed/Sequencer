-- Perf: the lobby gets the same client-state treatment as the game.
--
-- 1) broadcast_room_update() — payload grows from {version} to the public
--    lobby projection (room settings + full roster). Clients apply it
--    straight to local state; ready toggles, joins, and seat changes land
--    in one realtime hop instead of a Next.js server re-render.
--    Bans are NOT broadcast: only the host sees them, and only the host's
--    own actions change them (his action response refreshes that list).
--    Back-compat: older clients only read payload.version and keep working.
--
-- 2) get_lobby_snapshot(p_room_id) — member-only reconcile fetch for the
--    self-heal paths (subscribe race / refocus / gap / skinny payload).
--    Includes the live game id so a backgrounded tab that missed the
--    game_started broadcast can still navigate into the game.
--
-- 3) get_game_snapshot() — also return room_id, so the win screen can
--    ready the player up for a rematch without an extra lookup.

----------------------------------------------------------------
-- 1) Fat lobby broadcast payload
----------------------------------------------------------------

create or replace function public.broadcast_room_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_players jsonb;
begin
  select coalesce(
           jsonb_agg(
             jsonb_build_object(
               'seat_index', rp.seat_index,
               'user_id', rp.user_id,
               'team', rp.team,
               'ready', rp.ready,
               'joined_at', rp.joined_at,
               'token_color', rp.token_color,
               'bot_difficulty', rp.bot_difficulty,
               'display_name', p.display_name,
               'is_bot', coalesce(p.is_bot, false)
             )
             order by rp.seat_index
           ),
           '[]'::jsonb
         )
    into v_players
  from public.room_players rp
  left join public.profiles p on p.id = rp.user_id
  where rp.room_id = NEW.id;

  perform realtime.send(
    jsonb_build_object(
      'version', NEW.version,
      'room', jsonb_build_object(
        'id', NEW.id,
        'code', NEW.code,
        'host_id', NEW.host_id,
        'target_players', NEW.target_players,
        'team_layout', NEW.team_layout,
        'status', NEW.status,
        'turn_seconds', NEW.turn_seconds,
        'target_sequences', NEW.target_sequences
      ),
      'players', v_players
    ),
    'update',
    'lobby:' || NEW.id::text,
    false
  );
  return NEW;
end;
$$;

----------------------------------------------------------------
-- 2) get_lobby_snapshot — one round trip for lobby reconciles
----------------------------------------------------------------

create or replace function public.get_lobby_snapshot(p_room_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
stable
as $$
declare
  v_caller uuid := auth.uid();
  v_room public.rooms;
  v_players jsonb;
  v_game_id uuid;
begin
  if v_caller is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  select * into v_room from public.rooms where id = p_room_id;
  if not found then
    return null;
  end if;

  if not exists (
    select 1 from public.room_players
    where room_id = p_room_id and user_id = v_caller
  ) then
    return null;
  end if;

  select coalesce(
           jsonb_agg(
             jsonb_build_object(
               'seat_index', rp.seat_index,
               'user_id', rp.user_id,
               'team', rp.team,
               'ready', rp.ready,
               'joined_at', rp.joined_at,
               'token_color', rp.token_color,
               'bot_difficulty', rp.bot_difficulty,
               'display_name', p.display_name,
               'is_bot', coalesce(p.is_bot, false)
             )
             order by rp.seat_index
           ),
           '[]'::jsonb
         )
    into v_players
  from public.room_players rp
  left join public.profiles p on p.id = rp.user_id
  where rp.room_id = p_room_id;

  select id into v_game_id
  from public.games
  where room_id = p_room_id and status = 'in_game'
  order by started_at desc
  limit 1;

  return jsonb_build_object(
    'version', v_room.version,
    'room', jsonb_build_object(
      'id', v_room.id,
      'code', v_room.code,
      'host_id', v_room.host_id,
      'target_players', v_room.target_players,
      'team_layout', v_room.team_layout,
      'status', v_room.status,
      'turn_seconds', v_room.turn_seconds,
      'target_sequences', v_room.target_sequences
    ),
    'players', v_players,
    'game_id', v_game_id
  );
end;
$$;

revoke all on function public.get_lobby_snapshot(uuid) from public;
grant execute on function public.get_lobby_snapshot(uuid) to authenticated;

----------------------------------------------------------------
-- 3) get_game_snapshot — add room_id (everything else unchanged)
----------------------------------------------------------------

create or replace function public.get_game_snapshot(p_game_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
stable
as $$
declare
  v_caller uuid := auth.uid();
  v_game record;
  v_players jsonb;
  v_last_move jsonb;
begin
  if v_caller is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  select g.id, g.status, g.version, g.board, g.turn_seat, g.turn_deadline,
         g.winner_team, g.room_id, g.deck_count,
         coalesce(jsonb_array_length(g.discard), 0) as discard_count,
         g.hands -> v_caller::text as my_hand,
         r.code as room_code
    into v_game
  from public.games g
  join public.rooms r on r.id = g.room_id
  where g.id = p_game_id;

  if v_game.id is null then
    return null;
  end if;

  -- Same visibility rule as the RLS policy on games: seated players only.
  if not exists (
    select 1 from public.room_players
    where room_id = v_game.room_id and user_id = v_caller
  ) then
    return null;
  end if;

  select coalesce(
           jsonb_agg(
             jsonb_build_object(
               'user_id', rp.user_id,
               'seat_index', rp.seat_index,
               'team', rp.team,
               'display_name', p.display_name,
               'is_bot', coalesce(p.is_bot, false)
             )
             order by rp.seat_index
           ),
           '[]'::jsonb
         )
    into v_players
  from public.room_players rp
  left join public.profiles p on p.id = rp.user_id
  where rp.room_id = v_game.room_id;

  select jsonb_build_object(
           'action', m.action,
           'row', m.tile_row,
           'col', m.tile_col
         )
    into v_last_move
  from public.game_moves m
  where m.game_id = p_game_id
    and m.action in ('place', 'remove')
    and m.tile_row is not null
  order by m.version desc
  limit 1;

  return jsonb_build_object(
    'id', v_game.id,
    'status', v_game.status,
    'version', v_game.version,
    'board', v_game.board,
    'turn_seat', v_game.turn_seat,
    'turn_deadline', v_game.turn_deadline,
    'winner_team', v_game.winner_team,
    'deck_count', v_game.deck_count,
    'discard_count', v_game.discard_count,
    'room_id', v_game.room_id,
    'room_code', v_game.room_code,
    'players', v_players,
    'hand', coalesce(v_game.my_hand, '[]'::jsonb),
    'last_move', v_last_move
  );
end;
$$;
