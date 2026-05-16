-- get_invitable_friends returns a TABLE with a user_id column, which
-- shadows the room_players.user_id inside the function body and causes
-- "column reference is ambiguous". Qualify all column references and
-- alias output columns to avoid the conflict.

create or replace function public.get_invitable_friends(p_room_id uuid)
returns table(
  user_id uuid,
  display_name text,
  tag text,
  state text
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
    select 1 from public.room_players rp
    where rp.room_id = p_room_id and rp.user_id = v_caller
  ) then
    raise exception 'You are not in this room' using errcode = '42501';
  end if;

  return query
  select
    f.friend_id as user_id,
    p.display_name,
    p.tag,
    case
      when exists (
        select 1 from public.room_players rp
        where rp.room_id = p_room_id and rp.user_id = f.friend_id
      ) then 'in_room'
      when exists (
        select 1 from public.room_invites ri
        where ri.room_id = p_room_id and ri.to_user = f.friend_id
      ) then 'invited'
      else 'available'
    end::text as state
  from (
    select case when fr.user_a = v_caller then fr.user_b else fr.user_a end as friend_id
    from public.friendships fr
    where fr.user_a = v_caller or fr.user_b = v_caller
  ) f
  join public.profiles p on p.id = f.friend_id
  order by p.display_name;
end;
$$;
