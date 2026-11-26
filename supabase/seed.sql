-- Dev-only seed data for local Supabase stack resets (`supabase db reset`).
-- NOT applied to the hosted project — the real family's accounts and rows
-- were created directly against the hosted project in Task 7, step 3.
--
-- UUID range: every id here uses only hex letters (a-f) as the repeated
-- digit (aaaa…/bbbb…/cccc…/dddd…/eeee…/ffff…), deliberately disjoint from
-- every supabase/tests/*.test.sql fixture, which only ever use digits 1-9
-- (1111…, 2222…, 3333…, 4444…, 5555…, 6666…, 7777…, 9999…). `db.seed` in
-- config.toml is enabled, so this file's rows are applied by every
-- `supabase db reset` BEFORE any test file runs, and they are never rolled
-- back (unlike a test file's own fixtures, which live inside
-- `begin; ... rollback;`). If this range ever overlapped a test file's
-- fixtures, every test's plain (non "on conflict") fixture insert would hit
-- a unique-constraint violation against these permanently-committed seed
-- rows on `auth.users`/`parents`/`children`. Emails are also on a distinct
-- domain (`@escudofamiliar.local` vs. the tests' `@example.com`) for the
-- same reason, since `auth.users.email` is uniquely indexed too.
insert into auth.users (id, email) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'edson.seed@escudofamiliar.local'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'esposa.seed@escudofamiliar.local'),
  ('cccccccc-cccc-cccc-cccc-cccccccccccc', 'vitor.device.seed@escudofamiliar.local'),
  ('dddddddd-dddd-dddd-dddd-dddddddddddd', 'mariaclara.device.seed@escudofamiliar.local')
on conflict (id) do nothing;

insert into parents (user_id, full_name) values
  ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', 'Edson'),
  ('bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', 'Esposa')
on conflict (user_id) do nothing;

insert into children (id, device_user_id, full_name, birthdate) values
  ('eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee', 'cccccccc-cccc-cccc-cccc-cccccccccccc', 'Vitor', '2019-01-01'),
  ('ffffffff-ffff-ffff-ffff-ffffffffffff', 'dddddddd-dddd-dddd-dddd-dddddddddddd', 'Maria Clara', '2014-01-01')
on conflict (id) do nothing;
