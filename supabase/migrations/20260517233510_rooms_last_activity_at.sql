-- Track activity (any meaningful RPC touching the room) on rooms so the
-- stale-cleanup cron can distinguish "lobby with an idle tab open" from
-- "lobby someone is actively poking at". Bumped automatically by the
-- existing auto_bump_room_version trigger, which runs BEFORE UPDATE on
-- rooms — so direct updates AND cascades from room_players /
-- room_invites / room_bans all carry the timestamp forward.
--
-- delete_stale_rooms switches its time check from created_at to
-- last_activity_at:
--   - empty room   → 5 min of no activity (someone left, nobody came back)
--   - orphan room  → 5 min of no activity (no game, no edits)
--   - waiting room → 24 h of no activity (host left a tab open and went home)

alter table public.rooms
  add column if not exists last_activity_at timestamptz not null default now();

create index if not exists rooms_last_activity_idx
  on public.rooms (last_activity_at);

-- Extend the existing version-bump trigger to also stamp last_activity_at.
-- BEFORE UPDATE → setting NEW fields works without a second UPDATE.
create or replace function public.auto_bump_room_version()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if NEW.version = OLD.version then
    NEW.version := OLD.version + 1;
  end if;
  NEW.last_activity_at := now();
  return NEW;
end;
$$;

create or replace function public.delete_stale_rooms()
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_deleted int;
begin
  with d as (
    delete from public.rooms r
    where
      (
        -- empty room, idle for 5 min
        not exists (
          select 1 from public.room_players where room_id = r.id
        )
        and r.last_activity_at < now() - interval '5 minutes'
      )
      or
      (
        -- in_game flag but no live game, idle for 5 min
        r.status = 'in_game'
        and not exists (
          select 1 from public.games
          where room_id = r.id and status = 'in_game'
        )
        and r.last_activity_at < now() - interval '5 minutes'
      )
      or
      (
        -- waiting room, no activity for 24 h (catches the
        -- "tab-open-and-forgotten" case)
        r.status = 'waiting'
        and r.last_activity_at < now() - interval '24 hours'
      )
    returning id
  )
  select count(*) into v_deleted from d;
  return v_deleted;
end;
$$;
