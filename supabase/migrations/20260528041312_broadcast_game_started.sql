-- Phase 3.E follow-up — broadcast `game_started` on lobby:<room_id> when
-- a new game row is inserted. Before this, the non-host's lobby relied
-- on a `postgres_changes` INSERT subscription on `games` to learn the
-- new game id and navigate to /game/<id>. postgres_changes is the slow
-- path (single-thread RLS dispatch, mobile WebSocket throttling, event
-- drops under load) and caused a 5-10s lag for the second player on
-- their first move — they were still sitting in the lobby while the
-- host was already in-game. The rooms-status broadcast did fire, but
-- its {version}-only payload required a server-side re-render +
-- redirect roundtrip, which races with SSR data freshness.
--
-- This broadcast carries the game id directly so the client can navigate
-- on the same fast channel it already uses for lobby updates.

create or replace function public.broadcast_game_started()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform realtime.send(
    jsonb_build_object('game_id', NEW.id::text),
    'game_started',
    'lobby:' || NEW.room_id::text,
    false
  );
  return NEW;
end;
$$;

drop trigger if exists broadcast_game_started_trigger on public.games;
create trigger broadcast_game_started_trigger
after insert on public.games
for each row
execute function public.broadcast_game_started();
