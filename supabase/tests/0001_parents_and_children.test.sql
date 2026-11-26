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

select test.assume_user('11111111-1111-1111-1111-111111111111');
select test.assert_true(
  (select count(*) from children) = 1,
  'parent must see the child row');

select test.assume_user('33333333-3333-3333-3333-333333333333');
select test.assert_true(
  (select count(*) from children) = 1,
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

select 'OK: 0001 tests passed';

rollback;
