-- Goliath rulebook (2023) allows 9-player games (3 teams of 3) at 4 cards
-- each. Phase 3.B's hand_size only listed 2/3/4/6/8/10/12, so start_game
-- rejected 9-player rooms. This migration fills in the missing row.

create or replace function public.hand_size(p_player_count int)
returns int
language sql
immutable
set search_path = ''
as $$
  select case p_player_count
    when 2  then 7
    when 3  then 6
    when 4  then 6
    when 6  then 5
    when 8  then 4
    when 9  then 4
    when 10 then 3
    when 12 then 3
    else null
  end;
$$;
