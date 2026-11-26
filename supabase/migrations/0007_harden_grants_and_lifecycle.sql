-- Final whole-branch review fix wave. Four independent hardening changes:
--
-- 1. Grants across Tasks 1-6 were only ever added, never baselined/reset, so
--    nothing ever confirmed they weren't wider than intended in practice
--    (e.g. against whatever ACL defaults the hosted cloud project started
--    with before these migrations ran). Revoke everything from `anon`/
--    `authenticated` on every table, then re-grant exactly what each
--    table's own policies need, copied verbatim from migrations 0001-0006.
-- 2. `purge_old_locations()` is `security definer` and still had its default
--    PUBLIC execute grant, reachable via PostgREST RPC
--    (`/rpc/purge_old_locations`) by anyone holding the `anon` key shipped
--    inside the Android APK. Revoke it.
-- 3. Enforce the spec's 18-year monitoring cutoff directly in
--    `is_own_child()`, the one function every child-role RLS policy across
--    every table calls — `create or replace` keeps the exact same
--    signature, so no existing policy needs to change.
-- 4. Two integrity constraints: bound `locations.recorded_at` against
--    far-future client-supplied timestamps, and tie `zone_events.zone_id`
--    to the same `child_id` as the event via a composite foreign key.

-- --- (1) Revoke-all-then-re-grant-exactly, per table ------------------------

revoke all on parents from anon, authenticated;
revoke all on children from anon, authenticated;
revoke all on safe_zones from anon, authenticated;
revoke all on zone_events from anon, authenticated;
revoke all on locations from anon, authenticated;
revoke all on alerts from anon, authenticated;
revoke all on app_usage from anon, authenticated;
revoke all on device_commands from anon, authenticated;
revoke all on push_tokens from anon, authenticated;

-- parents: only parents_select_self (select).
grant select on parents to authenticated;

-- children: children_all_for_parents ('for all') + children_select_own (select).
grant select, insert, update, delete on children to authenticated;

-- safe_zones: safe_zones_all_for_parents ('for all') + safe_zones_select_own_child (select).
grant select, insert, update, delete on safe_zones to authenticated;

-- zone_events: zone_events_select_for_parents (select) + zone_events_insert_own_child (insert).
grant select, insert on zone_events to authenticated;

-- locations: locations_select_for_parents (select) + locations_insert_own_child (insert).
grant select, insert on locations to authenticated;

-- alerts: alerts_select_for_parents (select) + alerts_insert_own_child (insert)
-- unchanged; alerts_update_ack_for_parents narrowed here to column-level,
-- matching the device_commands pattern -- parents are only meant to ack an
-- alert, not rewrite its child_id/alert_type/payload/created_at.
grant select, insert on alerts to authenticated;
grant update (acknowledged_at) on alerts to authenticated;

-- app_usage: app_usage_select_for_parents + app_usage_select_own_child (select)
-- + app_usage_upsert_own_child (insert) + app_usage_update_own_child (update).
grant select, insert, update on app_usage to authenticated;

-- device_commands: re-asserting Task 6's fix-round grant unchanged -- select
-- + insert ungated, update column-scoped to (status, delivered_at,
-- acknowledged_at) only, so a child device account can never rewrite
-- command_type/requested_by on its own row.
grant select, insert on device_commands to authenticated;
grant update (status, delivered_at, acknowledged_at) on device_commands to authenticated;

-- push_tokens: push_tokens_manage_own ('for all').
grant select, insert, update, delete on push_tokens to authenticated;

-- --- (2) Close the purge_old_locations() PUBLIC execute gap -----------------

revoke execute on function purge_old_locations() from public, anon, authenticated;

-- --- (3) Enforce the spec's 18-year monitoring cutoff -----------------------
--
-- Every later table's child-role RLS policy calls is_own_child(uuid); fixing
-- it here fixes all of them at once, with no other migration needing to
-- change. `create or replace function` with the identical signature
-- (p_child_id uuid) returns boolean keeps every existing policy working
-- unmodified.

create or replace function is_own_child(p_child_id uuid) returns boolean
language sql security definer stable
set search_path = public as $$
  select exists (
    select 1 from children
    where id = p_child_id
      and device_user_id = auth.uid()
      and birthdate > current_date - interval '18 years'
  );
$$;

-- --- (4a) Bound locations.recorded_at against far-future timestamps --------
--
-- A malicious or buggy child device could otherwise insert a row with
-- recorded_at far in the future, which the 180-day retention job would
-- never purge. 1 day of slack accounts for reasonable clock skew between a
-- child's phone and the server.

alter table locations add constraint locations_recorded_at_not_future
  check (recorded_at <= now() + interval '1 day');

-- --- (4b) Tie zone_events.zone_id to the same child_id as the event --------
--
-- Without this, a child could log an enter/exit event against a sibling's
-- safe zone (a zone_id/child_id pair that doesn't actually belong together).

alter table safe_zones add constraint safe_zones_id_child_id_unique unique (id, child_id);
alter table zone_events add constraint zone_events_zone_child_fk
  foreign key (zone_id, child_id) references safe_zones (id, child_id);
