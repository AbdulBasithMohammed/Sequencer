-- Perf: cut per-turn latency and game-page boot time.
--
-- 1) broadcast_game_update() — the payload grows from {version} to the full
--    public projection of the games row. Clients apply it straight to local
--    state instead of round-tripping through a Next.js server re-render plus
--    four Supabase queries on every move. Hands stay private: they are never
--    broadcast; each client refetches its own hand via get_my_hand() only
--    when its hand could have changed (it just held the turn).
--    Back-compat: older clients only read payload.version and keep working.
--
-- 2) get_game_snapshot(p_game_id) — single SECURITY DEFINER round trip that
--    returns everything /game/[id] needs to boot: public game fields, the
--    roster, the caller's own hand, and the last placed/removed tile. The
--    page previously needed an auth round trip plus four queries for this.

----------------------------------------------------------------
-- 1) Fat broadcast payload
----------------------------------------------------------------

create or replace function public.broadcast_game_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform realtime.send(
    jsonb_build_object(
      'version', NEW.version,
      'status', NEW.status,
      'board', NEW.board,
      'turn_seat', NEW.turn_seat,
      'turn_deadline', NEW.turn_deadline,
      'winner_team', NEW.winner_team,
      'deck_count', NEW.deck_count,
      'discard_count', coalesce(jsonb_array_length(NEW.discard), 0)
    ),
    'update',
    'game:' || NEW.id::text,
    false
  );
  return NEW;
end;
$$;

----------------------------------------------------------------
-- 2) get_game_snapshot — one round trip for the whole game page
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
    'room_code', v_game.room_code,
    'players', v_players,
    'hand', coalesce(v_game.my_hand, '[]'::jsonb),
    'last_move', v_last_move
  );
end;
$$;

revoke all on function public.get_game_snapshot(uuid) from public;
grant execute on function public.get_game_snapshot(uuid) to authenticated;
