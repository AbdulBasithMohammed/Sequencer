-- Public lookup for the /join/<CODE> landing page.
--
-- The rooms table is RLS-locked to members only (good — we don't want
-- random people browsing rooms by guessing UUIDs). But /join needs to
-- render a "this room is full / in-game / banned" notice even for
-- signed-out visitors, so we expose a SECURITY DEFINER RPC that returns
-- only joinability fields — never the room id or anything sensitive.
--
-- The ban check requires the caller's uid; anonymous callers always see
-- is_banned = false (they're not signed in yet).

create or replace function public.room_join_info(p_code text)
returns table (
  exists_ boolean,
  status text,
  target_players int,
  seated int,
  is_full boolean,
  is_banned boolean
)
language plpgsql
security definer
stable
set search_path = ''
as $$
declare
  v_code text := upper(trim(p_code));
  v_room public.rooms;
  v_seated int;
  v_banned boolean := false;
  v_user uuid := auth.uid();
begin
  select * into v_room from public.rooms where code = v_code;
  if not found then
    return query select false, null::text, null::int, null::int, null::boolean, null::boolean;
    return;
  end if;

  select count(*) into v_seated
  from public.room_players where room_id = v_room.id;

  if v_user is not null then
    select exists (
      select 1 from public.room_bans
      where room_id = v_room.id and user_id = v_user
    ) into v_banned;
  end if;

  return query select
    true,
    v_room.status,
    v_room.target_players,
    v_seated,
    v_seated >= v_room.target_players,
    v_banned;
end;
$$;

grant execute on function public.room_join_info(text) to anon, authenticated;
