-- Fix: 20260516021802 redefined create_room but accidentally dropped the
-- team-assignment logic that lobby_polish (20260514100702) had added.
-- Result: hosts were inserted into room_players with team=null, so the
-- lobby UI couldn't place them in Team 1 / Team 2 cards. Restore that
-- logic AND keep the 9-player support.

create or replace function public.create_room(p_target_players int)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_room_id uuid;
  v_code text;
  v_attempts int := 0;
  v_layout text;
begin
  if v_user_id is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  if p_target_players not in (2, 3, 4, 6, 8, 9, 10, 12) then
    raise exception 'Invalid player count: %', p_target_players
      using errcode = '22023';
  end if;

  v_layout := public.default_layout_for(p_target_players);

  loop
    v_code := public.generate_room_code();
    begin
      insert into public.rooms (code, host_id, target_players, team_layout)
      values (v_code, v_user_id, p_target_players, v_layout)
      returning id into v_room_id;
      exit;
    exception when unique_violation then
      v_attempts := v_attempts + 1;
      if v_attempts > 10 then
        raise exception 'Could not generate a unique room code'
          using errcode = 'P0001';
      end if;
    end;
  end loop;

  insert into public.room_players (room_id, user_id, seat_index, team)
  values (
    v_room_id,
    v_user_id,
    0,
    public.compute_team(0, p_target_players, v_layout)
  );

  return v_code;
end;
$$;
