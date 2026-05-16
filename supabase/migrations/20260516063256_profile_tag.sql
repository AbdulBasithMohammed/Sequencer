-- Per-user 6-char alphanumeric tag (Discord-style discriminator).
-- Format matches room codes (A-Z0-9, uppercase). Globally unique so it
-- can stably identify a user across display-name changes — used by
-- the upcoming friends feature.

----------------------------------------------------------------
-- 1) Generator. Random 6-char retry until unique. 36^6 = ~2.18B
--    keyspace, collisions are essentially impossible at our scale.
----------------------------------------------------------------

create or replace function public.generate_profile_tag()
returns text
language plpgsql
volatile
set search_path = ''
as $$
declare
  v_chars text := 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
  v_tag text;
  v_attempts int := 0;
begin
  loop
    v_tag := '';
    for v_i in 1..6 loop
      v_tag := v_tag || substr(v_chars, 1 + floor(random() * 36)::int, 1);
    end loop;
    if not exists (select 1 from public.profiles where tag = v_tag) then
      return v_tag;
    end if;
    v_attempts := v_attempts + 1;
    if v_attempts > 100 then
      raise exception 'Could not generate unique profile tag after 100 attempts';
    end if;
  end loop;
end;
$$;

----------------------------------------------------------------
-- 2) Add the column nullable, backfill row-by-row (so the uniqueness
--    check inside generate_profile_tag sees each prior commit), then
--    enforce NOT NULL + format + unique.
----------------------------------------------------------------

alter table public.profiles add column if not exists tag text;

do $$
declare
  v_row record;
begin
  for v_row in select id from public.profiles where tag is null loop
    update public.profiles
       set tag = public.generate_profile_tag()
     where id = v_row.id;
  end loop;
end;
$$;

alter table public.profiles alter column tag set not null;

alter table public.profiles
  add constraint profile_tag_format check (tag ~ '^[A-Z0-9]{6}$');

create unique index if not exists profiles_tag_idx on public.profiles (tag);

----------------------------------------------------------------
-- 3) Signup trigger now also assigns a tag.
----------------------------------------------------------------

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name, tag)
  values (
    new.id,
    new.raw_user_meta_data->>'display_name',
    public.generate_profile_tag()
  );
  return new;
end;
$$;
