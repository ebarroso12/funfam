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
language sql security definer stable
set search_path = public
as $$
  select exists (select 1 from parents where user_id = auth.uid());
$$;

create or replace function is_own_child(p_child_id uuid) returns boolean
language sql security definer stable
set search_path = public
as $$
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

-- Supabase's default table grants for the `authenticated` role (Dxtm) do not
-- include select/insert/update, so without these grants every query is
-- blocked before RLS is even evaluated. Grant only the operations each
-- table's policies actually use today (least privilege): `parents` only
-- has a select-self policy, so only select is granted; `children` has a
-- `for all` policy for parents, so all four are granted there. RLS is
-- still the layer that decides which rows/operations are actually allowed
-- within what's granted here — but if a future policy on `parents` ever
-- becomes permissive for insert/update/delete, the grant would need to be
-- widened to match, so keep this comment in sync with the policies above.
grant select on parents to authenticated;
grant select, insert, update, delete on children to authenticated;
