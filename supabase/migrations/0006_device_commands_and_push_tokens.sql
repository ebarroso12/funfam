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

-- Supabase's default table grants for the `authenticated` role do not
-- include select/insert/update/delete, so without these grants every query
-- is blocked before RLS is even evaluated (see Task 1's migration for the
-- full explanation).
-- device_commands: select used by device_commands_select_for_parents and
-- device_commands_select_own_child; insert used by
-- device_commands_insert_for_parents; update used by
-- device_commands_update_status_own_child. No policy uses delete.
grant select, insert, update on device_commands to authenticated;
-- push_tokens: the single `for all` policy (push_tokens_manage_own) covers
-- select, insert, update, and delete.
grant select, insert, update, delete on push_tokens to authenticated;
