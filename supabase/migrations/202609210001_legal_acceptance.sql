-- Versioned click-through acceptance evidence for the public Terms and Privacy
-- Policy. These columns deliberately live on the user-owned profile so RLS
-- limits updates to the signed-in account.

alter table public.profiles
  add column if not exists legal_terms_version text,
  add column if not exists legal_terms_accepted_at timestamptz,
  add column if not exists privacy_policy_version text,
  add column if not exists privacy_policy_accepted_at timestamptz;

alter table public.profiles
  drop constraint if exists profiles_legal_acceptance_complete,
  add constraint profiles_legal_acceptance_complete check (
    (legal_terms_version is null and legal_terms_accepted_at is null)
    or (legal_terms_version is not null and legal_terms_accepted_at is not null)
  ),
  drop constraint if exists profiles_privacy_acceptance_complete,
  add constraint profiles_privacy_acceptance_complete check (
    (privacy_policy_version is null and privacy_policy_accepted_at is null)
    or (privacy_policy_version is not null and privacy_policy_accepted_at is not null)
  );

comment on column public.profiles.legal_terms_version is
  'Version of the Terms affirmatively accepted during sign-in.';
comment on column public.profiles.legal_terms_accepted_at is
  'Server-recorded timestamp for affirmative Terms acceptance.';
comment on column public.profiles.privacy_policy_version is
  'Version of the Privacy Policy acknowledged during sign-in.';
comment on column public.profiles.privacy_policy_accepted_at is
  'Server-recorded timestamp for Privacy Policy acknowledgement.';
