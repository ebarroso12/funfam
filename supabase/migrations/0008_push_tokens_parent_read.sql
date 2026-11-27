-- The web dashboard's "bloquear"/"desbloquear" action needs to read the
-- target child's FCM push token server-side, so it can send an instant
-- push instead of relying solely on the device's own polling fallback.
-- push_tokens had no select policy reachable by a parent at all --
-- push_tokens_manage_own (migration 0006) only lets a row's own owner
-- (the device account itself) see it. Add a parent-scoped select policy,
-- narrowly limited to push tokens owned by one of that family's own
-- children's device accounts -- never any other user's token.
--
-- No grant change needed: `grant select, insert, update, delete on
-- push_tokens to authenticated` already covers select (migration 0006);
-- RLS was the only thing missing.
create policy push_tokens_select_for_parents_of_child on push_tokens for select
  using (
    is_parent() and exists (
      select 1 from children where device_user_id = push_tokens.owner_user_id
    )
  );
