-- Stacks V1 canonical schema.
-- Apply with: supabase db push
-- This migration is intentionally private-by-default. Public and link-only
-- sharing are exposed through controlled queries / edge functions, not public
-- media URLs.

create extension if not exists pgcrypto;
create extension if not exists citext;

create type public.stack_visibility as enum ('private', 'link_only', 'public');
create type public.collaborator_permission as enum ('viewer', 'editor');
create type public.item_source as enum ('search', 'pasted_link', 'camera', 'photo_library', 'manual_photo', 'share_extension');
create type public.background_removal_status as enum ('queued', 'processing', 'complete', 'failed');
create type public.gift_claim_status as enum ('claimed', 'purchased', 'cancelled');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null check (char_length(trim(display_name)) between 1 and 80),
  username citext not null unique check (username ~ '^[a-zA-Z0-9_]{3,30}$'),
  avatar_path text,
  bio text not null default '' check (char_length(bio) <= 280),
  link_in_bio_url text,
  discovery_enabled boolean not null default false,
  onboarding_completed_at timestamptz,
  deletion_requested_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.stacks (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles(id) on delete cascade,
  title text not null check (char_length(trim(title)) between 1 and 80),
  summary text not null default '' check (char_length(summary) <= 280),
  visibility public.stack_visibility not null default 'private',
  wishlist_mode boolean not null default false,
  public_link_token uuid not null unique default gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index stacks_owner_updated_idx on public.stacks (owner_id, updated_at desc);
create index stacks_public_updated_idx on public.stacks (updated_at desc) where visibility = 'public';

create table public.stack_collaborators (
  stack_id uuid not null references public.stacks(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  permission public.collaborator_permission not null default 'viewer',
  invited_by uuid not null references public.profiles(id) on delete restrict,
  accepted_at timestamptz,
  created_at timestamptz not null default now(),
  primary key (stack_id, user_id)
);

create index stack_collaborators_user_idx on public.stack_collaborators (user_id, created_at desc);

create table public.stack_items (
  id uuid primary key default gen_random_uuid(),
  stack_id uuid not null references public.stacks(id) on delete cascade,
  title text not null check (char_length(trim(title)) between 1 and 160),
  brand text not null default '' check (char_length(brand) <= 100),
  description text not null default '' check (char_length(description) <= 1_500),
  price numeric(12, 2),
  currency_code char(3),
  size_text text not null default '' check (char_length(size_text) <= 80),
  source_url text,
  buy_url text,
  affiliate_url text,
  original_image_path text,
  removed_background_image_path text,
  removal_status public.background_removal_status not null default 'queued',
  placement_x numeric(6, 5) not null default 0.5 check (placement_x between 0 and 1),
  placement_y numeric(6, 5) not null default 0.5 check (placement_y between 0 and 1),
  placement_scale numeric(5, 3) not null default 1 check (placement_scale between 0.2 and 3),
  rotation_degrees numeric(6, 2) not null default 0 check (rotation_degrees between -180 and 180),
  has_custom_placement boolean not null default false,
  source_type public.item_source not null,
  needs_link boolean generated always as (source_url is null and buy_url is null) stored,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (price is null or price >= 0),
  check (currency_code is null or currency_code ~ '^[A-Z]{3}$'),
  check (source_url is null or source_url ~ '^https?://'),
  check (buy_url is null or buy_url ~ '^https?://'),
  check (affiliate_url is null or affiliate_url ~ '^https?://')
);

create index stack_items_stack_created_idx on public.stack_items (stack_id, created_at);

-- A pin is the only saved-Stack relationship. Older client code may still call
-- this a bookmark until the production repository replaces that naming.
create table public.stack_pins (
  stack_id uuid not null references public.stacks(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (stack_id, user_id)
);

create index stack_pins_user_created_idx on public.stack_pins (user_id, created_at desc);

create table public.follows (
  follower_id uuid not null references public.profiles(id) on delete cascade,
  followed_user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, followed_user_id),
  check (follower_id <> followed_user_id)
);

create index follows_followed_idx on public.follows (followed_user_id, created_at desc);

-- Gift claims are deliberately invisible to a Stack owner. Only a claim's
-- author and privileged server-side workflows can read the record.
create table public.gift_claims (
  id uuid primary key default gen_random_uuid(),
  stack_id uuid not null references public.stacks(id) on delete cascade,
  item_id uuid not null references public.stack_items(id) on delete cascade,
  claimer_id uuid not null references public.profiles(id) on delete cascade,
  claimer_name text not null check (char_length(trim(claimer_name)) between 1 and 80),
  private_message text check (char_length(private_message) <= 500),
  status public.gift_claim_status not null default 'claimed',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (item_id, claimer_id)
);

create table public.product_imports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  stack_id uuid references public.stacks(id) on delete set null,
  source_type public.item_source not null,
  source_url text,
  extracted_metadata jsonb not null default '{}'::jsonb,
  original_image_path text,
  removed_background_image_path text,
  removal_status public.background_removal_status not null default 'queued',
  error_message text,
  expires_at timestamptz not null default now() + interval '7 days',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (source_url is null or source_url ~ '^https?://')
);

create index product_imports_user_updated_idx on public.product_imports (user_id, updated_at desc);

create table public.user_blocks (
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_user_id),
  check (blocker_id <> blocked_user_id)
);

create table public.content_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  reported_profile_id uuid references public.profiles(id) on delete set null,
  reported_stack_id uuid references public.stacks(id) on delete set null,
  reason text not null check (char_length(trim(reason)) between 1 and 100),
  details text not null default '' check (char_length(details) <= 2_000),
  created_at timestamptz not null default now(),
  check (reported_profile_id is not null or reported_stack_id is not null)
);

-- Affiliate clicks are write-only from trusted edge functions. These fields are
-- purposefully small: no page HTML, search terms, or raw image content.
create table public.affiliate_clicks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles(id) on delete set null,
  stack_id uuid references public.stacks(id) on delete set null,
  item_id uuid references public.stack_items(id) on delete set null,
  destination_host text not null,
  network text,
  created_at timestamptz not null default now()
);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_set_updated_at before update on public.profiles
for each row execute function public.set_updated_at();
create trigger stacks_set_updated_at before update on public.stacks
for each row execute function public.set_updated_at();
create trigger stack_items_set_updated_at before update on public.stack_items
for each row execute function public.set_updated_at();
create trigger gift_claims_set_updated_at before update on public.gift_claims
for each row execute function public.set_updated_at();
create trigger product_imports_set_updated_at before update on public.product_imports
for each row execute function public.set_updated_at();

-- Creates a profile from a new Supabase Auth user. The app completes the
-- profile after authentication; this trigger prevents orphaned user records.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  initial_name text;
begin
  initial_name := coalesce(
    nullif(new.raw_user_meta_data ->> 'full_name', ''),
    nullif(new.raw_user_meta_data ->> 'name', ''),
    split_part(coalesce(new.email, ''), '@', 1),
    'New member'
  );

  insert into public.profiles (id, display_name, username)
  values (
    new.id,
    left(initial_name, 80),
    'stacker_' || substring(replace(new.id::text, '-', '') from 1 for 12)
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

-- Security-definer helpers keep RLS policies readable and avoid recursive
-- policy evaluation. They never expose data themselves.
create or replace function public.is_stack_owner(target_stack_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.stacks
    where id = target_stack_id and owner_id = auth.uid()
  );
$$;

create or replace function public.can_edit_stack(target_stack_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select public.is_stack_owner(target_stack_id)
    or exists (
      select 1 from public.stack_collaborators
      where stack_id = target_stack_id
        and user_id = auth.uid()
        and permission = 'editor'
        and accepted_at is not null
    );
$$;

create or replace function public.can_view_stack(target_stack_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1
    from public.stacks s
    where s.id = target_stack_id
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

create or replace function public.is_blocked_pair(first_user_id uuid, second_user_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.user_blocks
    where (blocker_id = first_user_id and blocked_user_id = second_user_id)
       or (blocker_id = second_user_id and blocked_user_id = first_user_id)
  );
$$;

-- Link-only Stacks are fetched through this narrow RPC instead of a broad RLS
-- policy, so holding an opaque token is required to read both its stack and
-- item payload. It does not expose collaborators, claims, imports, or pins.
create or replace function public.get_link_only_stack(link_token uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  result jsonb;
begin
  select jsonb_build_object(
    'stack', to_jsonb(s),
    'items', coalesce(
      (
        select jsonb_agg(to_jsonb(i) order by i.created_at)
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

revoke all on function public.get_link_only_stack(uuid) from public;
grant execute on function public.get_link_only_stack(uuid) to authenticated;

alter table public.profiles enable row level security;
alter table public.stacks enable row level security;
alter table public.stack_collaborators enable row level security;
alter table public.stack_items enable row level security;
alter table public.stack_pins enable row level security;
alter table public.follows enable row level security;
alter table public.gift_claims enable row level security;
alter table public.product_imports enable row level security;
alter table public.user_blocks enable row level security;
alter table public.content_reports enable row level security;
alter table public.affiliate_clicks enable row level security;

create policy "profiles viewable by self or discovery users"
on public.profiles for select to authenticated
using (id = auth.uid() or discovery_enabled = true);
create policy "profiles updateable by self"
on public.profiles for update to authenticated
using (id = auth.uid()) with check (id = auth.uid());

create policy "stacks viewable when authorized"
on public.stacks for select to authenticated
using (
  public.can_view_stack(id)
  and not public.is_blocked_pair(owner_id, auth.uid())
);
create policy "users create their own stacks"
on public.stacks for insert to authenticated
with check (owner_id = auth.uid());
create policy "owners update their stacks"
on public.stacks for update to authenticated
using (owner_id = auth.uid()) with check (owner_id = auth.uid());
create policy "owners delete their stacks"
on public.stacks for delete to authenticated
using (owner_id = auth.uid());

create policy "collaborators view their relationship"
on public.stack_collaborators for select to authenticated
using (user_id = auth.uid() or public.is_stack_owner(stack_id));
create policy "owners manage collaborators"
on public.stack_collaborators for all to authenticated
using (public.is_stack_owner(stack_id)) with check (public.is_stack_owner(stack_id));

create policy "items viewable with stack"
on public.stack_items for select to authenticated
using (public.can_view_stack(stack_id));
create policy "editors insert items"
on public.stack_items for insert to authenticated
with check (public.can_edit_stack(stack_id));
create policy "editors update items"
on public.stack_items for update to authenticated
using (public.can_edit_stack(stack_id)) with check (public.can_edit_stack(stack_id));
create policy "editors delete items"
on public.stack_items for delete to authenticated
using (public.can_edit_stack(stack_id));

create policy "users view their pins"
on public.stack_pins for select to authenticated
using (user_id = auth.uid());
create policy "users create viewable pins"
on public.stack_pins for insert to authenticated
with check (user_id = auth.uid() and public.can_view_stack(stack_id));
create policy "users remove their pins"
on public.stack_pins for delete to authenticated
using (user_id = auth.uid());

create policy "users view their follow relationships"
on public.follows for select to authenticated
using (follower_id = auth.uid() or followed_user_id = auth.uid());
create policy "users create own follows"
on public.follows for insert to authenticated
with check (follower_id = auth.uid() and follower_id <> followed_user_id);
create policy "users remove own follows"
on public.follows for delete to authenticated
using (follower_id = auth.uid());

create policy "claimers view private claims"
on public.gift_claims for select to authenticated
using (claimer_id = auth.uid());
create policy "viewers create claims"
on public.gift_claims for insert to authenticated
with check (claimer_id = auth.uid() and public.can_view_stack(stack_id));
create policy "claimers update private claims"
on public.gift_claims for update to authenticated
using (claimer_id = auth.uid()) with check (claimer_id = auth.uid());

create policy "users manage their imports"
on public.product_imports for all to authenticated
using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "users manage their blocks"
on public.user_blocks for all to authenticated
using (blocker_id = auth.uid()) with check (blocker_id = auth.uid());
create policy "users create and view their reports"
on public.content_reports for select to authenticated
using (reporter_id = auth.uid());
create policy "users submit reports"
on public.content_reports for insert to authenticated
with check (reporter_id = auth.uid());

-- No client-side policies are granted for affiliate_clicks. A service-role edge
-- function records them after validating the authenticated caller and target.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'stack-media',
  'stack-media',
  false,
  20971520,
  array['image/jpeg', 'image/png', 'image/heic', 'image/webp']
)
on conflict (id) do nothing;

create policy "users upload into their media prefix"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'stack-media'
  and (storage.foldername(name))[1] = auth.uid()::text
);
create policy "users view their original media"
on storage.objects for select to authenticated
using (
  bucket_id = 'stack-media'
  and (storage.foldername(name))[1] = auth.uid()::text
);
create policy "users update their media"
on storage.objects for update to authenticated
using (
  bucket_id = 'stack-media'
  and (storage.foldername(name))[1] = auth.uid()::text
);
create policy "users delete their media"
on storage.objects for delete to authenticated
using (
  bucket_id = 'stack-media'
  and (storage.foldername(name))[1] = auth.uid()::text
);
