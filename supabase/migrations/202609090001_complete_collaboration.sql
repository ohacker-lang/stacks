-- Complete collaborative Stacks: owners explicitly enable collaboration,
-- accepted editors can work together, and members can see the shared roster.
alter table public.stacks
add column if not exists collaboration_enabled boolean not null default false;

create or replace function public.is_stack_member(target_stack_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1
    from public.stacks s
    where s.id = target_stack_id
      and (
        s.owner_id = auth.uid()
        or exists (
          select 1 from public.stack_collaborators c
          where c.stack_id = s.id
            and c.user_id = auth.uid()
            and c.accepted_at is not null
        )
      )
  );
$$;

create or replace function public.shares_collaborative_stack(target_profile_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1
    from public.stacks s
    where s.collaboration_enabled
      and (
        s.owner_id = auth.uid()
        or exists (
          select 1 from public.stack_collaborators mine
          where mine.stack_id = s.id
            and mine.user_id = auth.uid()
            and mine.accepted_at is not null
        )
      )
      and (
        s.owner_id = target_profile_id
        or exists (
          select 1 from public.stack_collaborators theirs
          where theirs.stack_id = s.id
            and theirs.user_id = target_profile_id
            and theirs.accepted_at is not null
        )
      )
  );
$$;

create or replace function public.can_edit_stack(target_stack_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1
    from public.stacks s
    where s.id = target_stack_id
      and (
        s.owner_id = auth.uid()
        or (
          s.collaboration_enabled
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

drop policy if exists "collaborators view their relationship" on public.stack_collaborators;
create policy "stack members view their roster"
on public.stack_collaborators for select to authenticated
using (public.is_stack_member(stack_id));

create policy "collaborators leave stacks"
on public.stack_collaborators for delete to authenticated
using (user_id = auth.uid());

drop policy if exists "profiles viewable through an allowed relationship" on public.profiles;
drop policy if exists "profiles viewable by self or discovery users" on public.profiles;
create policy "profiles viewable through an allowed relationship"
on public.profiles for select to authenticated
using (
  id = auth.uid()
  or (discovery_enabled and not public.is_blocked_pair(id, auth.uid()))
  or public.shares_collaborative_stack(id)
);

create or replace function public.protect_stack_collaboration_setting()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if new.collaboration_enabled is distinct from old.collaboration_enabled
     and auth.uid() is distinct from old.owner_id then
    raise exception 'Only the Stack owner can change collaboration.' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists stacks_protect_collaboration_setting on public.stacks;
create trigger stacks_protect_collaboration_setting
before update of collaboration_enabled on public.stacks
for each row execute function public.protect_stack_collaboration_setting();

create or replace function public.revoke_invites_when_collaboration_disabled()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
  if old.collaboration_enabled and not new.collaboration_enabled then
    update public.collaboration_invites
    set revoked_at = coalesce(revoked_at, now())
    where stack_id = new.id and accepted_at is null;
  end if;
  return new;
end;
$$;

drop trigger if exists stacks_revoke_invites_when_disabled on public.stacks;
create trigger stacks_revoke_invites_when_disabled
after update of collaboration_enabled on public.stacks
for each row execute function public.revoke_invites_when_collaboration_disabled();

create or replace function public.accept_collaboration_invite(invite_token uuid)
returns table (stack_id uuid, permission public.collaborator_permission)
language plpgsql
security definer
set search_path = public
as $$
declare
  invitation public.collaboration_invites%rowtype;
  target_stack public.stacks%rowtype;
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

  select * into target_stack from public.stacks s where s.id = invitation.stack_id;
  if not found or not target_stack.collaboration_enabled then
    raise exception 'Collaboration is no longer enabled for this Stack.' using errcode = 'P0001';
  end if;
  if target_stack.owner_id = auth.uid() then
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

revoke all on function public.is_stack_member(uuid) from public;
revoke all on function public.shares_collaborative_stack(uuid) from public;
revoke all on function public.can_edit_stack(uuid) from public;
revoke all on function public.accept_collaboration_invite(uuid) from public;
grant execute on function public.is_stack_member(uuid) to authenticated;
grant execute on function public.shares_collaborative_stack(uuid) to authenticated;
grant execute on function public.can_edit_stack(uuid) to authenticated;
grant execute on function public.accept_collaboration_invite(uuid) to authenticated;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'stacks'
  ) then alter publication supabase_realtime add table public.stacks; end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'stack_items'
  ) then alter publication supabase_realtime add table public.stack_items; end if;
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'stack_collaborators'
  ) then alter publication supabase_realtime add table public.stack_collaborators; end if;
end;
$$;
