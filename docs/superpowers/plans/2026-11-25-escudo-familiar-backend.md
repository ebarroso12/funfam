# Escudo Familiar — Backend (Supabase) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the Supabase schema, RLS policies and retention job that the
Android app (children) and the web dashboard (parents) will both build on.

**Architecture:** One Supabase Postgres project. Two roles, both backed by
`auth.users`: a `parents` row per parent account (full access to everything
about their children), and a `children.device_user_id` per child — a Supabase
Auth account provisioned by the parents, used only by that child's Android app
to write its own telemetry. RLS is the only access boundary; there is no
separate API layer. A scheduled job purges location history older than 180
days.

**Tech Stack:** Supabase CLI (local dev stack), Postgres migrations under
`supabase/migrations/`, plain SQL (no pgTAP) for RLS tests, `pg_cron` for the
retention job.

**Spec:** `docs/superpowers/specs/2026-11-25-escudo-familiar-design.md`

## Global Constraints

- Every table holding a `child_id` must have RLS enabled with no public
  access — only `parents` (full access) and the owning child's device account
  (insert-only on its own rows, per table as scoped below) may touch it.
- `children.birthdate` is writable only by parents — never by the child's own
  device account.
- Location history older than 180 days is deleted automatically.
- No table or policy references message/notification content — only
  telemetry (location, battery, Wi-Fi metadata, app usage duration, alerts,
  commands).

## Review Focus

- A child device account that tries to `select`/`insert`/`update` another
  child's rows (wrong `child_id` in the payload) must be rejected by RLS, not
  by trusting the client — tested directly against Postgres, not through
  app code.
- A child device account that tries to `update` its own `children.birthdate`
  must be rejected.
- A `device_commands` row inserted by anyone other than a `parents` member
  must be rejected.
- A location row older than 180 days must actually disappear after the
  retention job runs, including rows exactly at the 180-day boundary.
- Two parents must both see the same children and the same data — there is
  no per-parent partition of the family's own children.

---

## File Structure

```
supabase/
  migrations/
    0001_parents_and_children.sql
    0002_safe_zones_and_zone_events.sql
    0003_locations_and_retention.sql
    0004_alerts.sql
    0005_app_usage.sql
    0006_device_commands_and_push_tokens.sql
  tests/
    0001_parents_and_children.test.sql
    0002_safe_zones_and_zone_events.test.sql
    0003_locations_and_retention.test.sql
    0004_alerts.test.sql
    0005_app_usage.test.sql
    0006_device_commands_and_push_tokens.test.sql
  seed.sql
```

Each `NNNN_*.sql` migration owns its own tables, helper functions it
introduces, and RLS policies. Each `.test.sql` is a standalone script run
with `psql` against the local Supabase stack; it sets the Postgres session to
impersonate a specific `auth.uid()` via `set_config('request.jwt.claims', ...)`
and asserts row visibility with `DO $$ ... RAISE EXCEPTION ... $$` blocks, so
a failing assertion makes `psql` exit non-zero.

**Test helper** (define once, reuse in every test file):

```sql
-- supabase/tests/_helpers.sql
create or replace function test.assume_user(p_uid uuid, p_role text default 'authenticated')
returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_uid::text)::text, true);
  perform set_config('role', p_role, true);
end;
$$;

create or replace function test.assert_true(p_condition boolean, p_message text)
returns void language plpgsql as $$
begin
  if not p_condition then
    raise exception 'ASSERTION FAILED: %', p_message;
  end if;
end;
$$;
```

---

### Task 1: Project scaffolding + `parents`/`children` tables

**Files:**
- Create: `supabase/config.toml` (via `supabase init`)
- Create: `supabase/migrations/0001_parents_and_children.sql`
- Create: `supabase/tests/_helpers.sql`
- Create: `supabase/tests/0001_parents_and_children.test.sql`
- Create: `supabase/seed.sql`

**Interfaces:**
- Produces: tables `parents(user_id uuid pk)`, `children(id uuid pk,
  device_user_id uuid unique, full_name text, birthdate date, created_at
  timestamptz)`; functions `is_parent() returns boolean`,
  `is_own_child(p_child_id uuid) returns boolean`, both `security definer`,
  usable by every later migration's RLS policies.

- [ ] **Step 1: Run `supabase init` in `C:\dev\familia-escudo`, then `supabase start`**

Expected: local stack comes up; note the local `DATABASE_URL` it prints.

- [ ] **Step 2: Write `supabase/tests/_helpers.sql`** (content above, in a
  dedicated `test` schema created at the top of the file: `create schema if
  not exists test;`)

- [ ] **Step 3: Write migration `0001_parents_and_children.sql`**

```sql
create table parents (
  user_id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  created_at timestamptz not null default now()
);

create table children (
  id uuid primary key default gen_random_uuid(),
  device_user_id uuid not null unique references auth.users(id) on delete cascade,
  full_name text not null,
  birthdate date not null,
  created_at timestamptz not null default now()
);

create or replace function is_parent() returns boolean
language sql security definer stable as $$
  select exists (select 1 from parents where user_id = auth.uid());
$$;

create or replace function is_own_child(p_child_id uuid) returns boolean
language sql security definer stable as $$
  select exists (
    select 1 from children where id = p_child_id and device_user_id = auth.uid()
  );
$$;

alter table parents enable row level security;
alter table children enable row level security;

create policy parents_select_self on parents for select
  using (user_id = auth.uid());

create policy children_all_for_parents on children for all
  using (is_parent()) with check (is_parent());

create policy children_select_own on children for select
  using (device_user_id = auth.uid());
```

- [ ] **Step 4: Write `supabase/tests/0001_parents_and_children.test.sql`**

```sql
\i supabase/tests/_helpers.sql

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
select test.assert_true(
  not exists (
    select 1 from children
    where id = '44444444-4444-4444-4444-444444444444'
    for update
  ) or (
    (update children set birthdate = '2000-01-01'
     where id = '44444444-4444-4444-4444-444444444444') is null
  ),
  'placeholder — replaced by explicit negative-update check below'
);

-- explicit: child device account cannot update its own birthdate
do $$
begin
  perform test.assume_user('33333333-3333-3333-3333-333333333333');
  update children set birthdate = '2000-01-01' where id = '44444444-4444-4444-4444-444444444444';
  if (select birthdate from children where id = '44444444-4444-4444-4444-444444444444') = '2000-01-01' then
    raise exception 'ASSERTION FAILED: child device account updated its own birthdate';
  end if;
exception when insufficient_privilege then
  null; -- expected
end $$;

select 'OK: 0001 tests passed';
```

(Replace the placeholder assertion with a clean negative-update check: the
intent is "child device account's `update` on `birthdate` must either be
rejected by RLS or silently affect zero rows" — write whichever of the two
actually matches how Postgres RLS behaves for a `for all`-less table with no
matching `update` policy, and delete the unused placeholder lines.)

- [ ] **Step 5: Run the test**

Run: `psql "$DATABASE_URL" -f supabase/tests/0001_parents_and_children.test.sql`
Expected: ends with `OK: 0001 tests passed`, no `ASSERTION FAILED`.

- [ ] **Step 6: Commit**

```bash
git add supabase/
git commit -m "feat: add parents/children tables with RLS"
```

---

### Task 2: `safe_zones` + `zone_events`

**Files:**
- Create: `supabase/migrations/0002_safe_zones_and_zone_events.sql`
- Create: `supabase/tests/0002_safe_zones_and_zone_events.test.sql`

**Interfaces:**
- Consumes: `is_parent()`, `is_own_child(uuid)` from Task 1.
- Produces: tables `safe_zones(id uuid pk, child_id uuid, name text, lat
  double precision, lng double precision, radius_m integer)`,
  `zone_events(id bigint pk, child_id uuid, zone_id uuid, event_type text
  check in ('enter','exit'), occurred_at timestamptz)`.

- [ ] **Step 1: Write migration `0002_safe_zones_and_zone_events.sql`**

```sql
create table safe_zones (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references children(id) on delete cascade,
  name text not null,
  lat double precision not null,
  lng double precision not null,
  radius_m integer not null,
  created_at timestamptz not null default now()
);

create table zone_events (
  id bigint generated always as identity primary key,
  child_id uuid not null references children(id) on delete cascade,
  zone_id uuid not null references safe_zones(id) on delete cascade,
  event_type text not null check (event_type in ('enter','exit')),
  occurred_at timestamptz not null default now()
);

alter table safe_zones enable row level security;
alter table zone_events enable row level security;

create policy safe_zones_all_for_parents on safe_zones for all
  using (is_parent()) with check (is_parent());
create policy safe_zones_select_own_child on safe_zones for select
  using (is_own_child(child_id));

create policy zone_events_select_for_parents on zone_events for select
  using (is_parent());
create policy zone_events_insert_own_child on zone_events for insert
  with check (is_own_child(child_id));
```

- [ ] **Step 2: Write `supabase/tests/0002_safe_zones_and_zone_events.test.sql`**

Reuse the Task 1 fixtures (re-insert them at the top of this file too, since
each test file runs against a fresh local database). Assert:
- parent can insert a `safe_zones` row for the child and read it back.
- the child device account can `select` that same `safe_zones` row.
- the child device account can `insert` a `zone_events` row for its own
  `child_id` but an `insert` for a different, non-existent `child_id` it does
  not own is rejected.
- the parent can `select` the inserted `zone_events` row.

- [ ] **Step 3: Run the test**

Run: `psql "$DATABASE_URL" -f supabase/tests/0002_safe_zones_and_zone_events.test.sql`
Expected: `OK: 0002 tests passed`, no `ASSERTION FAILED`.

- [ ] **Step 4: Commit**

```bash
git add supabase/
git commit -m "feat: add safe_zones/zone_events tables with RLS"
```

---

### Task 3: `locations` + 180-day retention job

**Files:**
- Create: `supabase/migrations/0003_locations_and_retention.sql`
- Create: `supabase/tests/0003_locations_and_retention.test.sql`

**Interfaces:**
- Consumes: `is_parent()`, `is_own_child(uuid)` from Task 1.
- Produces: table `locations(id bigint pk, child_id uuid, lat double
  precision, lng double precision, battery_pct integer, wifi_ssid text,
  wifi_is_risky boolean, recorded_at timestamptz)`; function
  `purge_old_locations() returns void`, scheduled via `pg_cron`.

- [ ] **Step 1: Write migration `0003_locations_and_retention.sql`**

```sql
create table locations (
  id bigint generated always as identity primary key,
  child_id uuid not null references children(id) on delete cascade,
  lat double precision not null,
  lng double precision not null,
  battery_pct integer,
  wifi_ssid text,
  wifi_is_risky boolean,
  recorded_at timestamptz not null default now()
);
create index locations_child_recorded_idx on locations (child_id, recorded_at desc);

alter table locations enable row level security;

create policy locations_select_for_parents on locations for select
  using (is_parent());
create policy locations_insert_own_child on locations for insert
  with check (is_own_child(child_id));

create extension if not exists pg_cron;

create or replace function purge_old_locations() returns void
language sql security definer as $$
  delete from locations where recorded_at < now() - interval '180 days';
$$;

select cron.schedule('purge_old_locations_daily', '0 3 * * *', 'select purge_old_locations();');
```

- [ ] **Step 2: Write `supabase/tests/0003_locations_and_retention.test.sql`**

Assert:
- child device account can `insert` a `locations` row for its own child and
  cannot `insert` one for a `child_id` it does not own.
- parent can `select` the row; the child device account cannot `select` any
  `locations` row (no select policy is granted to it).
- insert three rows directly via `postgres` role with `recorded_at` at
  `now() - interval '181 days'`, `now() - interval '179 days'`, and `now()`;
  call `select purge_old_locations();`; assert only the 181-day-old row was
  deleted and the other two remain.

- [ ] **Step 3: Run the test**

Run: `psql "$DATABASE_URL" -f supabase/tests/0003_locations_and_retention.test.sql`
Expected: `OK: 0003 tests passed`, no `ASSERTION FAILED`.

- [ ] **Step 4: Commit**

```bash
git add supabase/
git commit -m "feat: add locations table with RLS and 180-day retention job"
```

---

### Task 4: `alerts`

**Files:**
- Create: `supabase/migrations/0004_alerts.sql`
- Create: `supabase/tests/0004_alerts.test.sql`

**Interfaces:**
- Consumes: `is_parent()`, `is_own_child(uuid)` from Task 1.
- Produces: table `alerts(id bigint pk, child_id uuid, alert_type text check
  in ('panic','theft_lock_engaged','battery_critical','risky_wifi',
  'zone_enter','zone_exit','location_permission_revoked','app_uninstalled'),
  payload jsonb, created_at timestamptz, acknowledged_at timestamptz)`.

- [ ] **Step 1: Write migration `0004_alerts.sql`**

```sql
create table alerts (
  id bigint generated always as identity primary key,
  child_id uuid not null references children(id) on delete cascade,
  alert_type text not null check (alert_type in (
    'panic', 'theft_lock_engaged', 'battery_critical', 'risky_wifi',
    'zone_enter', 'zone_exit', 'location_permission_revoked', 'app_uninstalled'
  )),
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  acknowledged_at timestamptz
);

alter table alerts enable row level security;

create policy alerts_select_for_parents on alerts for select
  using (is_parent());
create policy alerts_update_ack_for_parents on alerts for update
  using (is_parent()) with check (is_parent());
create policy alerts_insert_own_child on alerts for insert
  with check (is_own_child(child_id));
```

- [ ] **Step 2: Write `supabase/tests/0004_alerts.test.sql`**

Assert:
- child device account can `insert` a `panic` alert for its own child; cannot
  insert one for another `child_id`.
- parent can `select` it and `update` its `acknowledged_at`.
- child device account cannot `update` `acknowledged_at` on any alert (no
  update policy granted to it).

- [ ] **Step 3: Run the test**

Run: `psql "$DATABASE_URL" -f supabase/tests/0004_alerts.test.sql`
Expected: `OK: 0004 tests passed`, no `ASSERTION FAILED`.

- [ ] **Step 4: Commit**

```bash
git add supabase/
git commit -m "feat: add alerts table with RLS"
```

---

### Task 5: `app_usage`

**Files:**
- Create: `supabase/migrations/0005_app_usage.sql`
- Create: `supabase/tests/0005_app_usage.test.sql`

**Interfaces:**
- Consumes: `is_parent()`, `is_own_child(uuid)` from Task 1.
- Produces: table `app_usage(id bigint pk, child_id uuid, app_package text,
  usage_date date, duration_minutes integer, unique(child_id, app_package,
  usage_date))`.

- [ ] **Step 1: Write migration `0005_app_usage.sql`**

```sql
create table app_usage (
  id bigint generated always as identity primary key,
  child_id uuid not null references children(id) on delete cascade,
  app_package text not null,
  usage_date date not null,
  duration_minutes integer not null default 0,
  unique (child_id, app_package, usage_date)
);

alter table app_usage enable row level security;

create policy app_usage_select_for_parents on app_usage for select
  using (is_parent());
create policy app_usage_upsert_own_child on app_usage for insert
  with check (is_own_child(child_id));
create policy app_usage_update_own_child on app_usage for update
  using (is_own_child(child_id)) with check (is_own_child(child_id));
```

- [ ] **Step 2: Write `supabase/tests/0005_app_usage.test.sql`**

Assert:
- child device account can `insert` a row for its own child, then `update`
  (upsert pattern: `insert ... on conflict (child_id, app_package,
  usage_date) do update set duration_minutes = ...`) that same row.
- child device account cannot insert/update a row for a different
  `child_id`.
- parent can `select` all rows for its children.

- [ ] **Step 3: Run the test**

Run: `psql "$DATABASE_URL" -f supabase/tests/0005_app_usage.test.sql`
Expected: `OK: 0005 tests passed`, no `ASSERTION FAILED`.

- [ ] **Step 4: Commit**

```bash
git add supabase/
git commit -m "feat: add app_usage table with RLS"
```

---

### Task 6: `device_commands` + `push_tokens`

**Files:**
- Create: `supabase/migrations/0006_device_commands_and_push_tokens.sql`
- Create: `supabase/tests/0006_device_commands_and_push_tokens.test.sql`

**Interfaces:**
- Consumes: `is_parent()`, `is_own_child(uuid)` from Task 1.
- Produces: tables `device_commands(id uuid pk, child_id uuid, command_type
  text check in ('lock','unlock'), requested_by uuid references
  parents(user_id), status text check in
  ('pending','delivered','acknowledged'), created_at, delivered_at,
  acknowledged_at)`, `push_tokens(id uuid pk, owner_user_id uuid references
  auth.users(id), fcm_token text, updated_at timestamptz, unique
  (owner_user_id, fcm_token))`.

- [ ] **Step 1: Write migration `0006_device_commands_and_push_tokens.sql`**

```sql
create table device_commands (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references children(id) on delete cascade,
  command_type text not null check (command_type in ('lock', 'unlock')),
  requested_by uuid not null references parents(user_id),
  status text not null default 'pending' check (status in ('pending', 'delivered', 'acknowledged')),
  created_at timestamptz not null default now(),
  delivered_at timestamptz,
  acknowledged_at timestamptz
);

create table push_tokens (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid not null references auth.users(id) on delete cascade,
  fcm_token text not null,
  updated_at timestamptz not null default now(),
  unique (owner_user_id, fcm_token)
);

alter table device_commands enable row level security;
alter table push_tokens enable row level security;

create policy device_commands_select_for_parents on device_commands for select
  using (is_parent());
create policy device_commands_insert_for_parents on device_commands for insert
  with check (is_parent() and requested_by = auth.uid());
create policy device_commands_select_own_child on device_commands for select
  using (is_own_child(child_id));
create policy device_commands_update_status_own_child on device_commands for update
  using (is_own_child(child_id)) with check (is_own_child(child_id));

create policy push_tokens_manage_own on push_tokens for all
  using (owner_user_id = auth.uid()) with check (owner_user_id = auth.uid());
```

- [ ] **Step 2: Write `supabase/tests/0006_device_commands_and_push_tokens.test.sql`**

Assert:
- parent can `insert` a `lock` command for its child with
  `requested_by = auth.uid()`; a parent cannot insert one with
  `requested_by` set to the other parent's `user_id`.
- the child device account can `select` its own pending command and
  `update` its `status` to `delivered` then `acknowledged`.
- a child device account cannot `insert` a `device_commands` row at all (no
  insert policy is granted to it).
- any user can `insert`/`update` only their own `push_tokens` row; cannot
  touch another user's.

- [ ] **Step 3: Run the test**

Run: `psql "$DATABASE_URL" -f supabase/tests/0006_device_commands_and_push_tokens.test.sql`
Expected: `OK: 0006 tests passed`, no `ASSERTION FAILED`.

- [ ] **Step 4: Commit**

```bash
git add supabase/
git commit -m "feat: add device_commands/push_tokens tables with RLS"
```

---

### Task 7: Seed data for the real family + apply to the hosted Supabase project

**Files:**
- Create: `supabase/seed.sql`
- Modify: none (deployment step, not code)

**Interfaces:**
- Consumes: all tables from Tasks 1–6.
- Produces: nothing new in code; this task applies migrations to the real
  hosted Supabase project and provisions the real accounts.

- [ ] **Step 1: Write `supabase/seed.sql`** with placeholder `insert`
  statements for two parent rows and two children rows (Vitor, Maria
  Clara), matching the schema from Tasks 1–6, for use in future local-dev
  resets — not run against the hosted project.

- [ ] **Step 2: Create the hosted Supabase project** (or confirm the target
  project with Edson if one already exists for this purpose), then run
  `supabase link` and `supabase db push` to apply all six migrations to it.

- [ ] **Step 3: In the hosted project's Auth, create the real accounts**:
  Edson's parent account, the esposa's parent account, and one device
  account per child (Vitor, Maria Clara) — then insert the matching
  `parents` and `children` rows via the SQL editor (not `seed.sql`, which is
  dev-only).

- [ ] **Step 4: Confirm RLS is enabled on every table**

Run (in the hosted project's SQL editor):
```sql
select tablename, rowsecurity from pg_tables
where schemaname = 'public'
  and tablename in ('parents','children','safe_zones','zone_events',
                     'locations','alerts','app_usage','device_commands','push_tokens');
```
Expected: `rowsecurity = true` for every row.

- [ ] **Step 5: Commit**

```bash
git add supabase/seed.sql
git commit -m "chore: add dev seed data for backend local testing"
```

---

## Self-Review Notes

- **Spec coverage:** every Goal that needs backend state (location, safe
  zones, battery/Wi-Fi via `locations`, app usage time, panic/theft alerts,
  remote lock/unlock, shared parent access, 18-year birthdate protection,
  180-day retention) has a table and RLS policy. The Android app and web
  dashboard plans consume this schema; UI, Firebase push delivery, and the
  Kotlin/Next.js code itself are out of scope for this plan by design.
- **Review Focus coverage:** cross-child isolation, birthdate protection,
  `device_commands` origin, retention boundary, and shared parent visibility
  each have a dedicated assertion in Tasks 1, 1, 6, 3, and 1/2 respectively.
- **Proportion:** this plan is schema-and-policy heavy because the spec's
  core guarantee (no one outside the two parents touches a child's data) is
  entirely enforced here, in SQL, not in the two client apps built next.
