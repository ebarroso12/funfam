\set ON_ERROR_STOP on
\i supabase/tests/_helpers.sql

begin;

-- fixtures: one family, two children (own-transaction, rolled back after --
-- same convention as every other test file; see 0006 for why these UUIDs
-- are safe to reuse here).
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

-- each child's device account registers its own push token.
select test.assume_user('33333333-3333-3333-3333-333333333333');
insert into push_tokens (owner_user_id, fcm_token) values
  ('33333333-3333-3333-3333-333333333333', 'vitor-token-1');

select test.assume_user('66666666-6666-6666-6666-666666666666');
insert into push_tokens (owner_user_id, fcm_token) values
  ('66666666-6666-6666-6666-666666666666', 'ana-token-1');

-- a parent can select his own child's push token -- this is the whole
-- point of this migration (the painel's "bloquear" action needs this to
-- send an instant FCM push instead of relying only on the device's poll).
select test.assume_user('11111111-1111-1111-1111-111111111111');
select test.assert_true(
  (select fcm_token from push_tokens where owner_user_id = '33333333-3333-3333-3333-333333333333') = 'vitor-token-1',
  'a parent must be able to select his own child''s push_tokens row');

-- ...and the other child's too -- is_parent() grants access to the whole
-- family, not just a single child, matching every other table's model.
select test.assert_true(
  (select fcm_token from push_tokens where owner_user_id = '66666666-6666-6666-6666-666666666666') = 'ana-token-1',
  'a parent must be able to select his other child''s push_tokens row too');

-- Vitor's own device account is not a parent, so the new policy does not
-- apply to it; it still cannot see Ana's token (push_tokens_manage_own's
-- using clause requires owner_user_id = auth.uid(), which fails for Ana's
-- row from Vitor's session).
select test.assume_user('33333333-3333-3333-3333-333333333333');
select test.assert_true(
  (select count(*) from push_tokens where owner_user_id = '66666666-6666-6666-6666-666666666666') = 0,
  'a child device account must not be able to select a sibling''s push_tokens row');

select 'OK: 0008 tests passed';

rollback;
