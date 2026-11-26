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
  -- below to prove cross-child insert/update is rejected by RLS itself
  -- rather than by the child_id foreign key or a missing row.
  ('77777777-7777-7777-7777-777777777777', '66666666-6666-6666-6666-666666666666', 'Ana', '2021-01-01');

-- the child device account can insert an app_usage row for its own child.
select test.assume_user('33333333-3333-3333-3333-333333333333');
insert into app_usage (child_id, app_package, usage_date, duration_minutes) values
  ('44444444-4444-4444-4444-444444444444', 'com.whatsapp', '2026-11-26', 5);

-- the same child device account can then upsert (the app's real pattern:
-- insert ... on conflict (child_id, app_package, usage_date) do update set
-- duration_minutes = ...) that same row as usage accrues through the day.
insert into app_usage (child_id, app_package, usage_date, duration_minutes)
  values ('44444444-4444-4444-4444-444444444444', 'com.whatsapp', '2026-11-26', 12)
  on conflict (child_id, app_package, usage_date)
  do update set duration_minutes = excluded.duration_minutes;

-- verify the insert+upsert landed as the parent...
select test.assume_user('11111111-1111-1111-1111-111111111111');
select test.assert_true(
  (select count(*) from app_usage
     where child_id = '44444444-4444-4444-4444-444444444444'
       and app_package = 'com.whatsapp' and usage_date = '2026-11-26'
       and duration_minutes = 12) = 1,
  'child device account must be able to insert then upsert its own app_usage row');

-- ...and also as the child device account itself, via
-- `app_usage_select_own_child`. This policy is what makes the on-conflict
-- upsert above possible at all (Postgres requires the existing row to be
-- SELECT-visible before an UPDATE, including the DO UPDATE path of
-- ON CONFLICT, can touch it), so this assertion directly exercises it.
select test.assume_user('33333333-3333-3333-3333-333333333333');
select test.assert_true(
  (select count(*) from app_usage
     where child_id = '44444444-4444-4444-4444-444444444444'
       and app_package = 'com.whatsapp' and usage_date = '2026-11-26'
       and duration_minutes = 12) = 1,
  'child device account must be able to select its own app_usage row');

-- Ana's own device account inserts a row for Ana, used below as the
-- real-but-unowned row for Vitor's cross-child checks.
select test.assume_user('66666666-6666-6666-6666-666666666666');
insert into app_usage (child_id, app_package, usage_date, duration_minutes) values
  ('77777777-7777-7777-7777-777777777777', 'com.tiktok', '2026-11-26', 30);

-- Vitor's device account cannot see Ana's row via
-- `app_usage_select_own_child` -- it only grants visibility into rows
-- where is_own_child(child_id) is true for the caller, which is false for
-- Ana's child_id.
select test.assume_user('33333333-3333-3333-3333-333333333333');
select test.assert_true(
  (select count(*) from app_usage
     where child_id = '77777777-7777-7777-7777-777777777777'
       and app_package = 'com.tiktok' and usage_date = '2026-11-26') = 0,
  'child device account must not be able to select another child''s app_usage row');

-- the child device account cannot insert an app_usage row for a child_id it
-- does not own. The target child_id (Ana, 77777777...) genuinely exists in
-- `children`, owned by a different device account, so this can only be
-- rejected by the `app_usage_upsert_own_child` RLS policy (SQLSTATE 42501 /
-- insufficient_privilege) -- there is no foreign key failure possible here,
-- so any other exception must re-raise as a real test failure.
do $$
begin
  perform test.assume_user('33333333-3333-3333-3333-333333333333');
  insert into app_usage (child_id, app_package, usage_date, duration_minutes) values
    ('77777777-7777-7777-7777-777777777777', 'com.instagram', '2026-11-26', 5);
  raise exception 'ASSERTION FAILED: child device account inserted an app_usage row for a child_id it does not own';
exception
  when insufficient_privilege then
    null; -- expected: RLS rejected the insert
end $$;

-- the child device account cannot update Ana's row either. Vitor's device
-- account already has working select and update policies proven above (the
-- upsert and the self-select both succeeded on its own row), and both
-- `app_usage_select_own_child` and `app_usage_update_own_child` key off the
-- same is_own_child(child_id) check, which is false for Ana's child_id --
-- so a 0-row-affected result here is clean evidence of that shared
-- ownership check doing the filtering, not an accidental default-deny.
select test.assume_user('33333333-3333-3333-3333-333333333333');
update app_usage set duration_minutes = 999
  where child_id = '77777777-7777-7777-7777-777777777777'
    and app_package = 'com.tiktok' and usage_date = '2026-11-26';

select test.assume_user('11111111-1111-1111-1111-111111111111');
select test.assert_true(
  (select count(*) from app_usage
     where child_id = '77777777-7777-7777-7777-777777777777'
       and app_package = 'com.tiktok' and usage_date = '2026-11-26'
       and duration_minutes = 30) = 1,
  'child device account''s update of another child''s app_usage row must have no effect (RLS filters it to 0 rows)');

-- the parent can select all app_usage rows across both children.
select test.assert_true(
  (select count(*) from app_usage
     where child_id in ('44444444-4444-4444-4444-444444444444', '77777777-7777-7777-7777-777777777777')) = 2,
  'parent must be able to select all app_usage rows for its children');

select 'OK: 0005 tests passed';

rollback;
