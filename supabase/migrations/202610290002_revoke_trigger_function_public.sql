-- The Pro limit triggers were still executable by PUBLIC (and so by anon and
-- authenticated). They only run as triggers, so nobody needs EXECUTE on them.
revoke execute on function public.enforce_stack_item_limit() from public;
revoke execute on function public.enforce_stack_collaborator_limit() from public;
revoke execute on function public.enforce_stack_invite_limit() from public;
