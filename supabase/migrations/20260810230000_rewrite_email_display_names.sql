-- Remove email addresses that are sitting in public display names.
--
-- Two accounts signed up while the form carried autoComplete="username",
-- so the browser autofilled their email into the display name field. That
-- name renders in lobbies, player lists and friend search, exposing their
-- address to every other player.
--
-- 20260810180000 blocked new occurrences and added the CHECK constraint
-- NOT VALID so those two rows were grandfathered. This rewrites them and
-- validates the constraint.
--
-- Deliberately pattern-matched rather than targeting the two rows by
-- address: this repo is public, so hardcoding the emails here would
-- republish exactly what the migration exists to remove.
--
-- Rewrite rule: keep the local part, drop the @domain — the closest
-- thing to their chosen name that is no longer an email. Falls back to
-- Player #tag if the local part cannot satisfy the 3–30 char constraint,
-- so this cannot fail partway and leave the constraint unvalidatable.

update public.profiles p
set display_name = case
  when char_length(trim(split_part(p.display_name, '@', 1))) between 3 and 30
    then trim(split_part(p.display_name, '@', 1))
  else 'Player ' || coalesce(p.tag, 'user')
end
where p.display_name ~* '^[^@[:space:]]+@[^@[:space:]]+\.[a-z]{2,}$';

-- No rows can violate it now, so the constraint becomes fully enforced
-- rather than applying only to new writes.
alter table public.profiles
  validate constraint display_name_not_email;
