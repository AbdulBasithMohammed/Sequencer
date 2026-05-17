-- Test: guest accounts.
--
-- 1. Anonymous auth user → profile.is_guest = true + display_name
--    suffix preserved.
-- 2. Registered users CANNOT friend or invite a guest, and search
--    doesn't return guest rows.
-- 3. Guest accounts CANNOT initiate friend requests or invites.
-- 4. delete_stale_guests respects the 1-hour creation grace AND a
--    24-hour activity TTL.
--
-- Run via Supabase admin API (see swap-dead-card.sql header).

create or replace function public._test_guest_mode_e2e()
returns table(step text, status text, detail text)
language plpgsql
as $$
declare
  v_existing_user uuid;
  v_guest_user uuid;
  v_guest_email text;
  v_room_id uuid;
  v_err text;
  v_guest_profile record;
  v_deleted_count int;
  v_remaining int;
begin
  -- ─── Pick a registered user already in the database ────────────
  select id into v_existing_user
  from public.profiles
  where is_guest = false
  order by created_at
  limit 1;
  if v_existing_user is null then
    step := 'setup'; status := 'FAIL';
    detail := 'no registered profile to test against';
    return next;
    return;
  end if;

  -- ─── Create a mock anonymous user (no SMTP / no email) ─────────
  v_guest_user := gen_random_uuid();
  v_guest_email := v_guest_user::text || '@guest.local';

  -- Insert with is_anonymous = true so the handle_new_user trigger
  -- mirrors it onto profiles.is_guest. raw_user_meta_data must carry
  -- the chosen display_name (matches what supabase.auth.signInAnonymously
  -- sends from the client).
  insert into auth.users (
    id, instance_id, aud, role, email, raw_user_meta_data,
    is_anonymous, encrypted_password, created_at, updated_at
  ) values (
    v_guest_user, '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated',
    v_guest_email,
    jsonb_build_object('display_name', 'TestyMcGuest (Guest)'),
    true, '', now(), now()
  );

  -- Trigger should have populated profiles
  select * into v_guest_profile from public.profiles where id = v_guest_user;
  if v_guest_profile is null then
    step := 'trigger'; status := 'FAIL';
    detail := 'no profile row created for guest';
    delete from auth.users where id = v_guest_user;
    return next;
    return;
  end if;
  if v_guest_profile.is_guest is not true then
    step := 'trigger_is_guest'; status := 'FAIL';
    detail := format('is_guest=%s expected true', v_guest_profile.is_guest);
    delete from auth.users where id = v_guest_user;
    return next;
    return;
  end if;
  if v_guest_profile.display_name <> 'TestyMcGuest (Guest)' then
    step := 'trigger_display_name'; status := 'FAIL';
    detail := format('display_name=%s', v_guest_profile.display_name);
    delete from auth.users where id = v_guest_user;
    return next;
    return;
  end if;
  step := '1_trigger_mirrors_is_anonymous'; status := 'PASS';
  detail := format('guest %s tagged #%s, is_guest=true',
    v_guest_profile.display_name, v_guest_profile.tag);
  return next;

  -- ─── Registered user → friend-request guest: should fail ───────
  perform set_config('request.jwt.claim.sub', v_existing_user::text, true);
  begin
    perform public.send_friend_request(v_guest_user);
    step := '2_register_friend_guest'; status := 'FAIL';
    detail := 'send_friend_request accepted a guest target';
    return next;
  exception
    when sqlstate '42501' then
      step := '2_register_friend_guest'; status := 'PASS';
      detail := sqlerrm;
      return next;
    when others then
      step := '2_register_friend_guest'; status := 'FAIL';
      detail := 'wrong error: ' || sqlerrm;
      return next;
  end;

  -- ─── search_users from registered → guest is excluded ──────────
  if exists (
    select 1 from public.search_users('Testy')
    where user_id = v_guest_user
  ) then
    step := '3_search_excludes_guest'; status := 'FAIL';
    detail := 'guest showed up in search results';
    return next;
  else
    step := '3_search_excludes_guest'; status := 'PASS';
    detail := 'guest absent from search_users results';
    return next;
  end if;

  -- ─── Guest → friend-request registered user: should fail ───────
  perform set_config('request.jwt.claim.sub', v_guest_user::text, true);
  begin
    perform public.send_friend_request(v_existing_user);
    step := '4_guest_friend_register'; status := 'FAIL';
    detail := 'send_friend_request accepted a guest caller';
    return next;
  exception
    when sqlstate '42501' then
      step := '4_guest_friend_register'; status := 'PASS';
      detail := sqlerrm;
      return next;
  end;

  -- ─── search_users from guest returns nothing at all ────────────
  if (select count(*) from public.search_users('a')) <> 0 then
    step := '5_search_blank_for_guest'; status := 'FAIL';
    detail := 'guest got search hits — should be empty';
    return next;
  else
    step := '5_search_blank_for_guest'; status := 'PASS';
    detail := 'search_users returns empty for guest caller';
    return next;
  end if;

  -- ─── invite_to_room targeting a guest: should fail ─────────────
  -- Set up a temp room owned by the registered user, then invite the
  -- guest from there.
  insert into public.rooms (code, host_id, target_players, status, team_layout)
  values ('TESTGM', v_existing_user, 2, 'waiting', 'auto')
  returning id into v_room_id;

  insert into public.room_players (room_id, user_id, seat_index, team, token_color)
  values (v_room_id, v_existing_user, 0, 1, 'pink');

  perform set_config('request.jwt.claim.sub', v_existing_user::text, true);
  begin
    perform public.invite_to_room(v_room_id, v_guest_user);
    step := '6_register_invites_guest'; status := 'FAIL';
    detail := 'invite_to_room accepted a guest target';
    return next;
  exception
    when sqlstate '42501' then
      step := '6_register_invites_guest'; status := 'PASS';
      detail := sqlerrm;
      return next;
  end;

  -- ─── Stale-guest cleanup: fresh guest is NOT deleted ───────────
  v_deleted_count := public.delete_stale_guests();
  select count(*) into v_remaining
  from auth.users where id = v_guest_user;
  if v_remaining = 0 then
    step := '7_fresh_guest_protected'; status := 'FAIL';
    detail := 'cleanup deleted a 0-minute-old guest';
    return next;
  else
    step := '7_fresh_guest_protected'; status := 'PASS';
    detail := format(
      'delete_stale_guests removed %s rows; fresh guest still here',
      v_deleted_count
    );
    return next;
  end if;

  -- ─── Backdate the guest 2 days; cleanup should pick it up ──────
  update auth.users
    set created_at = now() - interval '2 days',
        last_sign_in_at = now() - interval '2 days'
  where id = v_guest_user;

  v_deleted_count := public.delete_stale_guests();
  select count(*) into v_remaining
  from auth.users where id = v_guest_user;
  if v_remaining <> 0 then
    step := '8_stale_guest_deleted'; status := 'FAIL';
    detail := 'cleanup left a 2-day-old guest';
    return next;
  else
    step := '8_stale_guest_deleted'; status := 'PASS';
    detail := format('delete_stale_guests removed %s rows including ours',
      v_deleted_count);
    return next;
  end if;

  -- Profile should be gone via ON DELETE CASCADE
  if exists (select 1 from public.profiles where id = v_guest_user) then
    step := '9_cascade_profile_deleted'; status := 'FAIL';
    detail := 'profile row survived auth.users delete';
    return next;
  else
    step := '9_cascade_profile_deleted'; status := 'PASS';
    detail := 'profile row removed by FK cascade';
    return next;
  end if;

  -- ─── Cleanup leftover test room ────────────────────────────────
  delete from public.rooms where id = v_room_id;
  step := 'cleanup'; status := 'OK'; detail := 'test room deleted';
  return next;
exception
  when others then
    v_err := sqlerrm;
    -- Defensive cleanup
    delete from public.rooms where code = 'TESTGM';
    delete from auth.users where id = v_guest_user;
    step := 'error'; status := 'FAIL'; detail := v_err;
    return next;
end;
$$;

select * from public._test_guest_mode_e2e();
drop function public._test_guest_mode_e2e();
