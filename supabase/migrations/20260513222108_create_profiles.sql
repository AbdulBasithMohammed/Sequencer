-- profiles table: 1:1 with auth.users, holds the public display name.
-- A signup trigger auto-creates a profile row from the metadata passed to supabase.auth.signUp().

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  created_at timestamptz not null default now(),
  constraint display_name_length
    check (char_length(trim(display_name)) between 3 and 20)
);

create unique index profiles_display_name_lower_idx
  on public.profiles (lower(display_name));

alter table public.profiles enable row level security;

create policy "Profiles are viewable by authenticated users"
  on public.profiles
  for select
  to authenticated
  using (true);

create policy "Users can update their own profile"
  on public.profiles
  for update
  to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);

-- INSERT and DELETE are intentionally not policied — the trigger below is the
-- only path that creates a profile, and rows are cleaned up by ON DELETE CASCADE.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, new.raw_user_meta_data->>'display_name');
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
