\set ON_ERROR_STOP on
\i supabase/tests/_helpers.sql

begin;

-- fixtures: two parent auth users + one child auth user, inserted as postgres (bypasses RLS)
insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'edson@example.com'),
  ('22222222-2222-2222-2222-222222222222', 'esposa@example.com'),
  ('33333333-3333-3333-3333-333333333333', 'vitor-device@example.com');
insert into parents (user_id, full_name) values
  ('11111111-1111-1111-1111-111111111111', 'Edson'),
  ('22222222-2222-2222-2222-222222222222', 'Esposa');
insert into children (id, device_user_id, full_name, birthdate) values
  ('44444444-4444-4444-4444-444444444444', '33333333-3333-3333-3333-333333333333', 'Vitor', '2019-01-01');

-- a second fixture, inserted here (still as postgres, before any
-- test.assume_user() call switches the session role) for the 18-year
-- monitoring cutoff test near the end of this file: an "adult child" whose
-- device account's device_user_id still matches its own children row, but
-- whose birthdate makes them already 18+ (well past the cutoff, not a
-- boundary case).
insert into auth.users (id, email) values
  ('55555555-5555-5555-5555-555555555555', 'adult-child-device@example.com');
insert into children (id, device_user_id, full_name, birthdate) values
  ('66666666-6666-6666-6666-666666666666', '55555555-5555-5555-5555-555555555555', 'Adult Child', '2000-01-01');

-- scoped by id, not a bare count(*) on the whole table: after a real
-- `supabase db reset`, seed.sql's own parents/children rows are also
-- present (permanently, outside this rolled-back transaction) and visible
-- to any parent via is_parent(), so an unscoped count(*) would break the
-- moment seed data exists alongside this test's fixtures.
select test.assume_user('11111111-1111-1111-1111-111111111111');
select test.assert_true(
  (select count(*) from children where id = '44444444-4444-4444-4444-444444444444') = 1,
  'parent must see the child row');

-- the SECOND real parent (Esposa, not just Edson) must also see the same
-- child row -- the spec requires both parents to have equal access, with
-- no per-parent partition of the family's data.
select test.assume_user('22222222-2222-2222-2222-222222222222');
select test.assert_true(
  (select count(*) from children where id = '44444444-4444-4444-4444-444444444444') = 1,
  'the second parent (Esposa) must also see the child row');

select test.assume_user('33333333-3333-3333-3333-333333333333');
select test.assert_true(
  (select count(*) from children where id = '44444444-4444-4444-4444-444444444444') = 1,
  'child device account must see its own row');

-- explicit: child device account cannot update its own birthdate.
-- Covers both possible Postgres RLS behaviors: a thrown insufficient_privilege,
-- or a silently-affected-zero-rows update that doesn't raise.
do $$
begin
  perform test.assume_user('33333333-3333-3333-3333-333333333333');
  update children set birthdate = '2000-01-01' where id = '44444444-4444-4444-4444-444444444444';
  if (select birthdate from children where id = '44444444-4444-4444-4444-444444444444') <> '2019-01-01' then
    raise exception 'ASSERTION FAILED: child device account updated its own birthdate';
  end if;
exception when insufficient_privilege then
  null; -- expected
end $$;

-- the spec's 18-year monitoring cutoff (migration 0007: is_own_child() now
-- also checks birthdate), exercised via a `locations` insert -- the same
-- table/pattern Task 3's test already uses for ordinary cross-child
-- rejection, and the single highest-frequency write a child's device makes,
-- so it's the clearest concrete proof that "monitoring" actually stops.
-- Uses the "Adult Child" fixture inserted above, at the top of this file.
do $$
begin
  perform test.assume_user('55555555-5555-5555-5555-555555555555');
  insert into locations (child_id, lat, lng) values
    ('66666666-6666-6666-6666-666666666666', -23.55, -46.63);
  raise exception 'ASSERTION FAILED: an 18+ child''s own device account inserted a locations row';
exception
  when insufficient_privilege then
    null; -- expected: is_own_child() now requires birthdate within the last 18 years
end $$;

select 'OK: 0001 tests passed';

rollback;
