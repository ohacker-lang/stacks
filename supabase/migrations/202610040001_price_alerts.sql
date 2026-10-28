-- Price monitoring is server-owned: clients can read their own alerts and
-- events, but all mutations run through the authenticated price-alerts Edge
-- Function so retailer verification and Pro limits cannot be bypassed.
create table if not exists public.price_alerts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  stack_item_id uuid not null references public.stack_items(id) on delete cascade,
  mode text not null check (mode in ('any_drop', 'target')),
  target_price numeric(12,2),
  currency_code text not null check (currency_code ~ '^[A-Z]{3}$'),
  baseline_price numeric(12,2) not null check (baseline_price > 0),
  current_price numeric(12,2) not null check (current_price > 0),
  lowest_price numeric(12,2) not null check (lowest_price > 0),
  last_notified_price numeric(12,2),
  status text not null default 'active'
    check (status in ('active', 'paused', 'pro_required', 'temporarily_unavailable')),
  next_check_at timestamptz not null default now(),
  last_checked_at timestamptz,
  last_success_at timestamptz,
  consecutive_failures integer not null default 0 check (consecutive_failures >= 0),
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, stack_item_id),
  check ((mode = 'target' and target_price is not null and target_price > 0)
      or (mode = 'any_drop' and target_price is null))
);

create index if not exists price_alerts_due_idx
  on public.price_alerts (next_check_at)
  where status in ('active', 'temporarily_unavailable');
create index if not exists price_alerts_user_idx
  on public.price_alerts (user_id, created_at);

create table if not exists public.price_observations (
  id bigint generated always as identity primary key,
  alert_id uuid not null references public.price_alerts(id) on delete cascade,
  price numeric(12,2) not null check (price > 0),
  currency_code text not null check (currency_code ~ '^[A-Z]{3}$'),
  observed_at timestamptz not null default now()
);
create index if not exists price_observations_alert_idx
  on public.price_observations (alert_id, observed_at desc);

create table if not exists public.price_alert_events (
  id uuid primary key default gen_random_uuid(),
  alert_id uuid not null references public.price_alerts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  previous_price numeric(12,2) not null,
  current_price numeric(12,2) not null,
  currency_code text not null check (currency_code ~ '^[A-Z]{3}$'),
  dedupe_key text not null unique,
  created_at timestamptz not null default now(),
  delivered_at timestamptz,
  read_at timestamptz
);
create index if not exists price_alert_events_user_idx
  on public.price_alert_events (user_id, created_at desc);

create table if not exists public.notification_preferences (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  price_alerts_enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.price_alerts enable row level security;
alter table public.price_observations enable row level security;
alter table public.price_alert_events enable row level security;
alter table public.notification_preferences enable row level security;

create policy "users read own price alerts"
on public.price_alerts for select to authenticated
using (user_id = auth.uid());
create policy "users read own price observations"
on public.price_observations for select to authenticated
using (exists (
  select 1 from public.price_alerts a
  where a.id = alert_id and a.user_id = auth.uid()
));
create policy "users read own price events"
on public.price_alert_events for select to authenticated
using (user_id = auth.uid());
create policy "users read own notification preferences"
on public.notification_preferences for select to authenticated
using (user_id = auth.uid());

create or replace function public.user_has_pro(target_user uuid)
returns boolean language sql stable security definer
set search_path = public as $$
  select exists (
    select 1 from public.pro_entitlements e
    where e.user_id = target_user
      and e.expires_at > now()
      and e.revoked_at is null
  );
$$;
revoke all on function public.user_has_pro(uuid) from public;
grant execute on function public.user_has_pro(uuid) to authenticated, service_role;

-- Run after a RevenueCat expiration or before listing alerts. It preserves the
-- member's oldest alert and pauses the rest instead of deleting their choices.
create or replace function public.reconcile_price_alert_entitlement(target_user uuid)
returns void language plpgsql security definer
set search_path = public as $$
begin
  if public.user_has_pro(target_user) then
    update public.price_alerts
      set status = 'active', next_check_at = least(next_check_at, now()), updated_at = now()
      where user_id = target_user and status = 'pro_required';
  else
    with ranked as (
      select id, row_number() over (order by created_at, id) as position
      from public.price_alerts
      where user_id = target_user and status in ('active', 'temporarily_unavailable', 'pro_required')
    )
    update public.price_alerts a
      set status = case when ranked.position = 1 then 'active' else 'pro_required' end,
          updated_at = now()
      from ranked where a.id = ranked.id;
  end if;
end;
$$;
revoke all on function public.reconcile_price_alert_entitlement(uuid) from public;
grant execute on function public.reconcile_price_alert_entitlement(uuid) to service_role;

-- Device tokens need an APNs environment so local development tokens are
-- never sent to the production endpoint or vice versa.
alter table public.push_device_tokens
  add column if not exists environment text not null default 'production'
  check (environment in ('sandbox', 'production'));
