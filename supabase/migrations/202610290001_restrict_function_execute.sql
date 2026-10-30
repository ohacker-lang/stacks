-- Supabase grants EXECUTE on new public functions to anon and authenticated
-- directly, so the earlier "revoke all ... from public" statements left every
-- SECURITY DEFINER helper callable through /rest/v1/rpc by signed-out
-- visitors. No policy for anon uses these helpers, so only the waitlist RPCs
-- the website calls with the publishable key stay open to anon.

do $$
declare
  fn regprocedure;
begin
  for fn in
    select p.oid::regprocedure
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosecdef
      and p.proname not in ('waitlist_username_available', 'reserve_waitlist_username')
  loop
    execute format('revoke execute on function %s from anon', fn);
  end loop;
end;
$$;

-- Server-only helpers: price-alert reconciliation runs from Edge Functions
-- with the service role, media-path checks run inside other functions, and
-- the limit functions are triggers (EXECUTE is checked when a trigger is
-- created, not when it fires).
revoke execute on function public.reconcile_price_alert_entitlement(uuid) from authenticated;
revoke execute on function public.is_stack_item_media_path(uuid, text) from authenticated;
revoke execute on function public.enforce_stack_item_limit() from authenticated;
revoke execute on function public.enforce_stack_collaborator_limit() from authenticated;
revoke execute on function public.enforce_stack_invite_limit() from authenticated;

-- New functions must be granted to anon explicitly from now on.
alter default privileges in schema public revoke execute on functions from anon;
