-- A wishlist item can only be claimed once. The owner never receives a row
-- through RLS, so this constraint prevents duplicate purchases without leaking
-- the claimant's identity.
alter table public.gift_claims
  drop constraint if exists gift_claims_item_id_claimer_id_key;

create unique index if not exists gift_claims_one_claim_per_item_idx
  on public.gift_claims (item_id)
  where status in ('claimed', 'purchased');
