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

-- the child device account can insert a locations row for its own child_id
select test.assume_user('33333333-3333-3333-3333-333333333333');
insert into locations (child_id, lat, lng, recorded_at) values
  ('44444444-4444-4444-4444-444444444444', -23.55, -46.63, now());

-- the child device account cannot insert a locations row for a child_id it
-- does not own. The target child_id (Ana, 77777777...) genuinely exists in
-- `children`, owned by a different device account, so this can only be
-- rejected by the `locations_insert_own_child` RLS policy (SQLSTATE 42501
-- / insufficient_privilege) -- there is no foreign key failure possible
-- here, so any other exception must re-raise as a real test failure.
do $$
begin
  perform test.assume_user('33333333-3333-3333-3333-333333333333');
  insert into locations (child_id, lat, lng) values
    ('77777777-7777-7777-7777-777777777777', -23.55, -46.63);
  raise exception 'ASSERTION FAILED: child device account inserted a locations row for a child_id it does not own';
exception
  when insufficient_privilege then
    null; -- expected: RLS rejected the insert
end $$;

-- the parent can select the inserted locations row
select test.assume_user('11111111-1111-1111-1111-111111111111');
select test.assert_true(
  (select count(*) from locations
     where child_id = '44444444-4444-4444-4444-444444444444') = 1,
  'parent must be able to select the inserted locations row');

-- the child device account cannot select any locations row -- no select
-- policy is granted to it, so RLS filters every row out (no error, just an
-- empty result)
select test.assume_user('33333333-3333-3333-3333-333333333333');
select test.assert_true(
  (select count(*) from locations) = 0,
  'child device account must not be able to select any locations row');

-- retention: switch back to postgres (bypasses RLS) to insert fixture rows
-- directly, exactly as the plan's test steps describe. We do NOT wrap this
-- section in its own sub-transaction that we roll back separately: the
-- whole file already runs inside one begin/rollback, and a `delete` is
-- visible to statements later in the *same* transaction. So we can insert
-- the three rows, call purge_old_locations() for real, and assert the
-- resulting row counts as seen within this transaction -- proving the
-- function's `where` clause deletes exactly the right row -- while the
-- outer `rollback` at the end of the file still discards every row this
-- test ever wrote, leaving zero permanent fixture data behind.
select set_config('role', 'postgres', true);
insert into locations (child_id, lat, lng, recorded_at) values
  ('44444444-4444-4444-4444-444444444444', 1, 1, now() - interval '181 days'),
  ('44444444-4444-4444-4444-444444444444', 2, 2, now() - interval '179 days'),
  ('44444444-4444-4444-4444-444444444444', 3, 3, now());

select purge_old_locations();

select test.assert_true(
  (select count(*) from locations where lat = 1 and lng = 1) = 0,
  'purge_old_locations() must delete the 181-day-old row');
select test.assert_true(
  (select count(*) from locations where lat = 2 and lng = 2) = 1,
  'purge_old_locations() must keep the 179-day-old row');
select test.assert_true(
  (select count(*) from locations where lat = 3 and lng = 3) = 1,
  'purge_old_locations() must keep the just-now row');

select 'OK: 0003 tests passed';

rollback;
