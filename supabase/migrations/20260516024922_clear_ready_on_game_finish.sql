-- 7.A.1 — When a game finishes, also clear all room_players.ready so the
-- lobby requires everyone to re-ready before the host can restart.
--
-- Extends the existing reset_room_on_game_finish trigger (which already
-- flips rooms.status back to 'waiting').

create or replace function public.reset_room_on_game_finish()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if NEW.status = 'finished' and (OLD.status is distinct from 'finished') then
    update public.rooms set status = 'waiting' where id = NEW.room_id;
    update public.room_players set ready = false where room_id = NEW.room_id;
  end if;
  return NEW;
end;
$$;
