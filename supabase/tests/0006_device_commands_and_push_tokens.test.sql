\i supabase/tests/_helpers.sql

begin;

-- fixtures: re-insert Task 1's two parent auth users + one child auth user,
-- since each test file runs in its own transaction and Task 1's own test
-- file rolled its fixtures back. Inserted as postgres (bypasses RLS), which
-- is the role this script connects as before any test.assume_user() switch
-- below.
insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'edson@example.com'),
  ('22222222-2222-2222-2222-222222222222', 'esposa@example.com'),
  ('33333333-3333-3333-3333-333333333333', 'vitor-device@example.com');
insert into parents (user_id, full_name) values
  ('11111111-1111-1111-1111-111111111111', 'Edson'),
  ('22222222-2222-2222-2222-222222222222', 'Esposa');
insert into children (id, device_user_id, full_name, birthdate) values
  ('44444444-4444-4444-4444-444444444444', '33333333-3333-3333-3333-333333333333', 'Vitor', '2019-01-01');

-- a parent (Edson) can insert a 'lock' command for his child, with
-- requested_by set to his own auth.uid(), per
-- device_commands_insert_for_parents's with check (is_parent() and
-- requested_by = auth.uid()).
select test.assume_user('11111111-1111-1111-1111-111111111111');
insert into device_commands (id, child_id, command_type, requested_by) values
  ('55555555-5555-5555-5555-555555555555', '44444444-4444-4444-4444-444444444444', 'lock', '11111111-1111-1111-1111-111111111111');

-- the same parent cannot insert a command with requested_by set to the
-- OTHER parent's (Esposa's) user_id, even though Esposa is a real parent
-- row -- device_commands_insert_for_parents's with check requires
-- requested_by = auth.uid() of the inserting user specifically.
do $$
begin
  perform test.assume_user('11111111-1111-1111-1111-111111111111');
  insert into device_commands (child_id, command_type, requested_by) values
    ('44444444-4444-4444-4444-444444444444', 'lock', '22222222-2222-2222-2222-222222222222');
  raise exception 'ASSERTION FAILED: parent inserted a device_commands row with requested_by set to the other parent''s user_id';
exception
  when insufficient_privilege then
    null; -- expected: RLS rejected the insert
end $$;

-- the child device account can select its own pending command via
-- device_commands_select_own_child.
select test.assume_user('33333333-3333-3333-3333-333333333333');
select test.assert_true(
  (select status from device_commands where id = '55555555-5555-5555-5555-555555555555') = 'pending',
  'child device account must be able to select its own pending device_commands row');

-- the child device account can update that command's status to 'delivered'
-- via device_commands_update_status_own_child. (device_commands_select_own_
-- child, exercised just above, already makes the row SELECT-visible to this
-- role, so the ON CONFLICT/UPDATE-visibility gap found in Task 5 does not
-- apply here.)
update device_commands set status = 'delivered'
  where id = '55555555-5555-5555-5555-555555555555';
select test.assert_true(
  (select status from device_commands where id = '55555555-5555-5555-5555-555555555555') = 'delivered',
  'child device account must be able to update its own command status to delivered');

-- ...and then to 'acknowledged'.
update device_commands set status = 'acknowledged'
  where id = '55555555-5555-5555-5555-555555555555';
select test.assert_true(
  (select status from device_commands where id = '55555555-5555-5555-5555-555555555555') = 'acknowledged',
  'child device account must be able to update its own command status to acknowledged');

-- the child device account cannot insert a device_commands row at all --
-- no insert policy is granted to it, only to parents. requested_by below is
-- a real parent's user_id (Edson's) so the only possible rejection is RLS
-- (is_parent() is false for this child device account), never a foreign
-- key violation on requested_by.
do $$
begin
  perform test.assume_user('33333333-3333-3333-3333-333333333333');
  insert into device_commands (child_id, command_type, requested_by) values
    ('44444444-4444-4444-4444-444444444444', 'unlock', '11111111-1111-1111-1111-111111111111');
  raise exception 'ASSERTION FAILED: child device account inserted a device_commands row';
exception
  when insufficient_privilege then
    null; -- expected: RLS rejected the insert (no insert policy applies)
end $$;

-- any user can insert their own push_tokens row.
select test.assume_user('11111111-1111-1111-1111-111111111111');
insert into push_tokens (owner_user_id, fcm_token) values
  ('11111111-1111-1111-1111-111111111111', 'edson-token-1');

-- that user cannot insert a push_tokens row owned by another user, even
-- though that other user (Esposa) is real -- push_tokens_manage_own's with
-- check requires owner_user_id = auth.uid().
do $$
begin
  perform test.assume_user('11111111-1111-1111-1111-111111111111');
  insert into push_tokens (owner_user_id, fcm_token) values
    ('22222222-2222-2222-2222-222222222222', 'edson-planted-token');
  raise exception 'ASSERTION FAILED: user inserted a push_tokens row owned by another user';
exception
  when insufficient_privilege then
    null; -- expected: RLS rejected the insert
end $$;

-- Esposa inserts her own real push_tokens row, used below as the
-- real-but-unowned row for Edson's cross-user checks.
select test.assume_user('22222222-2222-2222-2222-222222222222');
insert into push_tokens (owner_user_id, fcm_token) values
  ('22222222-2222-2222-2222-222222222222', 'esposa-token-1');

-- Edson cannot update Esposa's push_tokens row -- push_tokens_manage_own's
-- using clause filters it out of what Edson's UPDATE can even touch, so
-- this affects 0 rows rather than raising.
select test.assume_user('11111111-1111-1111-1111-111111111111');
update push_tokens set fcm_token = 'edson-overwrote-this'
  where owner_user_id = '22222222-2222-2222-2222-222222222222' and fcm_token = 'esposa-token-1';

select test.assume_user('22222222-2222-2222-2222-222222222222');
select test.assert_true(
  (select count(*) from push_tokens
     where owner_user_id = '22222222-2222-2222-2222-222222222222' and fcm_token = 'esposa-token-1') = 1,
  'another user''s attempted update of Esposa''s push_tokens row must have no effect (RLS filters it to 0 rows)');

-- Edson can update his own push_tokens row.
select test.assume_user('11111111-1111-1111-1111-111111111111');
update push_tokens set fcm_token = 'edson-token-2'
  where owner_user_id = '11111111-1111-1111-1111-111111111111' and fcm_token = 'edson-token-1';
select test.assert_true(
  (select count(*) from push_tokens
     where owner_user_id = '11111111-1111-1111-1111-111111111111' and fcm_token = 'edson-token-2') = 1,
  'user must be able to update their own push_tokens row');

select 'OK: 0006 tests passed';

rollback;
