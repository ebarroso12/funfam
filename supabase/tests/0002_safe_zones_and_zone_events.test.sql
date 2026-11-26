\set ON_ERROR_STOP on
\i supabase/tests/_helpers.sql

begin;

-- fixtures: re-insert Task 1's parent/child auth users + parents/children rows,
-- since each test file runs in its own transaction and Task 1's own test file
-- rolled its fixtures back. Also includes a second real child (Ana, owned by
-- a different device account) so cross-child negative tests target a real
-- row and can't accidentally pass because of a foreign-key failure instead
-- of an RLS rejection.
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
  ('77777777-7777-7777-7777-777777777777', '66666666-6666-6666-6666-666666666666', 'Ana', '2021-01-01');

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

-- the parent sets up a safe_zone for Ana, used below both as a clean RLS-
-- only negative test and as the FK-mismatch negative test's mismatched zone.
select test.assume_user('11111111-1111-1111-1111-111111111111');
insert into safe_zones (id, child_id, name, lat, lng, radius_m) values
  ('88888888-8888-8888-8888-888888888888', '77777777-7777-7777-7777-777777777777', 'Ana''s Home', -23.56, -46.64, 150);

-- the child device account (Vitor) cannot insert a zone_events row for a
-- different, real child_id it does not own (Ana's). The (zone_id, child_id)
-- pair used here (Ana's own zone with Ana's own child_id) IS a valid pair
-- per the composite FK added in migration 0007, so this can only be
-- rejected by the `zone_events_insert_own_child` RLS policy itself (SQLSTATE
-- 42501 / insufficient_privilege), cleanly isolating the RLS check from the
-- FK check tested separately below.
do $$
begin
  perform test.assume_user('33333333-3333-3333-3333-333333333333');
  insert into zone_events (child_id, zone_id, event_type) values
    ('77777777-7777-7777-7777-777777777777', '88888888-8888-8888-8888-888888888888', 'enter');
  raise exception 'ASSERTION FAILED: child device account inserted a zone_events row for a child_id it does not own';
exception
  when insufficient_privilege then
    null; -- expected: RLS rejected the insert
end $$;

-- the child device account (Vitor) cannot insert a zone_events row that
-- pairs its OWN child_id (which passes the RLS check) with a sibling's
-- zone_id (Ana's) -- the (zone_id, child_id) pair doesn't match any row in
-- safe_zones, so migration 0007's composite foreign key
-- (zone_events_zone_child_fk) rejects it. This is the one negative test in
-- this suite that correctly expects foreign_key_violation rather than
-- insufficient_privilege, since it's specifically exercising the FK
-- relationship, not RLS cross-child isolation.
do $$
begin
  perform test.assume_user('33333333-3333-3333-3333-333333333333');
  insert into zone_events (child_id, zone_id, event_type) values
    ('44444444-4444-4444-4444-444444444444', '88888888-8888-8888-8888-888888888888', 'enter');
  raise exception 'ASSERTION FAILED: child device account inserted a zone_events row with a zone_id belonging to a sibling''s safe_zones row';
exception
  when foreign_key_violation then
    null; -- expected: the (zone_id, child_id) composite FK rejected the mismatched pair
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
