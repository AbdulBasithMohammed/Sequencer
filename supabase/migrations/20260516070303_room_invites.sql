-- Room invites: anyone in a lobby can invite their friends. Invitees
-- see a notification top-right; accepting joins the lobby, declining
-- (or sender canceling) deletes the row.
--
-- Realtime fan-out:
--   - Recipients listen on 'invites:<user_id>' for incoming/changes
--   - Senders / lobby see the "Invited" state by piggy-backing on the
--     existing rooms.version cascade — any change to room_invites bumps
--     rooms.version which fires the lobby broadcast

----------------------------------------------------------------
-- Table
----------------------------------------------------------------

create table public.room_invites (
  room_id uuid not null references public.rooms(id) on delete cascade,
  from_user uuid not null references public.profiles(id) on delete cascade,
  to_user uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (room_id, to_user),
  check (from_user <> to_user)
);

create index room_invites_to_idx on public.room_invites (to_user);

alter table public.room_invites enable row level security;
create policy "see related invites"
  on public.room_invites for select
  using (
    from_user = (select auth.uid())
    or to_user = (select auth.uid())
  );

----------------------------------------------------------------
-- Cascade: any change to room_invites bumps rooms.version so the
-- lobby channel sees the new "Invited" state
----------------------------------------------------------------

drop trigger if exists bump_rooms_version_on_invites on public.room_invites;
create trigger bump_rooms_version_on_invites
after insert or update or delete on public.room_invites
for each row execute function public.bump_rooms_version_from_child();

----------------------------------------------------------------
-- Personal broadcast to the invitee on insert/delete
----------------------------------------------------------------

create or replace function public.broadcast_room_invites()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_to uuid;
begin
  if TG_OP = 'DELETE' then
    v_to := OLD.to_user;
  else
    v_to := NEW.to_user;
  end if;
  perform realtime.send(
    jsonb_build_object('updated_at', extract(epoch from now())),
    'update',
    'invites:' || v_to::text,
    false
  );
  if TG_OP = 'DELETE' then return OLD; else return NEW; end if;
end;
$$;

drop trigger if exists broadcast_room_invites_trigger on public.room_invites;
create trigger broadcast_room_invites_trigger
after insert or delete on public.room_invites
for each row execute function public.broadcast_room_invites();

----------------------------------------------------------------
-- invite_to_room — caller must be in the room AND friends with target
----------------------------------------------------------------

create or replace function public.invite_to_room(
  p_room_id uuid,
  p_to_user uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_from uuid := auth.uid();
  v_min uuid;
  v_max uuid;
  v_room public.rooms;
  v_player_count int;
begin
  if v_from is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  if v_from = p_to_user then
    raise exception 'Cannot invite yourself' using errcode = '22023';
  end if;

  -- Caller must be a member of the room
  if not exists (
    select 1 from public.room_players
    where room_id = p_room_id and user_id = v_from
  ) then
    raise exception 'You are not in this room' using errcode = '42501';
  end if;

  select * into v_room from public.rooms where id = p_room_id;
  if not found then
    raise exception 'Room not found' using errcode = 'P0002';
  end if;
  if v_room.status <> 'waiting' then
    raise exception 'Room is no longer accepting invites' using errcode = 'P0001';
  end if;

  v_min := least(v_from, p_to_user);
  v_max := greatest(v_from, p_to_user);
  if not exists (
    select 1 from public.friendships
    where user_a = v_min and user_b = v_max
  ) then
    raise exception 'You are not friends with this user' using errcode = '42501';
  end if;

  -- Invitee already in the room: silent no-op
  if exists (
    select 1 from public.room_players
    where room_id = p_room_id and user_id = p_to_user
  ) then
    return;
  end if;

  -- Invitee is banned from this room: refuse
  if exists (
    select 1 from public.room_bans
    where room_id = p_room_id and user_id = p_to_user
  ) then
    raise exception 'User is banned from this room' using errcode = '42501';
  end if;

  select count(*) into v_player_count
  from public.room_players where room_id = p_room_id;
  if v_player_count >= v_room.target_players then
    raise exception 'Room is full' using errcode = 'P0001';
  end if;

  -- (room_id, to_user) is the PK — a second invite from a different
  -- friend just no-ops
  insert into public.room_invites (room_id, from_user, to_user)
  values (p_room_id, v_from, p_to_user)
  on conflict (room_id, to_user) do nothing;
end;
$$;

----------------------------------------------------------------
-- accept_room_invite — validate invite + same seat-assignment logic
-- as join_room
----------------------------------------------------------------

create or replace function public.accept_room_invite(p_room_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_room public.rooms;
  v_player_count int;
  v_next_seat int;
begin
  if v_user is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.room_invites
    where room_id = p_room_id and to_user = v_user
  ) then
    raise exception 'No invite for this room' using errcode = 'P0002';
  end if;

  delete from public.room_invites
    where room_id = p_room_id and to_user = v_user;

  -- Race: already a member somehow → idempotent return
  if exists (
    select 1 from public.room_players
    where room_id = p_room_id and user_id = v_user
  ) then
    return p_room_id;
  end if;

  select * into v_room from public.rooms where id = p_room_id;
  if not found then
    raise exception 'Room not found' using errcode = 'P0002';
  end if;
  if v_room.status <> 'waiting' then
    raise exception 'Room is no longer accepting players' using errcode = 'P0001';
  end if;
  if exists (
    select 1 from public.room_bans
    where room_id = p_room_id and user_id = v_user
  ) then
    raise exception 'You are banned from this room' using errcode = '42501';
  end if;

  select count(*) into v_player_count
  from public.room_players where room_id = p_room_id;
  if v_player_count >= v_room.target_players then
    raise exception 'Room is full' using errcode = 'P0001';
  end if;

  select s into v_next_seat
  from generate_series(0, v_room.target_players - 1) as g(s)
  where not exists (
    select 1 from public.room_players rp
    where rp.room_id = p_room_id and rp.seat_index = g.s
  )
  order by s limit 1;

  insert into public.room_players (room_id, user_id, seat_index, team, token_color)
  values (
    p_room_id,
    v_user,
    v_next_seat,
    public.compute_team(v_next_seat, v_room.target_players, v_room.team_layout),
    public.default_token_color(v_next_seat)
  );

  return p_room_id;
end;
$$;

----------------------------------------------------------------
-- decline_room_invite
----------------------------------------------------------------

create or replace function public.decline_room_invite(p_room_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  delete from public.room_invites
    where room_id = p_room_id and to_user = v_user;
end;
$$;

----------------------------------------------------------------
-- get_my_room_invites — pending invites for the caller
----------------------------------------------------------------

create or replace function public.get_my_room_invites()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    return '[]'::jsonb;
  end if;

  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'room_id', ri.room_id,
      'room_code', r.code,
      'from_user_id', ri.from_user,
      'from_display_name', p.display_name,
      'from_tag', p.tag,
      'target_players', r.target_players,
      'created_at', ri.created_at
    ) order by ri.created_at desc)
    from public.room_invites ri
    join public.rooms r on r.id = ri.room_id
    join public.profiles p on p.id = ri.from_user
    where ri.to_user = v_user
      and r.status = 'waiting'
  ), '[]'::jsonb);
end;
$$;

----------------------------------------------------------------
-- get_invitable_friends — caller's friends + their state for THIS room
----------------------------------------------------------------

create or replace function public.get_invitable_friends(p_room_id uuid)
returns table(
  user_id uuid,
  display_name text,
  tag text,
  state text  -- 'in_room' | 'invited' | 'available'
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_caller uuid := auth.uid();
begin
  if v_caller is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  if not exists (
    select 1 from public.room_players
    where room_id = p_room_id and user_id = v_caller
  ) then
    raise exception 'You are not in this room' using errcode = '42501';
  end if;

  return query
  select
    f.friend_id,
    p.display_name,
    p.tag,
    case
      when exists (
        select 1 from public.room_players
        where room_id = p_room_id and user_id = f.friend_id
      ) then 'in_room'
      when exists (
        select 1 from public.room_invites
        where room_id = p_room_id and to_user = f.friend_id
      ) then 'invited'
      else 'available'
    end::text
  from (
    select case when user_a = v_caller then user_b else user_a end as friend_id
    from public.friendships
    where user_a = v_caller or user_b = v_caller
  ) f
  join public.profiles p on p.id = f.friend_id
  order by p.display_name;
end;
$$;

grant execute on function public.invite_to_room(uuid, uuid) to authenticated;
grant execute on function public.accept_room_invite(uuid) to authenticated;
grant execute on function public.decline_room_invite(uuid) to authenticated;
grant execute on function public.get_my_room_invites() to authenticated;
grant execute on function public.get_invitable_friends(uuid) to authenticated;
