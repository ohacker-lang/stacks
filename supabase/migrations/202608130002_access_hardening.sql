-- Stacks V1 access hardening.
-- This migration deliberately keeps `stack-media` private. Clients receive
-- signed URLs only from authenticated edge functions after access is checked.

alter table public.stacks
  add column if not exists copied_from_stack_id uuid references public.stacks(id) on delete set null;

create index if not exists stacks_copied_from_idx
  on public.stacks (copied_from_stack_id)
  where copied_from_stack_id is not null;

-- Public Stacks can be viewed outside Discover, but blocked users must never
-- read an owner's Stack or its items through a direct table query.
create or replace function public.can_view_stack(target_stack_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1
    from public.stacks s
    where s.id = target_stack_id
      and not public.is_blocked_pair(s.owner_id, auth.uid())
      and (
        s.owner_id = auth.uid()
        or s.visibility = 'public'
        or exists (
          select 1 from public.stack_collaborators c
          where c.stack_id = s.id
            and c.user_id = auth.uid()
            and c.accepted_at is not null
        )
      )
  );
$$;

-- Editors can update Stack metadata, but only owners can transfer ownership or
-- publish/change visibility. Items remain editable through their own policies.
create or replace function public.can_update_stack_metadata(
  target_stack_id uuid,
  proposed_owner_id uuid,
  proposed_visibility public.stack_visibility
)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1
    from public.stacks s
    where s.id = target_stack_id
      and s.owner_id = proposed_owner_id
      and (
        s.owner_id = auth.uid()
        or (
          s.visibility = proposed_visibility
          and exists (
            select 1 from public.stack_collaborators c
            where c.stack_id = s.id
              and c.user_id = auth.uid()
              and c.permission = 'editor'
              and c.accepted_at is not null
          )
        )
      )
  );
$$;

-- Editors can refine a Stack but cannot publish it, rotate its share token, or
-- change provenance. Those fields are capability/ownership boundaries.
create or replace function public.protect_stack_security_fields()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if old.owner_id <> auth.uid() then
    if new.owner_id is distinct from old.owner_id
      or new.visibility is distinct from old.visibility
      or new.public_link_token is distinct from old.public_link_token
      or new.copied_from_stack_id is distinct from old.copied_from_stack_id then
      raise exception 'Only the Stack owner can change sharing or ownership.' using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists stacks_protect_security_fields on public.stacks;
create trigger stacks_protect_security_fields
before update on public.stacks
for each row execute function public.protect_stack_security_fields();

create or replace function public.can_claim_stack_item(
  target_stack_id uuid,
  target_item_id uuid
)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1
    from public.stacks s
    join public.stack_items i on i.id = target_item_id and i.stack_id = s.id
    where s.id = target_stack_id
      and s.wishlist_mode
      and s.owner_id <> auth.uid()
      and public.can_view_stack(s.id)
  );
$$;

-- This helper proves possession of a link-only token without granting normal
-- table access. It is also used by media and copy edge functions.
create or replace function public.can_view_link_only_stack(
  link_token uuid,
  target_stack_id uuid
)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1
    from public.stacks s
    where s.id = target_stack_id
      and s.visibility = 'link_only'
      and s.public_link_token = link_token
      and not public.is_blocked_pair(s.owner_id, auth.uid())
  );
$$;

-- Shared media must be attached to an actual Stack item. This prevents a
-- private import/draft file in the same owner/Stack prefix from becoming
-- readable simply because the Stack later becomes public or link-only.
create or replace function public.can_access_stack_item_media(
  target_stack_id uuid,
  target_path text
)
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.can_view_stack(target_stack_id)
    and exists (
      select 1
      from public.stack_items i
      where i.stack_id = target_stack_id
        and (
          i.original_image_path = target_path
          or i.removed_background_image_path = target_path
        )
    );
$$;

create or replace function public.is_stack_item_media_path(
  target_stack_id uuid,
  target_path text
)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1
    from public.stack_items i
    where i.stack_id = target_stack_id
      and (
        i.original_image_path = target_path
        or i.removed_background_image_path = target_path
      )
  );
$$;

-- Never return the link token itself. A leaked payload must not become a
-- reusable capability for someone who only saw it in logs or a screenshot.
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
            'created_at', i.created_at,
            'updated_at', i.updated_at
          ) order by i.created_at
        )
        from public.stack_items i
        where i.stack_id = s.id
      ),
      '[]'::jsonb
    )
  )
  into result
  from public.stacks s
  where s.visibility = 'link_only'
    and s.public_link_token = link_token
    and not public.is_blocked_pair(s.owner_id, auth.uid());

  return result;
end;
$$;

-- Link-only viewers receive narrow RPCs because the ordinary RLS path never
-- grants broad SELECT access to link-only Stacks.
create or replace function public.pin_link_only_stack(link_token uuid)
returns public.stack_pins
language plpgsql security definer set search_path = public
as $$
declare
  pinned public.stack_pins;
begin
  insert into public.stack_pins (stack_id, user_id)
  select s.id, auth.uid()
  from public.stacks s
  where s.visibility = 'link_only'
    and s.public_link_token = link_token
    and not public.is_blocked_pair(s.owner_id, auth.uid())
  on conflict (stack_id, user_id) do update
    set stack_id = excluded.stack_id
  returning * into pinned;

  if pinned.stack_id is null then
    raise exception 'The Stack is unavailable.' using errcode = 'P0001';
  end if;

  return pinned;
end;
$$;

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
  created_claim public.gift_claims;
begin
  if char_length(trim(claim_name)) not between 1 and 80 then
    raise exception 'A name is required.' using errcode = 'P0001';
  end if;

  insert into public.gift_claims (
    stack_id,
    item_id,
    claimer_id,
    claimer_name,
    private_message
  )
  select s.id, i.id, auth.uid(), trim(claim_name), nullif(trim(claim_message), '')
  from public.stacks s
  join public.stack_items i on i.id = target_item_id and i.stack_id = s.id
  where s.visibility = 'link_only'
    and s.wishlist_mode
    and s.public_link_token = link_token
    and s.owner_id <> auth.uid()
    and not public.is_blocked_pair(s.owner_id, auth.uid())
  on conflict (item_id, claimer_id) do update
    set claimer_name = excluded.claimer_name,
        private_message = excluded.private_message,
        status = 'claimed'
  returning * into created_claim;

  if created_claim.id is null then
    raise exception 'This item cannot be claimed.' using errcode = 'P0001';
  end if;

  return created_claim;
end;
$$;

-- Keep relationship queries out of client-side filtering. A public Stack may
-- be shared directly even when its owner opted out of Discover.
create or replace view public.discoverable_stacks
with (security_invoker = true)
as
select s.*
from public.stacks s
join public.profiles p on p.id = s.owner_id
where s.visibility = 'public'
  and p.discovery_enabled
  and not public.is_blocked_pair(s.owner_id, auth.uid());

grant select on public.discoverable_stacks to authenticated;

drop policy if exists "profiles viewable by self or discovery users" on public.profiles;
create policy "profiles viewable by self or discovery users"
on public.profiles for select to authenticated
using (
  id = auth.uid()
  or (discovery_enabled and not public.is_blocked_pair(id, auth.uid()))
);

drop policy if exists "owners update their stacks" on public.stacks;
create policy "owners and editors update stack metadata"
on public.stacks for update to authenticated
using (public.can_edit_stack(id))
with check (public.can_update_stack_metadata(id, owner_id, visibility));

drop policy if exists "collaborators view their relationship" on public.stack_collaborators;
create policy "collaborators view their relationship"
on public.stack_collaborators for select to authenticated
using (
  (user_id = auth.uid() or public.is_stack_owner(stack_id))
  and not exists (
    select 1
    from public.stacks s
    where s.id = stack_id
      and public.is_blocked_pair(s.owner_id, user_id)
  )
);

drop policy if exists "owners manage collaborators" on public.stack_collaborators;
create policy "owners manage non-blocked collaborators"
on public.stack_collaborators for all to authenticated
using (public.is_stack_owner(stack_id))
with check (
  public.is_stack_owner(stack_id)
  and not exists (
    select 1
    from public.stacks s
    where s.id = stack_id
      and public.is_blocked_pair(s.owner_id, user_id)
  )
);

drop policy if exists "viewers create claims" on public.gift_claims;
create policy "eligible viewers create claims"
on public.gift_claims for insert to authenticated
with check (
  claimer_id = auth.uid()
  and public.can_claim_stack_item(stack_id, item_id)
);

drop policy if exists "users create own follows" on public.follows;
create policy "users create own follows"
on public.follows for insert to authenticated
with check (
  follower_id = auth.uid()
  and follower_id <> followed_user_id
  and not public.is_blocked_pair(follower_id, followed_user_id)
);

drop policy if exists "users manage their imports" on public.product_imports;
create policy "users view their imports"
on public.product_imports for select to authenticated
using (user_id = auth.uid());
create policy "users create imports for editable stacks"
on public.product_imports for insert to authenticated
with check (
  user_id = auth.uid()
  and (stack_id is null or public.can_edit_stack(stack_id))
);
create policy "users update imports for editable stacks"
on public.product_imports for update to authenticated
using (user_id = auth.uid())
with check (
  user_id = auth.uid()
  and (stack_id is null or public.can_edit_stack(stack_id))
);
create policy "users delete their imports"
on public.product_imports for delete to authenticated
using (user_id = auth.uid());

-- A storage UPDATE needs a WITH CHECK clause as well, otherwise an existing
-- object could be renamed out of the caller's own prefix.
drop policy if exists "users update their media" on storage.objects;
create policy "users update their media"
on storage.objects for update to authenticated
using (
  bucket_id = 'stack-media'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'stack-media'
  and (storage.foldername(name))[1] = auth.uid()::text
);

revoke all on function public.can_view_stack(uuid) from public;
revoke all on function public.can_edit_stack(uuid) from public;
revoke all on function public.is_stack_owner(uuid) from public;
revoke all on function public.is_blocked_pair(uuid, uuid) from public;
revoke all on function public.can_update_stack_metadata(uuid, uuid, public.stack_visibility) from public;
revoke all on function public.can_claim_stack_item(uuid, uuid) from public;
revoke all on function public.can_view_link_only_stack(uuid, uuid) from public;
revoke all on function public.can_access_stack_item_media(uuid, text) from public;
revoke all on function public.is_stack_item_media_path(uuid, text) from public;
revoke all on function public.pin_link_only_stack(uuid) from public;
revoke all on function public.claim_link_only_item(uuid, uuid, text, text) from public;

grant execute on function public.can_view_stack(uuid) to authenticated;
grant execute on function public.can_edit_stack(uuid) to authenticated;
grant execute on function public.is_stack_owner(uuid) to authenticated;
grant execute on function public.is_blocked_pair(uuid, uuid) to authenticated;
grant execute on function public.can_update_stack_metadata(uuid, uuid, public.stack_visibility) to authenticated;
grant execute on function public.can_claim_stack_item(uuid, uuid) to authenticated;
grant execute on function public.can_view_link_only_stack(uuid, uuid) to authenticated;
grant execute on function public.can_access_stack_item_media(uuid, text) to authenticated;
grant execute on function public.is_stack_item_media_path(uuid, text) to service_role;
grant execute on function public.pin_link_only_stack(uuid) to authenticated;
grant execute on function public.claim_link_only_item(uuid, uuid, text, text) to authenticated;
