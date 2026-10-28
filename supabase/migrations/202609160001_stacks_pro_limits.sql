-- Server-owned subscription state. Clients may read their own row but cannot
-- grant themselves Pro. expires_at automatically restores free limits.
create table if not exists public.pro_entitlements (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  original_transaction_id text not null unique,
  product_id text not null check (product_id in ('stacks.pro.monthly', 'stacks.pro.annual')),
  expires_at timestamptz not null,
  revoked_at timestamptz,
  updated_at timestamptz not null default now()
);

alter table public.pro_entitlements enable row level security;
create policy "users read own pro entitlement"
on public.pro_entitlements for select to authenticated
using (user_id = auth.uid());

create or replace function public.stack_owner_has_pro(target_stack uuid)
returns boolean language sql stable security definer
set search_path = public as $$
  select exists (
    select 1 from public.stacks s
    join public.pro_entitlements e on e.user_id = s.owner_id
    where s.id = target_stack and e.expires_at > now() and e.revoked_at is null
  );
$$;
revoke all on function public.stack_owner_has_pro(uuid) from public;
grant execute on function public.stack_owner_has_pro(uuid) to authenticated, service_role;

create or replace function public.enforce_stack_item_limit()
returns trigger language plpgsql security definer
set search_path = public as $$
declare item_count integer;
begin
  -- Serialize concurrent inserts into the same Stack; without this lock two
  -- separate Share Sheet requests could both pass the tenth-item check.
  perform 1 from public.stacks where id = new.stack_id for update;
  if public.stack_owner_has_pro(new.stack_id) then return new; end if;
  select count(*) into item_count from public.stack_items where stack_id = new.stack_id;
  if item_count >= 15 then
    raise exception 'Stacks Pro is required to add more than 15 items to this Stack.'
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;
create trigger stack_items_pro_limit before insert on public.stack_items
for each row execute function public.enforce_stack_item_limit();

create or replace function public.enforce_stack_collaborator_limit()
returns trigger language plpgsql security definer
set search_path = public as $$
declare collaborator_count integer;
begin
  perform 1 from public.stacks where id = new.stack_id for update;
  if public.stack_owner_has_pro(new.stack_id) then return new; end if;
  select count(*) into collaborator_count
  from public.stack_collaborators where stack_id = new.stack_id;
  if collaborator_count >= 3 then
    raise exception 'Stacks Pro is required for more than 3 collaborators.'
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;
create trigger stack_collaborators_pro_limit before insert on public.stack_collaborators
for each row execute function public.enforce_stack_collaborator_limit();

create or replace function public.enforce_stack_invite_limit()
returns trigger language plpgsql security definer
set search_path = public as $$
declare invited_count integer;
begin
  perform 1 from public.stacks where id = new.stack_id for update;
  if public.stack_owner_has_pro(new.stack_id) then return new; end if;
  select (
    (select count(*) from public.stack_collaborators where stack_id = new.stack_id) +
    (select count(*) from public.collaboration_invites
      where stack_id = new.stack_id and accepted_at is null
        and revoked_at is null and expires_at > now())
  ) into invited_count;
  if invited_count >= 3 then
    raise exception 'Stacks Pro is required for more than 3 invited collaborators.'
      using errcode = 'P0001';
  end if;
  return new;
end;
$$;
create trigger collaboration_invites_pro_limit before insert on public.collaboration_invites
for each row execute function public.enforce_stack_invite_limit();
