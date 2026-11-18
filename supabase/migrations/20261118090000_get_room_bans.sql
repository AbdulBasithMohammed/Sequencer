-- get_room_bans: the host's banned-players list, with names.
--
-- The lobby page used to read room_bans directly and embed
-- profiles(display_name). Since 20260902090000 profiles SELECT is own-row
-- only, so the embed came back null for every banned player and the host
-- saw a ban list with no names. Same fix as the lobby roster: a narrow
-- SECURITY DEFINER projection rather than widening the profiles grant.
--
-- Host-only. Anyone else gets 42501, matching the admin_* RPCs. Only
-- display_name crosses over, never the rest of the profile.

create or replace function public.get_room_bans(p_room_id uuid)
returns table(
  user_id uuid,
  display_name text,
  banned_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_caller uuid := auth.uid();
begin
  if v_caller is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.rooms r
    where r.id = p_room_id and r.host_id = v_caller
  ) then
    raise exception 'Only the host can view bans' using errcode = '42501';
  end if;

  return query
  select b.user_id, p.display_name, b.banned_at
  from public.room_bans b
  left join public.profiles p on p.id = b.user_id
  where b.room_id = p_room_id
  order by b.banned_at desc;
end;
$$;

revoke all on function public.get_room_bans(uuid) from public;
grant execute on function public.get_room_bans(uuid) to authenticated;
