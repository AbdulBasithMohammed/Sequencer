-- Fix RLS recursion: both the rooms and room_players SELECT policies subquery
-- room_players, which (with RLS applied) re-enters the same policy. Postgres
-- breaks the recursion by returning empty, so legitimate members can't see
-- their own rooms after creating/joining.
--
-- Standard Supabase fix: a SECURITY DEFINER helper that returns the user's
-- room ids while bypassing RLS. Policies use the helper instead of subquerying
-- the table directly.

create or replace function public.current_user_room_ids()
returns setof uuid
language sql
security definer
stable
set search_path = ''
as $$
  select room_id from public.room_players where user_id = auth.uid();
$$;

grant execute on function public.current_user_room_ids() to authenticated;

drop policy "Members can see their rooms" on public.rooms;
create policy "Members can see their rooms"
  on public.rooms
  for select
  to authenticated
  using (id in (select public.current_user_room_ids()));

drop policy "Members can see room players" on public.room_players;
create policy "Members can see room players"
  on public.room_players
  for select
  to authenticated
  using (room_id in (select public.current_user_room_ids()));
