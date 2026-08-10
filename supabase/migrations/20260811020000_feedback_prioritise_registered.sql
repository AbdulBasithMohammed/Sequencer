-- Treat registered feedback as the signal and guest feedback as noise.
--
-- Two changes, same reasoning from opposite ends:
--
--   Limits — guests are the cheap abuse vector. An anonymous sign-in
--   costs nothing, so per-user caps barely constrain someone willing to
--   churn accounts. Giving guests the same 20/day as a registered user
--   is generous to precisely the account type that is free to create.
--   Guests now get 3/day and 2/hour; registered users keep 20/day and
--   5/hour. The 60s cooldown, duplicate block and 500/day global
--   circuit breaker are unchanged and still apply to everyone.
--
--   Ordering — registered feedback sorts first so it is never buried
--   under guest comments, which are read at low priority. Within each
--   group it stays newest-first.
--
-- Guests keep the ability to submit: first-impression feedback from
-- someone who never registered is often the most revealing kind, and
-- the comment survives the account being swept 24h later.

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

  select p.display_name, p.tag, p.is_guest
    into v_name, v_tag, v_guest
  from public.profiles p
  where p.id = v_uid;

  v_guest := coalesce(v_guest, false);
  v_cap_hour := case when v_guest then 2 else 5 end;
  v_cap_day  := case when v_guest then 3 else 20 end;

  -- 60 second cooldown
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
    user_id, author_name, author_tag, was_guest, body, page
  )
  values (v_uid, v_name, v_tag, v_guest, v_body, left(p_page, 200));
end;
$$;

-- Registered first, newest-first within each group.
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
  order by f.was_guest asc, f.created_at desc
  limit least(greatest(p_limit, 1), 300);
end;
$$;

revoke all on function public.submit_feedback(text, text) from public;
grant execute on function public.submit_feedback(text, text) to authenticated;
