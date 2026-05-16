-- Realtime: friends-table mutations fan out to user-scoped channels
-- 'friends:<user_id>' so the /friends page can auto-refresh without
-- polling. Matches the existing broadcast-from-database pattern used
-- by rooms/games.

create or replace function public.broadcast_friends_update(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform realtime.send(
    jsonb_build_object('updated_at', extract(epoch from now())),
    'update',
    'friends:' || p_user_id::text,
    false
  );
end;
$$;

----------------------------------------------------------------
-- friend_requests: notify both ends on INSERT or DELETE
----------------------------------------------------------------

create or replace function public.broadcast_friend_requests()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if TG_OP = 'DELETE' then
    perform public.broadcast_friends_update(OLD.from_user);
    perform public.broadcast_friends_update(OLD.to_user);
    return OLD;
  else
    perform public.broadcast_friends_update(NEW.from_user);
    perform public.broadcast_friends_update(NEW.to_user);
    return NEW;
  end if;
end;
$$;

drop trigger if exists broadcast_friend_requests_trigger on public.friend_requests;
create trigger broadcast_friend_requests_trigger
after insert or delete on public.friend_requests
for each row execute function public.broadcast_friend_requests();

----------------------------------------------------------------
-- friendships: notify both ends on INSERT or DELETE
----------------------------------------------------------------

create or replace function public.broadcast_friendships()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if TG_OP = 'DELETE' then
    perform public.broadcast_friends_update(OLD.user_a);
    perform public.broadcast_friends_update(OLD.user_b);
    return OLD;
  else
    perform public.broadcast_friends_update(NEW.user_a);
    perform public.broadcast_friends_update(NEW.user_b);
    return NEW;
  end if;
end;
$$;

drop trigger if exists broadcast_friendships_trigger on public.friendships;
create trigger broadcast_friendships_trigger
after insert or delete on public.friendships
for each row execute function public.broadcast_friendships();

----------------------------------------------------------------
-- friend_ignores: notify only the ignorer
----------------------------------------------------------------

create or replace function public.broadcast_friend_ignores()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if TG_OP = 'DELETE' then
    perform public.broadcast_friends_update(OLD.user_id);
    return OLD;
  else
    perform public.broadcast_friends_update(NEW.user_id);
    return NEW;
  end if;
end;
$$;

drop trigger if exists broadcast_friend_ignores_trigger on public.friend_ignores;
create trigger broadcast_friend_ignores_trigger
after insert or delete on public.friend_ignores
for each row execute function public.broadcast_friend_ignores();
