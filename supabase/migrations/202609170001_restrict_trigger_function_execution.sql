-- Trigger handlers run from their triggers; clients do not need to invoke
-- their SECURITY DEFINER bodies as public RPCs.
revoke execute on function public.handle_new_user()
  from public, anon, authenticated;
revoke execute on function public.protect_stack_collaboration_setting()
  from public, anon, authenticated;
revoke execute on function public.protect_stack_item_claim_status()
  from public, anon, authenticated;
revoke execute on function public.protect_stack_security_fields()
  from public, anon, authenticated;
revoke execute on function public.revoke_invites_when_collaboration_disabled()
  from public, anon, authenticated;
revoke execute on function public.sync_stack_item_claim_status()
  from public, anon, authenticated;
