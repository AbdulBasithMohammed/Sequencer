-- Admin replies to feedback.
--
-- One reply per feedback row, stored on the row itself — not a message
-- table. The player sees it under "Your feedback" in the feedback modal,
-- with an unread dot on the sidebar button until they open it. If they
-- want to answer, they send new feedback with parent_id pointing back, so
-- every player-side write still goes through submit_feedback and all of
-- its limits. The only new write path for players is marking replies
-- seen, which touches nothing but their own rows' reply_seen_at.
--
-- Retention: replied feedback outlives the normal 30 days until the
-- player has had 14 days with the reply after seeing it, capped at 90
-- days after the reply. Guests are swept 24h after their last sign-in,
-- which nulls user_id, so their replies fall back to the 30-day rule.

alter table public.feedback
  add column if not exists parent_id     uuid references public.feedback(id) on delete set null,
  add column if not exists reply_body    text,
  add column if not exists replied_at    timestamptz,
  add column if not exists reply_seen_at timestamptz;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'feedback_reply_length'
  ) then
    alter table public.feedback
      add constraint feedback_reply_length
      check (reply_body is null or char_length(trim(reply_body)) between 1 and 2000);
  end if;
end;
$$;

-- Unread count runs on every app-shell render; keep it an index probe.
create index if not exists feedback_unread_reply_idx
  on public.feedback (user_id)
  where reply_body is not null and reply_seen_at is null;

----------------------------------------------------------------
-- Submit: now accepts an optional parent (a reply to a reply).
-- Adding a parameter would create an overload, so drop the old one.
----------------------------------------------------------------

drop function if exists public.submit_feedback(text, text);

create or replace function public.submit_feedback(
  p_body      text,
  p_page      text default null,
  p_parent_id uuid default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid       uuid := auth.uid();
  v_body      text := trim(coalesce(p_body, ''));
  v_count     int;
  v_name      text;
  v_tag       text;
  v_guest     boolean;
  v_cap_hour  int;
  v_cap_day   int;
begin
  if v_uid is null then
    raise exception 'You need to be signed in to send feedback'
      using errcode = '42501';
  end if;

  if char_length(v_body) < 3 then
    raise exception 'Feedback is too short' using errcode = '22023';
  end if;
  if char_length(v_body) > 1000 then
    raise exception 'Feedback is too long (1000 characters max)'
      using errcode = '22023';
  end if;

  -- A parent must be the caller's own feedback. Otherwise anyone could
  -- thread onto (and so probe the existence of) other players' rows.
  if p_parent_id is not null and not exists (
    select 1 from public.feedback f
    where f.id = p_parent_id and f.user_id = v_uid
  ) then
    raise exception 'That conversation is no longer available'
      using errcode = '22023';
  end if;

  select p.display_name, p.tag, p.is_guest
    into v_name, v_tag, v_guest
  from public.profiles p
  where p.id = v_uid;

  v_guest := coalesce(v_guest, false);
  v_cap_hour := case when v_guest then 2 else 5 end;
  v_cap_day  := case when v_guest then 3 else 20 end;

  select count(*) into v_count
  from public.feedback
  where user_id = v_uid and created_at > now() - interval '60 seconds';
  if v_count > 0 then
    raise exception 'Give it a minute before sending more feedback'
      using errcode = 'P0001';
  end if;

  select count(*) into v_count
  from public.feedback
  where user_id = v_uid and created_at > now() - interval '1 hour';
  if v_count >= v_cap_hour then
    raise exception 'That is a lot of feedback in one hour — try again later'
      using errcode = 'P0001';
  end if;

  select count(*) into v_count
  from public.feedback
  where user_id = v_uid and created_at > now() - interval '24 hours';
  if v_count >= v_cap_day then
    raise exception 'Daily feedback limit reached — try again tomorrow'
      using errcode = 'P0001';
  end if;

  select count(*) into v_count
  from public.feedback
  where user_id = v_uid
    and body = v_body
    and created_at > now() - interval '24 hours';
  if v_count > 0 then
    raise exception 'You already sent that one' using errcode = 'P0001';
  end if;

  select count(*) into v_count
  from public.feedback
  where created_at > now() - interval '24 hours';
  if v_count >= 500 then
    raise exception 'Feedback is temporarily closed — try again tomorrow'
      using errcode = 'P0001';
  end if;

  insert into public.feedback (
    user_id, author_name, author_tag, was_guest, body, page, parent_id
  )
  values (
    v_uid, v_name, v_tag, v_guest, v_body, left(p_page, 200), p_parent_id
  );
end;
$$;

----------------------------------------------------------------
-- Admin read: adds reply state, threading and whether the author
-- still exists. New OUT columns, so drop first (42P13).
----------------------------------------------------------------

drop function if exists public.admin_feedback(int);

create or replace function public.admin_feedback(p_limit int default 100)
returns table (
  id            uuid,
  author_name   text,
  author_tag    text,
  was_guest     boolean,
  body          text,
  page          text,
  created_at    timestamptz,
  author_gone   boolean,
  parent_id     uuid,
  parent_body   text,
  reply_body    text,
  replied_at    timestamptz,
  reply_seen_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or not public.current_user_is_admin() then
    raise exception 'Not authorized' using errcode = '42501';
  end if;

  return query
  select f.id, f.author_name, f.author_tag, f.was_guest,
         f.body, f.page, f.created_at,
         f.user_id is null,
         f.parent_id, left(p.body, 200),
         f.reply_body, f.replied_at, f.reply_seen_at
  from public.feedback f
  left join public.feedback p on p.id = f.parent_id
  order by f.was_guest asc, f.created_at desc
  limit least(greatest(p_limit, 1), 300);
end;
$$;

----------------------------------------------------------------
-- Admin write: set, edit or clear (empty body) the reply.
-- Editing re-notifies: reply_seen_at goes back to null.
----------------------------------------------------------------

create or replace function public.admin_reply_feedback(
  p_id   uuid,
  p_body text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_body text := nullif(trim(coalesce(p_body, '')), '');
  v_user uuid;
begin
  if auth.uid() is null or not public.current_user_is_admin() then
    raise exception 'Not authorized' using errcode = '42501';
  end if;

  if v_body is not null and char_length(v_body) > 2000 then
    raise exception 'Reply is too long (2000 characters max)'
      using errcode = '22023';
  end if;

  select f.user_id into v_user
  from public.feedback f
  where f.id = p_id
  for update;

  if not found then
    raise exception 'Feedback not found' using errcode = 'P0002';
  end if;

  if v_user is null and v_body is not null then
    raise exception 'The author''s account is gone, so they would never see a reply'
      using errcode = 'P0001';
  end if;

  update public.feedback
  set reply_body    = v_body,
      replied_at    = case when v_body is null then null else now() end,
      reply_seen_at = null
  where id = p_id;
end;
$$;

----------------------------------------------------------------
-- Player reads and the seen marker. Own rows only.
----------------------------------------------------------------

create or replace function public.my_feedback()
returns table (
  id            uuid,
  body          text,
  created_at    timestamptz,
  parent_id     uuid,
  reply_body    text,
  replied_at    timestamptz,
  reply_seen_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Not signed in' using errcode = '42501';
  end if;

  return query
  select f.id, f.body, f.created_at, f.parent_id,
         f.reply_body, f.replied_at, f.reply_seen_at
  from public.feedback f
  where f.user_id = auth.uid()
  order by f.created_at desc
  limit 50;
end;
$$;

create or replace function public.my_feedback_unread()
returns int
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    return 0;
  end if;

  return (
    select count(*)::int
    from public.feedback f
    where f.user_id = auth.uid()
      and f.reply_body is not null
      and f.reply_seen_at is null
  );
end;
$$;

create or replace function public.mark_feedback_replies_seen()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'Not signed in' using errcode = '42501';
  end if;

  update public.feedback
  set reply_seen_at = now()
  where user_id = auth.uid()
    and reply_body is not null
    and reply_seen_at is null;
end;
$$;

----------------------------------------------------------------
-- Retention: keep replied rows long enough to be read.
----------------------------------------------------------------

create or replace function public.delete_old_feedback()
returns int
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_deleted int;
begin
  with d as (
    delete from public.feedback f
    where f.created_at < now() - interval '30 days'
      and not (
        f.reply_body is not null
        and f.user_id is not null
        and f.replied_at > now() - interval '90 days'
        and (f.reply_seen_at is null
             or f.reply_seen_at > now() - interval '14 days')
      )
    returning f.id
  )
  select count(*) into v_deleted from d;
  return v_deleted;
end;
$$;

revoke all on function public.submit_feedback(text, text, uuid)      from public;
revoke all on function public.admin_feedback(int)                    from public;
revoke all on function public.admin_reply_feedback(uuid, text)       from public;
revoke all on function public.my_feedback()                          from public;
revoke all on function public.my_feedback_unread()                   from public;
revoke all on function public.mark_feedback_replies_seen()           from public;
-- Cron runs this as postgres; no client role needs it.
revoke all on function public.delete_old_feedback()                  from public, anon, authenticated;

grant execute on function public.submit_feedback(text, text, uuid)   to authenticated;
grant execute on function public.admin_feedback(int)                 to authenticated;
grant execute on function public.admin_reply_feedback(uuid, text)    to authenticated;
grant execute on function public.my_feedback()                       to authenticated;
grant execute on function public.my_feedback_unread()                to authenticated;
grant execute on function public.mark_feedback_replies_seen()        to authenticated;
