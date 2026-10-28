create table if not exists public.push_device_tokens (
  token text primary key check (token ~ '^[0-9a-f]{64,256}$'),
  user_id uuid not null references public.profiles(id) on delete cascade,
  platform text not null check (platform in ('ios')),
  enabled boolean not null default true,
  last_registered_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create index if not exists push_device_tokens_user_idx
  on public.push_device_tokens (user_id) where enabled;

alter table public.push_device_tokens enable row level security;
-- Tokens are write-only through the authenticated Edge Function and readable
-- only by trusted notification workers using the service role.
