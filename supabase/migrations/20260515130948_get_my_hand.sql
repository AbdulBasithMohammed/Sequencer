-- Phase 3.D — get_my_hand(p_game_id) returns the caller's own hand cards
-- as text[]. SECURITY DEFINER so it can read games.hands (which is blocked
-- to clients via the column-level GRANT layer set up in 3.A).
--
-- Only returns the caller's slice of games.hands; never another player's.
-- Caller must be a seated player in the room of this game.

create or replace function public.get_my_hand(p_game_id uuid)
returns text[]
language plpgsql
security definer
set search_path = ''
stable
as $$
declare
  v_caller uuid := auth.uid();
  v_room_id uuid;
  v_hand jsonb;
begin
  if v_caller is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  select room_id, hands -> v_caller::text
    into v_room_id, v_hand
  from public.games
  where id = p_game_id;

  if v_room_id is null then
    raise exception 'Game not found' using errcode = 'P0002';
  end if;

  if not exists (
    select 1 from public.room_players
    where room_id = v_room_id and user_id = v_caller
  ) then
    raise exception 'Not a player in this game' using errcode = '42501';
  end if;

  if v_hand is null then
    return array[]::text[];
  end if;

  return array(select jsonb_array_elements_text(v_hand));
end;
$$;

revoke all on function public.get_my_hand(uuid) from public;
grant execute on function public.get_my_hand(uuid) to authenticated;
