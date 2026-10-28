-- Claim state is derived exclusively from gift_claims. Owners and editors may
-- edit product metadata, but no client may fake or clear this field directly.
create or replace function public.protect_stack_item_claim_status()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if new.claim_status is distinct from old.claim_status
    and pg_trigger_depth() = 1 then
    raise exception 'Claim state can only be changed through a gift claim.' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists stack_items_protect_claim_status on public.stack_items;
create trigger stack_items_protect_claim_status
before update of claim_status on public.stack_items
for each row execute function public.protect_stack_item_claim_status();

revoke all on function public.protect_stack_item_claim_status() from public;

