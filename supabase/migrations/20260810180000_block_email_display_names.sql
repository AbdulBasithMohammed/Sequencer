-- Reject email addresses as display names.
--
-- The signup form carried autoComplete="username" on the display name
-- field, so browsers autofilled the saved email address and users
-- submitted it without noticing. Two accounts ended up with their email
-- as their public handle, visible in lobbies, player lists and friend
-- search. The form attribute is fixed (autoComplete="nickname"), but the
-- database should not depend on the client getting it right.

----------------------------------------------------------------
-- 1) Signup trigger rejects it outright
----------------------------------------------------------------

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text := new.raw_user_meta_data->>'display_name';
begin
  -- Anonymous sign-ups must still pass a nickname in the metadata.
  if v_name is null or char_length(trim(v_name)) < 3 then
    raise exception 'Sign-up requires display_name (>= 3 chars)';
  end if;

  if trim(v_name) ~* '^[^@[:space:]]+@[^@[:space:]]+\.[a-z]{2,}$' then
    raise exception 'Display name cannot be an email address'
      using errcode = '22023';
  end if;

  insert into public.profiles (id, display_name, tag, is_guest)
  values (
    new.id,
    v_name,
    public.generate_profile_tag(),
    coalesce(new.is_anonymous, false)
  );
  return new;
end;
$$;

----------------------------------------------------------------
-- 2) Constraint so it also cannot be set by a later profile update.
--
--    NOT VALID: two existing rows already violate this. Adding a
--    validated constraint would fail outright, and rewriting someone's
--    public handle without asking them is not this migration's call.
--    NOT VALID enforces the rule on every INSERT and UPDATE from here
--    on while grandfathering those two rows. Once they're renamed:
--
--      alter table public.profiles
--        validate constraint display_name_not_email;
----------------------------------------------------------------

alter table public.profiles
  drop constraint if exists display_name_not_email;

alter table public.profiles
  add constraint display_name_not_email
    check (display_name !~* '^[^@[:space:]]+@[^@[:space:]]+\.[a-z]{2,}$')
    not valid;
