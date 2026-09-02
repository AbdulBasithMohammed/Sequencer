-- One-time onboarding: a site tour, first-game rules coaching, and a
-- post-game feedback nudge.
--
-- Four flags rather than a table. Onboarding is per-account, write-once,
-- and read on nearly every app render, so it belongs on the row we
-- already fetch — a separate table would mean a second query per page
-- load to learn something that is null forever after the first day.
-- Cost is ~17 bytes per profile with no new rows to reap.
--
-- Guests get the same flags. They vanish with the account at the 24h
-- guest reap, which is the correct semantics: a "returning" guest is a
-- new person on a new session and should see the tour again.
--
-- Deliberately NOT stored: which individual coach marks fired. That is
-- per-game UI state the client tracks in memory; persisting it would be
-- four more columns to learn nothing useful.

alter table public.profiles
  add column if not exists tour_seen_at           timestamptz,
  add column if not exists tour_skipped           boolean not null default false,
  add column if not exists coach_marks_done_at    timestamptz,
  add column if not exists feedback_nudge_seen_at timestamptz;

----------------------------------------------------------------
-- mark_onboarding — the only write path.
--
-- Set-once on every step: replaying the tour from /me is allowed to
-- show the UI again, but it must not reset the timestamps the admin
-- funnel is counting, and a double-fire from a re-render must be a
-- no-op. The allowlist means a tampered client can only ever flip one
-- of four known booleans on its own row — the anon key is public, so
-- "the client passes a column name" would be a write primitive.
----------------------------------------------------------------

create or replace function public.mark_onboarding(p_step text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    return;  -- signed out: nothing to record, and not an error
  end if;

  case p_step
    when 'tour_done' then
      update public.profiles
      set tour_seen_at = now()
      where id = v_uid and tour_seen_at is null;

    when 'tour_skipped' then
      -- Same completion timestamp, plus the flag that separates "read it"
      -- from "dismissed it" in the funnel. Without the split, a 100%
      -- completion rate and a 100% skip rate look identical.
      update public.profiles
      set tour_seen_at = now(),
          tour_skipped = true
      where id = v_uid and tour_seen_at is null;

    when 'coach_done' then
      update public.profiles
      set coach_marks_done_at = now()
      where id = v_uid and coach_marks_done_at is null;

    when 'nudge_seen' then
      update public.profiles
      set feedback_nudge_seen_at = now()
      where id = v_uid and feedback_nudge_seen_at is null;

    else
      raise exception 'Unknown onboarding step: %', p_step
        using errcode = '22023';
  end case;
end;
$$;

revoke all on function public.mark_onboarding(text) from public;
grant execute on function public.mark_onboarding(text) to authenticated;

----------------------------------------------------------------
-- Admin funnel. A new function rather than extra OUT columns on
-- admin_overview: changing that row type needs a DROP first (42P13),
-- and this is a separate concern with its own card on the page.
--
-- Bots are excluded throughout — they have profiles and would otherwise
-- count as players who never took the tour.
----------------------------------------------------------------

create or replace function public.admin_onboarding()
returns table (
  eligible        int,
  tour_seen       int,
  tour_skipped    int,
  coach_done      int,
  nudge_seen      int
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.current_user_is_admin() then
    raise exception 'Not authorized' using errcode = '42501';
  end if;

  return query
  select
    count(*)                                          filter (where not p.is_bot)::int,
    count(*) filter (where not p.is_bot and p.tour_seen_at is not null)::int,
    count(*) filter (where not p.is_bot and p.tour_skipped)::int,
    count(*) filter (where not p.is_bot and p.coach_marks_done_at is not null)::int,
    count(*) filter (where not p.is_bot and p.feedback_nudge_seen_at is not null)::int
  from public.profiles p;
end;
$$;

revoke all on function public.admin_onboarding() from public;
grant execute on function public.admin_onboarding() to authenticated;
