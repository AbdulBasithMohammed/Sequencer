-- get_my_stats — aggregate the caller's gameplay stats from existing
-- tables. Live aggregation, no materialized table. Cheap at our scale:
-- room_players is indexed by user_id, game_moves by (user_id, game_id),
-- games joins via room_id. Sub-10ms for thousands of games per user.

create or replace function public.get_my_stats()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_games_played bigint := 0;
  v_games_won bigint := 0;
  v_moves_played bigint := 0;
  v_total_seconds bigint := 0;
begin
  if v_user is null then
    return jsonb_build_object(
      'games_played', 0,
      'games_won', 0,
      'moves_played', 0,
      'total_seconds', 0
    );
  end if;

  select count(*) into v_games_played
  from public.games g
  join public.room_players rp on rp.room_id = g.room_id
  where rp.user_id = v_user;

  select count(*) into v_games_won
  from public.games g
  join public.room_players rp on rp.room_id = g.room_id
  where rp.user_id = v_user
    and g.status = 'finished'
    and g.winner_team is not null
    and rp.team = g.winner_team;

  select count(*) into v_moves_played
  from public.game_moves
  where user_id = v_user
    and action in ('place', 'remove', 'swap_dead');

  select coalesce(
    sum(
      extract(epoch from coalesce(g.finished_at, now()) - g.started_at)
    )::bigint,
    0
  ) into v_total_seconds
  from public.games g
  join public.room_players rp on rp.room_id = g.room_id
  where rp.user_id = v_user
    and g.started_at is not null;

  return jsonb_build_object(
    'games_played', v_games_played,
    'games_won', v_games_won,
    'moves_played', v_moves_played,
    'total_seconds', v_total_seconds
  );
end;
$$;

grant execute on function public.get_my_stats() to authenticated;
