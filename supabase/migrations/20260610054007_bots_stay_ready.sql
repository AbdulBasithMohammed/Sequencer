-- Fix: bots stay ready across games.
--
-- reset_room_on_game_finish cleared ready for ALL room_players, bots
-- included — but a bot can never re-ready itself (the ready toggle is
-- caller-scoped and bots don't call RPCs), so after one finished game the
-- host had to remove and re-add every bot. Re-readying is a human
-- ceremony; bots are always willing. Clear only human seats.

create or replace function public.reset_room_on_game_finish()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if NEW.status = 'finished' and (OLD.status is distinct from 'finished') then
    update public.rooms set status = 'waiting' where id = NEW.room_id;
    update public.room_players rp
       set ready = false
     where rp.room_id = NEW.room_id
       and not exists (
         select 1 from public.profiles p
         where p.id = rp.user_id and p.is_bot
       );
  end if;
  return NEW;
end;
$$;

-- Repair pass: re-ready any bot seats stranded unready by the old
-- behaviour (rooms whose game already finished before this fix).
update public.room_players rp
   set ready = true
  from public.profiles p
 where p.id = rp.user_id
   and p.is_bot
   and rp.ready = false;
