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

-- Supabase's default table grants for the `authenticated` role do not
-- include select/insert/update/delete, so without these grants every query
-- is blocked before RLS is even evaluated (see Task 1's migration for the
-- full explanation). `alerts` has a select policy and an update (ack)
-- policy for parents and an insert-only policy for the child device
-- account, so the union across all three is select, insert, and update --
-- no delete.
grant select, insert, update on alerts to authenticated;
