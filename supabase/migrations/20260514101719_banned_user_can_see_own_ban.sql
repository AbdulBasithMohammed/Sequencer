-- Let a banned user see their own ban row. The lobby refresher needs this to
-- distinguish a ban from an ordinary kick when both produce a DELETE on
-- room_players. The host-only SELECT policy from the previous migration
-- remains in effect; Postgres ORs multiple SELECT policies.

create policy "Users can see their own ban rows"
  on public.room_bans
  for select
  to authenticated
  using (user_id = auth.uid());
