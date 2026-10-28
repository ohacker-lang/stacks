-- New Stacks are wishlists; existing rows retain their chosen mode.
alter table public.stacks alter column wishlist_mode set default true;

-- Do not copy recipient claim state onto owner-readable product rows.
drop trigger if exists gift_claims_sync_item_status on public.gift_claims;
drop trigger if exists stack_items_protect_claim_status on public.stack_items;
drop function if exists public.sync_stack_item_claim_status();
drop function if exists public.protect_stack_item_claim_status();

-- Link-only readers see only availability. A signed-in owner remains blind,
-- although the same person can still open the secret URL anonymously.
create or replace function public.get_link_only_stack(link_token uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare result jsonb;
begin
  select jsonb_build_object(
    'stack', jsonb_build_object(
      'id', s.id, 'owner_id', s.owner_id, 'title', s.title,
      'summary', s.summary, 'visibility', s.visibility,
      'wishlist_mode', s.wishlist_mode, 'created_at', s.created_at,
      'updated_at', s.updated_at
    ),
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', i.id, 'stack_id', i.stack_id, 'title', i.title,
        'brand', i.brand, 'description', i.description,
        'price', i.price, 'currency_code', i.currency_code,
        'size_text', i.size_text, 'source_url', i.source_url,
        'buy_url', i.buy_url, 'affiliate_url', i.affiliate_url,
        'original_image_path', i.original_image_path,
        'removed_background_image_path', i.removed_background_image_path,
        'removal_status', i.removal_status, 'placement_x', i.placement_x,
        'placement_y', i.placement_y, 'placement_scale', i.placement_scale,
        'rotation_degrees', i.rotation_degrees,
        'has_custom_placement', i.has_custom_placement,
        'source_type', i.source_type, 'needs_link', i.needs_link,
        'claim_status', case when auth.uid() = s.owner_id then null else (
          select c.status from public.gift_claims c
          where c.item_id = i.id and c.status in ('claimed', 'purchased')
          limit 1
        ) end,
        'created_at', i.created_at, 'updated_at', i.updated_at
      ) order by i.created_at)
      from public.stack_items i where i.stack_id = s.id
    ), '[]'::jsonb)
  ) into result
  from public.stacks s
  where s.visibility = 'link_only'
    and s.public_link_token = link_token
    and not public.is_blocked_pair(s.owner_id, auth.uid());

  if result is null then
    raise exception 'This wishlist is unavailable.' using errcode = 'P0001';
  end if;
  return result;
end;
$$;

-- Recipients of a public or token-authorized wishlist may learn only whether
-- each product is available. No claimant identifiers or dates leave this RPC.
create or replace function public.get_wishlist_claim_states(
  target_stack_id uuid, link_token uuid default null
)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare target_stack public.stacks; result jsonb;
begin
  select * into target_stack from public.stacks where id = target_stack_id;
  if target_stack.id is null or not target_stack.wishlist_mode
    or target_stack.owner_id = auth.uid()
    or public.is_blocked_pair(target_stack.owner_id, auth.uid())
    or not (target_stack.visibility = 'public'
      or (target_stack.visibility = 'link_only' and link_token = target_stack.public_link_token)
      or public.can_view_stack(target_stack_id)) then
    return '[]'::jsonb;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
    'item_id', i.id,
    'status', (select c.status from public.gift_claims c
      where c.item_id = i.id and c.status in ('claimed', 'purchased') limit 1)
  )), '[]'::jsonb) into result
  from public.stack_items i where i.stack_id = target_stack_id;
  return result;
end;
$$;

create or replace function public.rotate_wishlist_link(target_stack_id uuid, revoke_link boolean default false)
returns uuid
language plpgsql volatile security definer set search_path = public
as $$
declare next_token uuid;
begin
  update public.stacks
  set public_link_token = gen_random_uuid(),
      visibility = case when revoke_link then 'private'::public.stack_visibility
        else 'link_only'::public.stack_visibility end
  where id = target_stack_id and owner_id = auth.uid() and wishlist_mode
  returning public_link_token into next_token;
  if next_token is null then raise exception 'Wishlist unavailable.' using errcode = '42501'; end if;
  return next_token;
end;
$$;

alter table public.stack_items drop column if exists claim_status;
revoke all on function public.get_wishlist_claim_states(uuid, uuid) from public;
grant execute on function public.get_wishlist_claim_states(uuid, uuid) to anon, authenticated;
revoke all on function public.rotate_wishlist_link(uuid, boolean) from public;
grant execute on function public.rotate_wishlist_link(uuid, boolean) to authenticated;
