-- Phase 3.E (post-3 follow-up) — Realtime: Broadcast-from-Database.
--
-- Replaces `postgres_changes` (deprecated by Supabase: single-thread RLS
-- dispatch, throttled aggressively on mobile WebSockets, drops events
-- under load) with Broadcast-from-Database. A Postgres trigger fires on
-- the mutation and calls `realtime.send()` with a tiny payload ({version}).
-- Clients subscribe to the named channel and refetch authoritative state
-- via the same RLS-protected SELECT they already use.
--
-- We also wire monotonic versions through the lobby chain:
--   - rooms.version is bumped on every UPDATE (auto, via BEFORE trigger)
--   - room_players + room_bans changes bump rooms.version too (via AFTER
--     triggers), which cascades into the rooms broadcast
--   - games.version was already there from Phase 3.A
--
-- Payload is non-sensitive ({version}); the real game/room state stays
-- behind RLS — clients re-SELECT after each broadcast.

----------------------------------------------------------------
-- 1) rooms.version — monotonic version for the lobby state
----------------------------------------------------------------

alter table public.rooms
  add column if not exists version int not null default 0;

----------------------------------------------------------------
-- 2) auto-bump rooms.version on every UPDATE that doesn't already
--    move it forward (so direct status-only updates also bump)
----------------------------------------------------------------

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
  return NEW;
end;
$$;

drop trigger if exists auto_bump_room_version_trigger on public.rooms;
create trigger auto_bump_room_version_trigger
before update on public.rooms
for each row
execute function public.auto_bump_room_version();

----------------------------------------------------------------
-- 3) Cascade: any change on room_players / room_bans bumps the
--    parent rooms.version (which then fires the broadcast trigger)
----------------------------------------------------------------

create or replace function public.bump_rooms_version_from_child()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_room_id uuid;
begin
  if TG_OP = 'DELETE' then
    v_room_id := OLD.room_id;
  else
    v_room_id := NEW.room_id;
  end if;
  update public.rooms set version = version + 1 where id = v_room_id;
  if TG_OP = 'DELETE' then
    return OLD;
  else
    return NEW;
  end if;
end;
$$;

drop trigger if exists bump_rooms_version_on_players on public.room_players;
create trigger bump_rooms_version_on_players
after insert or update or delete on public.room_players
for each row
execute function public.bump_rooms_version_from_child();

drop trigger if exists bump_rooms_version_on_bans on public.room_bans;
create trigger bump_rooms_version_on_bans
after insert or update or delete on public.room_bans
for each row
execute function public.bump_rooms_version_from_child();

----------------------------------------------------------------
-- 4) Broadcast triggers — call realtime.send() with the new
--    version on every meaningful mutation
----------------------------------------------------------------

create or replace function public.broadcast_room_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform realtime.send(
    jsonb_build_object('version', NEW.version),
    'update',
    'lobby:' || NEW.id::text,
    false
  );
  return NEW;
end;
$$;

drop trigger if exists broadcast_room_update_trigger on public.rooms;
create trigger broadcast_room_update_trigger
after update on public.rooms
for each row
when (NEW.version is distinct from OLD.version)
execute function public.broadcast_room_update();

create or replace function public.broadcast_game_update()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform realtime.send(
    jsonb_build_object('version', NEW.version),
    'update',
    'game:' || NEW.id::text,
    false
  );
  return NEW;
end;
$$;

drop trigger if exists broadcast_game_update_trigger on public.games;
create trigger broadcast_game_update_trigger
after update on public.games
for each row
when (NEW.version is distinct from OLD.version)
execute function public.broadcast_game_update();
