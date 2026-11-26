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

-- Controller ruling (not in the plan's original brief SQL): Postgres
-- requires the existing target row to be visible under a SELECT-applicable
-- policy before an UPDATE -- including the DO UPDATE path of
-- `insert ... on conflict (...) do update ...` -- consults the UPDATE
-- policy's own USING/WITH CHECK clauses. Without this, the child device
-- account's own upsert (required by this task's test) either affects 0
-- rows (plain update) or raises an RLS violation (on-conflict update),
-- confirmed by direct experiment during implementation. This policy only
-- lets a child see its own already-self-reported usage duration -- never
-- another child's -- so it exposes nothing new.
create policy app_usage_select_own_child on app_usage for select
  using (is_own_child(child_id));

-- Supabase's default table grants for the `authenticated` role do not
-- include select/insert/update/delete, so without these grants every query
-- is blocked before RLS is even evaluated (see Task 1's migration for the
-- full explanation). `app_usage` has select policies for parents and the
-- child's own device account, plus insert/update policies for the child's
-- own device account, so the union across all four is select, insert, and
-- update -- no delete.
grant select, insert, update on app_usage to authenticated;
