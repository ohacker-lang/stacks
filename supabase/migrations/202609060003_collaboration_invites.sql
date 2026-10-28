-- Invitation tokens are intentionally opaque. A token can be redeemed once,
-- expires automatically, and is never treated as authorization by itself: the
-- recipient must also have an authenticated Stacks account.
create table public.collaboration_invites (
  id uuid primary key default gen_random_uuid(),
  stack_id uuid not null references public.stacks(id) on delete cascade,
  invited_by uuid not null references public.profiles(id) on delete cascade,
  permission public.collaborator_permission not null default 'editor',
  token uuid not null unique default gen_random_uuid(),
  expires_at timestamptz not null default (now() + interval '7 days'),
  accepted_by uuid references public.profiles(id) on delete set null,
  accepted_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  check (expires_at > created_at)
);

create index collaboration_invites_creator_idx on public.collaboration_invites (invited_by, created_at desc);
create index collaboration_invites_token_idx on public.collaboration_invites (token) where accepted_at is null and revoked_at is null;

alter table public.collaboration_invites enable row level security;

create policy "owners view their collaboration invites"
on public.collaboration_invites for select to authenticated
using (public.is_stack_owner(stack_id));

create policy "owners revoke their collaboration invites"
on public.collaboration_invites for update to authenticated
using (public.is_stack_owner(stack_id))
with check (public.is_stack_owner(stack_id));

-- Redeeming happens through this transactional function so two people cannot
-- accept the same token at the same time.
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
  from public.collaboration_invites
  where token = invite_token
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

  select owner_id into stack_owner from public.stacks where id = invitation.stack_id;
  if stack_owner = auth.uid() then
    raise exception 'You already own this Stack.' using errcode = 'P0001';
  end if;

  insert into public.stack_collaborators (stack_id, user_id, permission, invited_by, accepted_at)
  values (invitation.stack_id, auth.uid(), invitation.permission, invitation.invited_by, now())
  on conflict (stack_id, user_id) do update
    set permission = excluded.permission,
        invited_by = excluded.invited_by,
        accepted_at = excluded.accepted_at;

  update public.collaboration_invites
  set accepted_by = auth.uid(), accepted_at = now()
  where id = invitation.id;

  return query select invitation.stack_id, invitation.permission;
end;
$$;

revoke all on function public.accept_collaboration_invite(uuid) from public;
grant execute on function public.accept_collaboration_invite(uuid) to authenticated;
