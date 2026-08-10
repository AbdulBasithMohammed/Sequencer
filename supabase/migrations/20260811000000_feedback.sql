-- In-app feedback, with the flood protection in the database.
--
-- Threat model: the anon key ships in the client bundle, so anyone can
-- call submit_feedback directly with curl. Every limit below therefore
-- lives in the function — a disabled button or a maxlength attribute
-- stops nobody.
--
-- Layers, cheapest first:
--   1. auth required            — no anonymous firehose
--   2. 1000 char cap            — bounds a single row
--   3. 60s cooldown per user    — kills hold-enter spam
--   4. 5/hour, 20/day per user  — kills a determined single user
--   5. 500/day globally         — circuit breaker against many accounts
--                                 at once; the only limit that protects
--                                 storage from a coordinated flood
--   6. exact-duplicate block    — stops the same text being resent
--
-- Storage ceiling: 500/day x 30 day retention = 15k rows, and at a
-- realistic ~300 bytes that is ~4.5 MB. Even every row maxed at 1000
-- chars caps out around 15 MB. Set against the 500 MB budget that is
-- bounded and safe, which is the point of limit 5.

create table if not exists public.feedback (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references public.profiles(id) on delete set null,
  -- Denormalised so feedback survives the guest cleanup that deletes the
  -- author 24h after their last sign-in. Guests are exactly the users
  -- most likely to leave a first-impression comment.
  author_name text,
  author_tag  text,
  was_guest   boolean not null default false,
  body        text not null,
  page        text,
  created_at  timestamptz not null default now(),
  constraint feedback_body_length
    check (char_length(trim(body)) between 3 and 1000),
  constraint feedback_page_length
    check (page is null or char_length(page) <= 200)
);

create index if not exists feedback_created_idx
  on public.feedback (created_at desc);
create index if not exists feedback_user_created_idx
  on public.feedback (user_id, created_at desc);

-- RLS on with no policies: no client role can read or write this table
-- directly. The SECURITY DEFINER functions below are the only paths in
-- and out.
alter table public.feedback enable row level security;

----------------------------------------------------------------
-- Submit
----------------------------------------------------------------

create or replace function public.submit_feedback(
  p_body text,
  p_page text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid    uuid := auth.uid();
  v_body   text := trim(coalesce(p_body, ''));
  v_count  int;
  v_name   text;
  v_tag    text;
  v_guest  boolean;
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

  -- 60 second cooldown
  select count(*) into v_count
  from public.feedback
  where user_id = v_uid and created_at > now() - interval '60 seconds';
  if v_count > 0 then
    raise exception 'Give it a minute before sending more feedback'
      using errcode = 'P0001';
  end if;

  -- per-user hourly
  select count(*) into v_count
  from public.feedback
  where user_id = v_uid and created_at > now() - interval '1 hour';
  if v_count >= 5 then
    raise exception 'That is a lot of feedback in one hour — try again later'
      using errcode = 'P0001';
  end if;

  -- per-user daily
  select count(*) into v_count
  from public.feedback
  where user_id = v_uid and created_at > now() - interval '24 hours';
  if v_count >= 20 then
    raise exception 'Daily feedback limit reached — try again tomorrow'
      using errcode = 'P0001';
  end if;

  -- exact duplicate from the same user
  select count(*) into v_count
  from public.feedback
  where user_id = v_uid
    and body = v_body
    and created_at > now() - interval '24 hours';
  if v_count > 0 then
    raise exception 'You already sent that one' using errcode = 'P0001';
  end if;

  -- global circuit breaker: protects storage when many accounts submit
  -- at once, which no per-user limit can catch.
  select count(*) into v_count
  from public.feedback
  where created_at > now() - interval '24 hours';
  if v_count >= 500 then
    raise exception 'Feedback is temporarily closed — try again tomorrow'
      using errcode = 'P0001';
  end if;

  select p.display_name, p.tag, p.is_guest
    into v_name, v_tag, v_guest
  from public.profiles p
  where p.id = v_uid;

  insert into public.feedback (
    user_id, author_name, author_tag, was_guest, body, page
  )
  values (
    v_uid, v_name, v_tag, coalesce(v_guest, false), v_body, left(p_page, 200)
  );
end;
$$;

----------------------------------------------------------------
-- Admin reads
----------------------------------------------------------------

create or replace function public.admin_feedback(p_limit int default 100)
returns table (
  id          uuid,
  author_name text,
  author_tag  text,
  was_guest   boolean,
  body        text,
  page        text,
  created_at  timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.current_user_is_admin() then
    raise exception 'Not authorized' using errcode = '42501';
  end if;

  return query
  select f.id, f.author_name, f.author_tag, f.was_guest,
         f.body, f.page, f.created_at
  from public.feedback f
  order by f.created_at desc
  limit least(greatest(p_limit, 1), 300);
end;
$$;

create or replace function public.admin_feedback_totals()
returns table (
  total       int,
  last_24h    int,
  last_7d     int
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.current_user_is_admin() then
    raise exception 'Not authorized' using errcode = '42501';
  end if;

  return query
  select
    (select count(*) from public.feedback)::int,
    (select count(*) from public.feedback
      where created_at > now() - interval '24 hours')::int,
    (select count(*) from public.feedback
      where created_at > now() - interval '7 days')::int;
end;
$$;

----------------------------------------------------------------
-- Retention: 30 days, swept daily
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
    delete from public.feedback
    where created_at < now() - interval '30 days'
    returning id
  )
  select count(*) into v_deleted from d;
  return v_deleted;
end;
$$;

do $$
declare
  v_jobid bigint;
begin
  for v_jobid in select jobid from cron.job
                 where jobname = 'sequence-delete-old-feedback' loop
    perform cron.unschedule(v_jobid);
  end loop;
  perform cron.schedule(
    'sequence-delete-old-feedback',
    '41 3 * * *',  -- daily, offset from the other sweepers
    $sql$ select public.delete_old_feedback(); $sql$
  );
exception when others then
  raise notice 'Could not (re)schedule sequence-delete-old-feedback: %', sqlerrm;
end;
$$;

revoke all on function public.submit_feedback(text, text) from public;
revoke all on function public.admin_feedback(int)         from public;
revoke all on function public.admin_feedback_totals()     from public;

grant execute on function public.submit_feedback(text, text) to authenticated;
grant execute on function public.admin_feedback(int)         to authenticated;
grant execute on function public.admin_feedback_totals()     to authenticated;
