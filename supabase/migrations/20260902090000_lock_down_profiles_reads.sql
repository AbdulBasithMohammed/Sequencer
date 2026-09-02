-- Stop the profiles table from being a public directory.
--
-- The old policy was:
--
--   create policy "Profiles are viewable by authenticated users"
--     on public.profiles for select to authenticated using (true);
--
-- Any authenticated caller could read every column of every row straight
-- off the REST API. "Authenticated" is the weak part: anonymous sign-in
-- issues a real JWT, so that role is "anyone who clicked Play as guest",
-- not "someone who made an account". The anon key ships in the browser
-- bundle by design, so this needed no exploit — just curl.
--
-- Nothing sensitive was reachable (email and the bcrypt hash live in
-- auth.users, which PostgREST does not expose), but is_admin was, which
-- let anyone enumerate exactly who to go after.
--
-- Two layers here, doing different jobs:
--
--   1. RLS narrowed to the caller's own row. This is the one that
--      matters: it stops anyone reading anybody else's data.
--   2. Column grants, so even your own row only exposes the columns the
--      app actually reads. This is the "don't advertise the schema" half.
--      Note it is cosmetic against anyone who reads the public repo,
--      where every migration is published — obscurity is not the defence
--      here, layer 1 is.
--
-- Safe because nothing reads another user's profile through the table.
-- Verified before writing this:
--   - The only direct client reads are lib/auth/me.ts and
--     auth/welcome/page.tsx, both filtered to .eq("id", user.id).
--   - Rosters, friend search, invites and the admin list all go through
--     SECURITY DEFINER RPCs (search_users, get_lobby_snapshot,
--     get_game_snapshot, get_friends_data, admin_user_list, …), which
--     bypass both RLS and column grants and return narrow projections.
--   - No views depend on the table.

drop policy if exists "Profiles are viewable by authenticated users"
  on public.profiles;

create policy "Users can read their own profile"
  on public.profiles
  for select
  to authenticated
  using (id = (select auth.uid()));

----------------------------------------------------------------
-- Column grants. Same technique already used on public.games to keep
-- hands and deck unreadable (20260515073225) — Postgres enforces column
-- privileges underneath RLS, so this holds even for the owning user.
--
-- Consequence worth remembering: `select=*` against profiles now fails
-- with "permission denied for column". Client reads must name their
-- columns, which both existing call sites already do.
----------------------------------------------------------------

revoke select on public.profiles from authenticated;
revoke select on public.profiles from anon;

grant select (
  id,                      -- needed for the .eq() filter, not just output
  display_name,
  tag,
  created_at,
  is_guest,
  country,
  tour_seen_at,
  tour_skipped,
  coach_marks_done_at,
  feedback_nudge_seen_at
) on public.profiles to authenticated;

-- Deliberately withheld: is_admin (enumerating admins is a phishing
-- shortlist), is_bot, version, team_cursor, target_sequences,
-- bot_difficulty, last_activity_at. Every one of these is already served
-- to the client through an RPC where it is genuinely needed.
