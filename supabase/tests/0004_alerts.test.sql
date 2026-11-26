\set ON_ERROR_STOP on
\i supabase/tests/_helpers.sql

begin;

-- fixtures: re-insert Task 1's parent/child auth users + parents/children rows,
-- since each test file runs in its own transaction and Task 1's own test file
-- rolled its fixtures back. Inserted as postgres (bypasses RLS), which is the
-- role this script connects as before any test.assume_user() switch below.
insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'edson@example.com'),
  ('22222222-2222-2222-2222-222222222222', 'esposa@example.com'),
  ('33333333-3333-3333-3333-333333333333', 'vitor-device@example.com'),
  ('66666666-6666-6666-6666-666666666666', 'ana-device@example.com');
insert into parents (user_id, full_name) values
  ('11111111-1111-1111-1111-111111111111', 'Edson'),
  ('22222222-2222-2222-2222-222222222222', 'Esposa');
insert into children (id, device_user_id, full_name, birthdate) values
  ('44444444-4444-4444-4444-444444444444', '33333333-3333-3333-3333-333333333333', 'Vitor', '2019-01-01'),
  -- a second, real child that Vitor's device account does NOT own, used
  -- below to prove the cross-child insert is rejected by RLS itself rather
  -- than by the child_id foreign key (a non-existent child_id would fail
  -- the FK regardless of whether RLS is even enabled, so it wouldn't prove
  -- anything about the policy).
  ('77777777-7777-7777-7777-777777777777', '66666666-6666-6666-6666-666666666666', 'Ana', '2021-01-01');

-- the child device account can insert a panic alert for its own child_id.
-- There is no select policy for the child device account (only
-- `alerts_select_for_parents`), so we verify the insert actually landed by
-- checking as the parent afterward, not by selecting it back as the child.
select test.assume_user('33333333-3333-3333-3333-333333333333');
insert into alerts (child_id, alert_type) values
  ('44444444-4444-4444-4444-444444444444', 'panic');

select test.assume_user('11111111-1111-1111-1111-111111111111');
select test.assert_true(
  (select count(*) from alerts
     where child_id = '44444444-4444-4444-4444-444444444444' and alert_type = 'panic') = 1,
  'child device account must be able to insert a panic alert for its own child');

-- the child device account's select on alerts returns 0 rows -- there is no
-- select policy granted to it, only `alerts_select_for_parents`.
select test.assume_user('33333333-3333-3333-3333-333333333333');
select test.assert_true(
  (select count(*) from alerts) = 0,
  'child device account must not be able to select any alerts row');

-- an alert_type not in the check constraint's allowed list is rejected.
do $$
begin
  perform test.assume_user('33333333-3333-3333-3333-333333333333');
  insert into alerts (child_id, alert_type) values
    ('44444444-4444-4444-4444-444444444444', 'not_a_real_alert_type');
  raise exception 'ASSERTION FAILED: inserted an alert with an invalid alert_type';
exception
  when check_violation then
    null; -- expected: the alert_type check constraint rejected it
end $$;

-- the child device account cannot insert an alert for a child_id it does
-- not own. The target child_id (Ana, 77777777...) genuinely exists in
-- `children`, owned by a different device account, so this can only be
-- rejected by the `alerts_insert_own_child` RLS policy (SQLSTATE 42501 /
-- insufficient_privilege) -- there is no foreign key failure possible
-- here, so any other exception must re-raise as a real test failure.
do $$
begin
  perform test.assume_user('33333333-3333-3333-3333-333333333333');
  insert into alerts (child_id, alert_type) values
    ('77777777-7777-7777-7777-777777777777', 'panic');
  raise exception 'ASSERTION FAILED: child device account inserted an alert for a child_id it does not own';
exception
  when insufficient_privilege then
    null; -- expected: RLS rejected the insert
end $$;

-- the parent can select the inserted alert and update its acknowledged_at
select test.assume_user('11111111-1111-1111-1111-111111111111');
select test.assert_true(
  (select count(*) from alerts
     where child_id = '44444444-4444-4444-4444-444444444444' and alert_type = 'panic') = 1,
  'parent must be able to select the inserted panic alert');

-- sentinel timestamp so we can later prove the child's update attempt did
-- not change this value, rather than just checking "is not null".
update alerts set acknowledged_at = '2026-01-01 00:00:00+00'
  where child_id = '44444444-4444-4444-4444-444444444444' and alert_type = 'panic';

select test.assert_true(
  (select count(*) from alerts
     where child_id = '44444444-4444-4444-4444-444444444444' and alert_type = 'panic'
       and acknowledged_at = '2026-01-01 00:00:00+00') = 1,
  'parent must be able to update acknowledged_at on the alert');

-- the child device account cannot update acknowledged_at on any alert --
-- there is no update policy granted to it (only `alerts_update_ack_for_parents`,
-- which requires is_parent()), so RLS filters out every row for the update
-- rather than raising an error: the statement succeeds but affects 0 rows.
-- Attempt to overwrite the sentinel with a different value, then verify
-- (as the parent) that the sentinel is unchanged.
select test.assume_user('33333333-3333-3333-3333-333333333333');
update alerts set acknowledged_at = '2099-01-01 00:00:00+00'
  where child_id = '44444444-4444-4444-4444-444444444444' and alert_type = 'panic';

select test.assume_user('11111111-1111-1111-1111-111111111111');
select test.assert_true(
  (select count(*) from alerts
     where child_id = '44444444-4444-4444-4444-444444444444' and alert_type = 'panic'
       and acknowledged_at = '2026-01-01 00:00:00+00') = 1,
  'child device account''s update of acknowledged_at must have no effect (RLS filters it to 0 rows)');

select 'OK: 0004 tests passed';

rollback;
