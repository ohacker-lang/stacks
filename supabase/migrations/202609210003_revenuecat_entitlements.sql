-- RevenueCat owns subscription validation. Supabase keeps the small server-side
-- entitlement projection used by database limits and scheduled Pro features.
alter table public.pro_entitlements
  alter column original_transaction_id drop not null;

alter table public.pro_entitlements
  add column if not exists provider text not null default 'revenuecat',
  add column if not exists provider_customer_id text;

create unique index if not exists pro_entitlements_provider_customer_idx
  on public.pro_entitlements (provider, provider_customer_id)
  where provider_customer_id is not null;

create table if not exists public.revenuecat_webhook_events (
  id text primary key,
  event_type text not null,
  received_at timestamptz not null default now()
);

alter table public.revenuecat_webhook_events enable row level security;
-- No client policies: only service-role Edge Functions can access this table.
