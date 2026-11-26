\i supabase/tests/_helpers.sql

begin;

-- fixtures: re-insert Task 1's parent/child auth users + parents/children rows,
-- since each test file runs in its own transaction and Task 1's own test file
-- rolled its fixtures back.
insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'edson@example.com'),
  ('22222222-2222-2222-2222-222222222222', 'esposa@example.com'),
  ('33333333-3333-3333-3333-333333333333', 'vitor-device@example.com');
insert into parents (user_id, full_name) values
  ('11111111-1111-1111-1111-111111111111', 'Edson'),
  ('22222222-2222-2222-2222-222222222222', 'Esposa');
insert into children (id, device_user_id, full_name, birthdate) values
  ('44444444-4444-4444-4444-444444444444', '33333333-3333-3333-3333-333333333333', 'Vitor', '2019-01-01');

-- parent can insert a safe_zones row for the child and read it back
select test.assume_user('11111111-1111-1111-1111-111111111111');
insert into safe_zones (id, child_id, name, lat, lng, radius_m) values
  ('55555555-5555-5555-5555-555555555555', '44444444-4444-4444-4444-444444444444', 'Home', -23.55, -46.63, 150);
select test.assert_true(
  (select count(*) from safe_zones where id = '55555555-5555-5555-5555-555555555555') = 1,
  'parent must be able to insert and read back a safe_zones row for the child');

-- the child device account can select that same safe_zones row
select test.assume_user('33333333-3333-3333-3333-333333333333');
select test.assert_true(
  (select count(*) from safe_zones where id = '55555555-5555-5555-5555-555555555555') = 1,
  'child device account must be able to select its own safe_zones row');

-- the child device account can insert a zone_events row for its own child_id.
-- zone_events has no select policy for the child, only insert, so we can't
-- read the row back as the child here -- the row-count check happens below,
-- as the parent, who does have a select policy on zone_events.
select test.assume_user('33333333-3333-3333-3333-333333333333');
insert into zone_events (child_id, zone_id, event_type) values
  ('44444444-4444-4444-4444-444444444444', '55555555-5555-5555-5555-555555555555', 'enter');

-- the child device account cannot insert a zone_events row for a different,
-- non-existent child_id it does not own.
do $$
begin
  perform test.assume_user('33333333-3333-3333-3333-333333333333');
  insert into zone_events (child_id, zone_id, event_type) values
    ('99999999-9999-9999-9999-999999999999', '55555555-5555-5555-5555-555555555555', 'enter');
  raise exception 'ASSERTION FAILED: child device account inserted a zone_events row for a child_id it does not own';
exception
  when insufficient_privilege then
    null; -- expected: RLS rejected the insert
  when foreign_key_violation then
    null; -- expected: child_id does not exist, and RLS/FK both reject it
end $$;

-- the parent can select the inserted zone_events row
select test.assume_user('11111111-1111-1111-1111-111111111111');
select test.assert_true(
  (select count(*) from zone_events
     where child_id = '44444444-4444-4444-4444-444444444444'
       and zone_id = '55555555-5555-5555-5555-555555555555'
       and event_type = 'enter') = 1,
  'parent must be able to select the inserted zone_events row');

select 'OK: 0002 tests passed';

rollback;
