-- Dev-only seed data for local Supabase stack resets (`supabase db reset`).
-- NOT applied to the hosted project — the real family's accounts and rows
-- were created directly against the hosted project in Task 7, step 3.
-- These UUIDs match the fixture convention used across supabase/tests/*.test.sql.

insert into auth.users (id, email) values
  ('11111111-1111-1111-1111-111111111111', 'edson@example.com'),
  ('22222222-2222-2222-2222-222222222222', 'esposa@example.com'),
  ('33333333-3333-3333-3333-333333333333', 'vitor-device@example.com'),
  ('77777777-7777-7777-7777-777777777777', 'mariaclara-device@example.com')
on conflict (id) do nothing;

insert into parents (user_id, full_name) values
  ('11111111-1111-1111-1111-111111111111', 'Edson'),
  ('22222222-2222-2222-2222-222222222222', 'Esposa')
on conflict (user_id) do nothing;

insert into children (id, device_user_id, full_name, birthdate) values
  ('44444444-4444-4444-4444-444444444444', '33333333-3333-3333-3333-333333333333', 'Vitor', '2019-01-01'),
  ('88888888-8888-8888-8888-888888888888', '77777777-7777-7777-7777-777777777777', 'Maria Clara', '2014-01-01')
on conflict (id) do nothing;
