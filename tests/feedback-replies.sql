-- Test: admin replies to feedback, across a guest's whole lifecycle.
--
-- 1. Guest sends feedback; admin replies; guest sees it as unread.
-- 2. Guest follows up (parent_id) and marks replies seen; an admin edit
--    makes it unread again.
-- 3. Guest account is deleted (the same `delete from auth.users` that
--    delete_stale_guests runs): feedback rows survive with user_id null,
--    reply intact, and admin_feedback reports author_gone.
-- 4. Admin can't reply to a gone author, but can clear the reply.
-- 5. A new guest can't see or thread onto the orphaned rows.
-- 6. Retention: orphaned replied rows fall back to 30 days; a live
--    registered author's unseen reply is kept; one seen >14 days ago goes.
-- 7. delete_old_feedback isn't executable by client roles.
--
-- Leaves nothing behind: every write happens inside a block that ends by
-- raising, which rolls the block back; results are carried out in an
-- array. The outer BEGIN/ROLLBACK also discards the helper function.
-- Needs at least one profile with is_admin = true.
--
--   npx supabase@2 db query --linked -f tests/feedback-replies.sql

begin;

create function public._test_feedback_replies()
returns table(step text, status text, detail text)
language plpgsql
as $$
declare
  r        text[] := '{}';
  v_admin  uuid;
  v_guest  uuid := gen_random_uuid();
  v_guest2 uuid := gen_random_uuid();
  v_fb     uuid;
  v_follow uuid;
  v_reg    uuid;
  v_n      int;
  v_row    record;
  v_err    text;

begin
  select id into v_admin from public.profiles where is_admin limit 1;
  if v_admin is null then
    return query select 'setup', 'FAIL', 'no admin profile to act as';
    return;
  end if;

  begin
    -- ── guest ────────────────────────────────────────────────────
    insert into auth.users (
      id, instance_id, aud, role, email, raw_user_meta_data,
      is_anonymous, encrypted_password, created_at, updated_at,
      last_sign_in_at
    ) values (
      v_guest, '00000000-0000-0000-0000-000000000000',
      'authenticated', 'authenticated', v_guest::text || '@guest.local',
      jsonb_build_object('display_name', 'FeedbackTest (Guest)'),
      true, '', now() - interval '2 days', now(), now() - interval '2 days'
    );

    -- 1. submit + reply + unread
    perform set_config('request.jwt.claim.sub', v_guest::text, true);
    perform public.submit_feedback('test feedback from a guest', '/play');
    select id into v_fb from public.feedback
      where user_id = v_guest order by created_at desc limit 1;
    -- clear the 60s cooldown for the follow-up below
    update public.feedback set created_at = now() - interval '2 minutes'
      where id = v_fb;

    perform set_config('request.jwt.claim.sub', v_admin::text, true);
    perform public.admin_reply_feedback(v_fb, '  thanks, fixed  ');

    perform set_config('request.jwt.claim.sub', v_guest::text, true);
    v_n := public.my_feedback_unread();
    select * into v_row from public.my_feedback() where id = v_fb;
    r := r || array['1_reply_visible_unread',
      case when v_n = 1 and v_row.reply_body = 'thanks, fixed' then 'PASS' else 'FAIL' end,
      format('unread=%s reply=%L', v_n, v_row.reply_body)];

    -- 2. follow-up, mark seen, edit re-notifies
    perform public.submit_feedback('a follow-up from the guest', '/play', v_fb);
    select id into v_follow from public.feedback
      where user_id = v_guest and parent_id = v_fb;
    perform public.mark_feedback_replies_seen();
    v_n := public.my_feedback_unread();
    r := r || array['2a_follow_up_and_seen',
      case when v_follow is not null and v_n = 0 then 'PASS' else 'FAIL' end,
      format('follow_up=%s unread_after_seen=%s', v_follow is not null, v_n)];

    perform set_config('request.jwt.claim.sub', v_admin::text, true);
    perform public.admin_reply_feedback(v_fb, 'edited reply');
    perform set_config('request.jwt.claim.sub', v_guest::text, true);
    v_n := public.my_feedback_unread();
    r := r || array['2b_edit_renotifies',
      case when v_n = 1 then 'PASS' else 'FAIL' end, format('unread=%s', v_n)];

    -- 3. guest expires (same statement shape as delete_stale_guests)
    delete from auth.users where id = v_guest;
    select count(*) into v_n from public.feedback
      where id in (v_fb, v_follow) and user_id is null;
    select * into v_row from public.feedback where id = v_fb;
    r := r || array['3a_rows_survive_guest_delete',
      case when v_n = 2 and v_row.reply_body = 'edited reply'
                and (select parent_id from public.feedback where id = v_follow) = v_fb
           then 'PASS' else 'FAIL' end,
      format('orphaned_rows=%s reply=%L', v_n, v_row.reply_body)];

    perform set_config('request.jwt.claim.sub', v_admin::text, true);
    select count(*) into v_n from public.admin_feedback(300) a
      where a.id in (v_fb, v_follow) and a.author_gone;
    r := r || array['3b_admin_sees_author_gone',
      case when v_n = 2 then 'PASS' else 'FAIL' end, format('author_gone=%s', v_n)];

    -- 4. reply to gone author refused; clearing allowed
    begin
      perform public.admin_reply_feedback(v_follow, 'hello?');
      r := r || array['4a_reply_to_gone_refused', 'FAIL', 'reply was accepted'];
    exception when others then
      r := r || array['4a_reply_to_gone_refused', 'PASS', sqlerrm];
    end;
    perform public.admin_reply_feedback(v_fb, '');
    r := r || array['4b_clear_reply_on_gone_author',
      case when (select reply_body from public.feedback where id = v_fb) is null
           then 'PASS' else 'FAIL' end, 'reply cleared'];
    perform public.admin_reply_feedback(v_fb, ''); -- idempotent
    update public.feedback set reply_body = 'edited reply', replied_at = now()
      where id = v_fb; -- restore for the retention check

    -- 5. a new guest can't see or adopt the orphans
    insert into auth.users (
      id, instance_id, aud, role, email, raw_user_meta_data,
      is_anonymous, encrypted_password, created_at, updated_at
    ) values (
      v_guest2, '00000000-0000-0000-0000-000000000000',
      'authenticated', 'authenticated', v_guest2::text || '@guest.local',
      jsonb_build_object('display_name', 'FeedbackTest2 (Guest)'),
      true, '', now(), now()
    );
    perform set_config('request.jwt.claim.sub', v_guest2::text, true);
    select count(*) into v_n from public.my_feedback();
    r := r || array['5a_new_guest_sees_nothing',
      case when v_n = 0 and public.my_feedback_unread() = 0 then 'PASS' else 'FAIL' end,
      format('rows=%s', v_n)];
    begin
      perform public.submit_feedback('trying to thread onto an orphan', '/play', v_fb);
      r := r || array['5b_cannot_thread_onto_orphan', 'FAIL', 'accepted'];
    exception when others then
      r := r || array['5b_cannot_thread_onto_orphan', 'PASS', sqlerrm];
    end;

    -- 6. retention
    insert into public.feedback (user_id, author_name, body, created_at,
                                 reply_body, replied_at, reply_seen_at)
    values (v_admin, 'retention test', 'live author, unseen reply',
            now() - interval '31 days', 'kept', now() - interval '20 days', null)
    returning id into v_reg;
    insert into public.feedback (user_id, author_name, body, created_at,
                                 reply_body, replied_at, reply_seen_at)
    values (v_admin, 'retention test', 'live author, seen long ago',
            now() - interval '40 days', 'gone', now() - interval '30 days',
            now() - interval '15 days');
    update public.feedback set created_at = now() - interval '31 days'
      where id in (v_fb, v_follow);

    perform public.delete_old_feedback();
    r := r || array['6a_orphaned_replied_rows_reaped_at_30d',
      case when not exists (select 1 from public.feedback where id in (v_fb, v_follow))
           then 'PASS' else 'FAIL' end, 'orphans deleted'];
    r := r || array['6b_live_unseen_reply_kept',
      case when exists (select 1 from public.feedback where id = v_reg)
           then 'PASS' else 'FAIL' end, 'kept past 30 days'];
    r := r || array['6c_seen_14d_ago_reaped',
      case when not exists (select 1 from public.feedback
                            where body = 'live author, seen long ago')
           then 'PASS' else 'FAIL' end, 'deleted'];

    -- 7. reaper not callable by clients
    r := r || array['7_reaper_not_client_callable',
      case when not has_function_privilege('anon', 'public.delete_old_feedback()', 'execute')
            and not has_function_privilege('authenticated', 'public.delete_old_feedback()', 'execute')
           then 'PASS' else 'FAIL' end, 'anon/authenticated lack EXECUTE'];

    raise exception 'ROLLBACK_SENTINEL';
  exception when others then
    if sqlerrm <> 'ROLLBACK_SENTINEL' then
      r := r || array['error', 'FAIL', sqlerrm];
    end if;
  end;

  for i in 1 .. coalesce(array_length(r, 1), 0) / 3 loop
    step := r[i*3-2]; status := r[i*3-1]; detail := r[i*3];
    return next;
  end loop;
end;
$$;

select * from public._test_feedback_replies();

rollback;
