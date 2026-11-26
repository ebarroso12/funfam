create schema if not exists test;

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

-- test.assume_user() switches the session's role (e.g. to "authenticated")
-- so RLS policies are actually exercised. That switched-to role needs
-- USAGE on this schema and EXECUTE on its functions, or every call after
-- the first assume_user() fails with "permission denied for schema test".
grant usage on schema test to public;
grant execute on all functions in schema test to public;
