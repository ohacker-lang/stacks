-- Complete wishlist sharing and claiming.
-- Claimant identity remains private; viewers only receive the item's state.

alter table public.stack_items
  add column if not exists claim_status public.gift_claim_status;

update public.stack_items i
set claim_status = (
  select c.status
  from public.gift_claims c
  where c.item_id = i.id
    and c.status in ('claimed', 'purchased')
  order by c.updated_at desc
  limit 1
)
where exists (
  select 1
  from public.gift_claims c
  where c.item_id = i.id
    and c.status in ('claimed', 'purchased')
);

create or replace function public.sync_stack_item_claim_status()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  affected_item_id uuid;
  next_status public.gift_claim_status;
begin
  affected_item_id := coalesce(new.item_id, old.item_id);

  select c.status into next_status
  from public.gift_claims c
  where c.item_id = affected_item_id
    and c.status in ('claimed', 'purchased')
  order by c.updated_at desc
  limit 1;

  update public.stack_items
  set claim_status = next_status
  where id = affected_item_id
    and claim_status is distinct from next_status;

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

drop trigger if exists gift_claims_sync_item_status on public.gift_claims;
create trigger gift_claims_sync_item_status
after insert or update of status or delete on public.gift_claims
for each row execute function public.sync_stack_item_claim_status();

-- One transaction owns the entire claim decision. The row lock plus the
-- partial unique index guarantees that two visitors cannot claim together.
create or replace function public.claim_wishlist_item(
  target_stack_id uuid,
  target_item_id uuid,
  link_token uuid default null,
  claim_name text default null
)
returns public.gift_claims
language plpgsql
security definer set search_path = public
as $$
declare
  target_stack public.stacks;
  target_item public.stack_items;
  created_claim public.gift_claims;
begin
  if auth.uid() is null then
    raise exception 'Sign in is required.' using errcode = '42501';
  end if;

  if char_length(trim(coalesce(claim_name, ''))) not between 1 and 80 then
    raise exception 'A name is required.' using errcode = 'P0001';
  end if;

  select * into target_stack
  from public.stacks
  where id = target_stack_id;

  if target_stack.id is null
    or not target_stack.wishlist_mode
    or target_stack.owner_id = auth.uid()
    or public.is_blocked_pair(target_stack.owner_id, auth.uid()) then
    raise exception 'This wishlist is unavailable.' using errcode = 'P0001';
  end if;

  if not (
    public.can_view_stack(target_stack.id)
    or (
      target_stack.visibility = 'link_only'
      and link_token is not null
      and target_stack.public_link_token = link_token
    )
  ) then
    raise exception 'This wishlist is unavailable.' using errcode = 'P0001';
  end if;

  select * into target_item
  from public.stack_items
  where id = target_item_id
    and stack_id = target_stack.id
  for update;

  if target_item.id is null then
    raise exception 'That item is unavailable.' using errcode = 'P0001';
  end if;

  if exists (
    select 1 from public.gift_claims c
    where c.item_id = target_item.id
      and c.status in ('claimed', 'purchased')
  ) then
    raise exception 'This item has already been claimed.' using errcode = '23505';
  end if;

  insert into public.gift_claims (
    stack_id,
    item_id,
    claimer_id,
    claimer_name,
    status
  ) values (
    target_stack.id,
    target_item.id,
    auth.uid(),
    trim(claim_name),
    'claimed'
  )
  returning * into created_claim;

  return created_claim;
end;
$$;

-- Link-only readers receive the public claim state but never the claimant,
-- timestamp, message, or claim identifier.
create or replace function public.get_link_only_stack(link_token uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  result jsonb;
begin
  select jsonb_build_object(
    'stack', jsonb_build_object(
      'id', s.id,
      'owner_id', s.owner_id,
      'title', s.title,
      'summary', s.summary,
      'visibility', s.visibility,
      'wishlist_mode', s.wishlist_mode,
      'created_at', s.created_at,
      'updated_at', s.updated_at
    ),
    'items', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', i.id,
            'stack_id', i.stack_id,
            'title', i.title,
            'brand', i.brand,
            'description', i.description,
            'price', i.price,
            'currency_code', i.currency_code,
            'size_text', i.size_text,
            'source_url', i.source_url,
            'buy_url', i.buy_url,
            'affiliate_url', i.affiliate_url,
            'original_image_path', i.original_image_path,
            'removed_background_image_path', i.removed_background_image_path,
            'removal_status', i.removal_status,
            'placement_x', i.placement_x,
            'placement_y', i.placement_y,
            'placement_scale', i.placement_scale,
            'rotation_degrees', i.rotation_degrees,
            'has_custom_placement', i.has_custom_placement,
            'source_type', i.source_type,
            'needs_link', i.needs_link,
            'claim_status', i.claim_status,
            'created_at', i.created_at,
            'updated_at', i.updated_at
          ) order by i.created_at
        )
        from public.stack_items i
        where i.stack_id = s.id
      ),
      '[]'::jsonb
    )
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

-- Collaborators must be able to display the owner's public-facing identity
-- even when that owner has Discover disabled.
drop policy if exists "profiles viewable by self or discovery users" on public.profiles;
create policy "profiles viewable through an allowed relationship"
on public.profiles for select to authenticated
using (
  id = auth.uid()
  or (discovery_enabled and not public.is_blocked_pair(id, auth.uid()))
  or exists (
    select 1
    from public.stacks s
    join public.stack_collaborators c on c.stack_id = s.id
    where s.owner_id = profiles.id
      and c.user_id = auth.uid()
      and c.accepted_at is not null
      and not public.is_blocked_pair(s.owner_id, auth.uid())
  )
);

revoke all on function public.sync_stack_item_claim_status() from public;
revoke all on function public.claim_wishlist_item(uuid, uuid, uuid, text) from public;
grant execute on function public.claim_wishlist_item(uuid, uuid, uuid, text) to authenticated;
grant execute on function public.get_link_only_stack(uuid) to authenticated;

-- Repair the earlier link-only helper after claims moved to a partial unique
-- index. Keep the public signature for older clients while sharing the same
-- secure transaction as the current endpoint.
create or replace function public.claim_link_only_item(
  link_token uuid,
  target_item_id uuid,
  claim_name text,
  claim_message text default null
)
returns public.gift_claims
language plpgsql security definer set search_path = public
as $$
declare
  target_stack_id uuid;
  created_claim public.gift_claims;
begin
  select s.id into target_stack_id
  from public.stacks s
  where s.visibility = 'link_only'
    and s.public_link_token = link_token;

  created_claim := public.claim_wishlist_item(
    target_stack_id,
    target_item_id,
    link_token,
    claim_name
  );

  if nullif(trim(coalesce(claim_message, '')), '') is not null then
    update public.gift_claims c
    set private_message = left(trim(claim_message), 500)
    where c.id = created_claim.id
      and c.claimer_id = auth.uid()
    returning c.* into created_claim;
  end if;

  return created_claim;
end;
$$;

-- Resolve the output-column/table-column ambiguity in the original invite
-- function by targeting the named primary-key constraint.
create or replace function public.accept_collaboration_invite(invite_token uuid)
returns table (stack_id uuid, permission public.collaborator_permission)
language plpgsql
security definer
set search_path = public
as $$
declare
  invitation public.collaboration_invites%rowtype;
  stack_owner uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required.' using errcode = '28000';
  end if;

  select * into invitation
  from public.collaboration_invites ci
  where ci.token = invite_token
  for update;

  if not found then
    raise exception 'This invitation is unavailable.' using errcode = 'P0002';
  end if;
  if invitation.revoked_at is not null or invitation.accepted_at is not null then
    raise exception 'This invitation has already been used.' using errcode = 'P0001';
  end if;
  if invitation.expires_at <= now() then
    raise exception 'This invitation has expired.' using errcode = 'P0001';
  end if;

  select s.owner_id into stack_owner
  from public.stacks s
  where s.id = invitation.stack_id;
  if stack_owner = auth.uid() then
    raise exception 'You already own this Stack.' using errcode = 'P0001';
  end if;

  insert into public.stack_collaborators (stack_id, user_id, permission, invited_by, accepted_at)
  values (invitation.stack_id, auth.uid(), invitation.permission, invitation.invited_by, now())
  on conflict on constraint stack_collaborators_pkey do update
    set permission = excluded.permission,
        invited_by = excluded.invited_by,
        accepted_at = excluded.accepted_at;

  update public.collaboration_invites ci
  set accepted_by = auth.uid(), accepted_at = now()
  where ci.id = invitation.id;

  return query select invitation.stack_id, invitation.permission;
end;
$$;

revoke all on function public.claim_link_only_item(uuid, uuid, text, text) from public;
grant execute on function public.claim_link_only_item(uuid, uuid, text, text) to authenticated;
revoke all on function public.accept_collaboration_invite(uuid) from public;
grant execute on function public.accept_collaboration_invite(uuid) to authenticated;
