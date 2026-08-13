-- Run against a local Supabase database after migrations and seed:
--   supabase db reset
--   psql "$LOCAL_DB_URL" -f supabase/tests/rls_access.sql
-- The transaction always rolls back.

begin;

create or replace function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$
begin
  if condition is distinct from true then
    raise exception 'RLS assertion failed: %', message;
  end if;
end;
$$;

create or replace function pg_temp.assert_false(condition boolean, message text)
returns void language plpgsql as $$
begin
  if condition is distinct from false then
    raise exception 'RLS assertion failed: %', message;
  end if;
end;
$$;

-- Owen owns a private Stack, can see a public Stack, and cannot query a
-- link-only Stack without its narrow RPC.
set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-4000-8000-000000000001', true);
select pg_temp.assert_true(
  exists (select 1 from public.stacks where id = '30000000-0000-4000-8000-000000000001'),
  'owner reads their private Stack'
);
select pg_temp.assert_true(
  exists (select 1 from public.stacks where id = '30000000-0000-4000-8000-000000000002'),
  'public Stack is readable'
);
select pg_temp.assert_false(
  exists (select 1 from public.stacks where id = '30000000-0000-4000-8000-000000000003'),
  'link-only Stack is not readable through table RLS'
);
select pg_temp.assert_true(
  (select public.get_link_only_stack('40000000-0000-4000-8000-000000000003'::uuid) is not null),
  'link-only Stack requires and accepts its token'
);

reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub', '20000000-0000-4000-8000-000000000002', true);
select pg_temp.assert_true(
  exists (select 1 from public.stacks where id = '30000000-0000-4000-8000-000000000001'),
  'accepted editor reads a private Stack'
);
select pg_temp.assert_true(
  public.can_edit_stack('30000000-0000-4000-8000-000000000001'),
  'accepted editor can edit items'
);

-- The following update must fail because only the owner may alter sharing.
savepoint editor_cannot_publish;
do $$
begin
  begin
    update public.stacks
    set visibility = 'public'
    where id = '30000000-0000-4000-8000-000000000001';
    raise exception 'Expected editor visibility change to fail.';
  exception when insufficient_privilege then
    null;
  end;
end;
$$;
rollback to savepoint editor_cannot_publish;

reset role;
rollback;
