-- Perf: retire the app's last postgres_changes subscription.
--
-- The lobby channel kept a postgres_changes binding on room_players DELETE
-- solely so a kicked/banned player could detect their own removal and be
-- redirected with the right toast. postgres_changes is the deprecated slow
-- path (single-threaded per-subscriber RLS dispatch) and adding it to a
-- channel also slows the SUBSCRIBE handshake for everyone in the lobby.
--
-- A Broadcast trigger carries the same fact on the fast path: every
-- room_players DELETE announces the removed user_id on lobby:<room_id>.
-- (Roster refreshes were already covered by the rooms.version "update"
-- broadcast; this event exists for the "was it me?" check.)

create or replace function public.broadcast_player_removed()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform realtime.send(
    jsonb_build_object('user_id', OLD.user_id::text),
    'player_removed',
    'lobby:' || OLD.room_id::text,
    false
  );
  return OLD;
end;
$$;

drop trigger if exists broadcast_player_removed_trigger on public.room_players;
create trigger broadcast_player_removed_trigger
after delete on public.room_players
for each row
execute function public.broadcast_player_removed();
