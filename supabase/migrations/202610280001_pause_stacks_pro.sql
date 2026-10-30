-- Stacks Pro is paused: every account gets Pro limits until it launches.
-- The item, collaborator, invite and price-alert limits all ask one of these
-- two functions, so redefining them lifts every limit without dropping the
-- triggers or the pro_entitlements table. To resume Pro, restore the bodies
-- from 202609160001_stacks_pro_limits.sql and 202610040001_price_alerts.sql
-- in a new migration and set StacksPro.isEnabled back to true in the app.

create or replace function public.stack_owner_has_pro(target_stack uuid)
returns boolean language sql stable security definer
set search_path = public as $$
  select true;
$$;

create or replace function public.user_has_pro(target_user uuid)
returns boolean language sql stable security definer
set search_path = public as $$
  select true;
$$;

-- Reactivate any alerts that were paused for lack of Pro.
update public.price_alerts
  set status = 'active', next_check_at = least(next_check_at, now()), updated_at = now()
  where status = 'pro_required';
