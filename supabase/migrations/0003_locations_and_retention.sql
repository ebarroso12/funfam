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

-- security definer so the daily cron job (running as its own role) can
-- delete rows for every child regardless of RLS; search_path is pinned to
-- prevent a search_path hijack from redirecting `locations` to another
-- table (same gap Task 1's is_parent()/is_own_child() had before review
-- caught it -- the plan's own literal SQL for this function omits it).
create or replace function purge_old_locations() returns void
language sql security definer
set search_path = public
as $$
  delete from locations where recorded_at < now() - interval '180 days';
$$;

select cron.schedule('purge_old_locations_daily', '0 3 * * *', 'select purge_old_locations();');

-- Supabase's default table grants for the `authenticated` role do not
-- include select/insert/update/delete, so without these grants every query
-- is blocked before RLS is even evaluated (see Task 1's migration for the
-- full explanation). `locations` has a select-only policy for parents and
-- an insert-only policy for the child device account, so the union across
-- both is select and insert only -- no update, no delete.
grant select, insert on locations to authenticated;
