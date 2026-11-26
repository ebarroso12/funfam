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

-- Supabase's default table grants for the `authenticated` role do not include
-- select/insert/update/delete, so without these grants every query is blocked
-- before RLS is even evaluated (see Task 1's migration for the full
-- explanation). Grant only the operations each table's own policies actually
-- use across all roles that use `authenticated` (least privilege):
-- `safe_zones` has a `for all` policy for parents (needs select/insert/
-- update/delete) and a select-only policy for the child (needs select), so
-- the union across both is all four operations. `zone_events` has a
-- select-only policy for parents and an insert-only policy for the child, so
-- the union is select and insert only -- no update, no delete.
grant select, insert, update, delete on safe_zones to authenticated;
grant select, insert on zone_events to authenticated;
