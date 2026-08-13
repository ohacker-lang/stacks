# Stacks

Stacks is a SwiftUI iOS 18+ wishlist and curation app. It opens through onboarding, then lets people create visual Stacks of background-removed product cutouts, add items by link/photo/search/Share Sheet, keep linkless **Unidentified Finds**, open editable product details with buy links, and discover, follow, pin, or copy other creators' public Stacks.

## Product Requirements

The product vision, V1 scope, user flows, launch criteria, and the camera-first **Stack Scout** capture experience are maintained in [docs/PRD.md](docs/PRD.md). Treat that document as the canonical product reference when making product or UX decisions.

## Continue This Project

Give a new Codex account [docs/CODEX_HANDOFF.md](docs/CODEX_HANDOFF.md) first. It is the current engineering handoff: what is live, what is intentionally incomplete, deployed Supabase inventory, product decisions, validation commands, and the recommended next work sequence.

## Open in Xcode

1. Clone or download this repository.
2. Open `Stacks.xcodeproj`.
3. Select the `Stacks` scheme.
4. Choose an iOS 18+ simulator.
5. Run.

`StacksApp` starts with `AppServices.configured()`: it uses the Supabase-backed services whenever the public Supabase URL and anon key are configured, and otherwise falls back to local demo services. The committed project is configured for the current Supabase development project; Sign in with Apple and email magic links still require the dashboard/provider setup below. Demo services remain available for previews and offline UI work.

## Live Backend

The app is already split behind protocols in `Stacks/Services`:

- `AuthService`
- `StackRepository`
- `ProfileRepository`
- `ProductSearchService`
- `BackgroundRemovalService`
- `AffiliateService`
- `ClaimService`
- `CollaborationService`
- `StorageService`
- `RealtimeService`

The app automatically uses the Supabase-backed services when both
`STACKS_SUPABASE_URL` and `STACKS_SUPABASE_ANON_KEY` are present in the target's
Info settings. Otherwise it uses local demo services, which keeps SwiftUI
previews and simulator UI work functional without a backend.

The production client now supports:

- secure Keychain-backed session restore and token refresh
- Sign in with Apple identity-token exchange
- email magic links with PKCE callback validation
- onboarding completion persisted to `profiles.onboarding_completed_at`
- the existing Supabase stacks, pins, follows, storage, and Edge Function clients

Before testing live sign-in, configure these external dashboard settings:

1. In Supabase **Authentication > URL Configuration**, add `stacks://auth/callback` as a redirect URL.
2. Enable the **Email** provider and ensure Magic Link is enabled.
3. Enable the **Apple** provider in Supabase and supply the Apple OAuth credentials generated for the final bundle identifier.
4. In Xcode, select the Stacks target, set your Apple Developer team, and keep the **Sign in with Apple** capability enabled. The entitlement is already in `Stacks.entitlements`.

The Supabase anon key is a public client credential. Never place a service-role key, Apple private key, SerpApi key, or affiliate secret in the iOS target.

The versioned Supabase functions are deployed for link parsing, product search, affiliate handling, AI descriptions, private media, account deletion, and Stack copying. A few integrations deliberately return a clear unavailable response until their vendor secrets or product surface is ready; see the handoff for the exact status.

## Backend Progress

The Supabase foundation is now versioned in this repository. It is designed to
keep Stacks private by default while supporting public sharing, collaboration,
pins, follows, wishlist claims, and copying shared Stacks safely.

### Implemented

- Canonical schema migrations in `supabase/migrations` for profiles, Stacks,
  items, collaborators, pins, follows, claims, imports, moderation, and
  affiliate click records.
- `private` as the default Stack visibility, with distinct `link_only` and
  `public` sharing modes.
- Row Level Security for owners, accepted collaborators, public viewers, pins,
  follows, product-import drafts, blocks, reports, and private gift claims.
- A private `stack-media` Storage bucket. Product files are never made public.
- Server-issued, short-lived media URLs through `media-url` after Stack access
  and item-path checks succeed.
- Signed collaborator uploads through `create-upload-url`, written into the
  Stack owner's media namespace.
- Secure public/link-only Stack copying through `copy-public-stack`. It creates
  a private copy and duplicates media into the new owner's Storage namespace.
- A deployed `web-preview` endpoint that intentionally returns `501` until the
  read-only web product is built; its security contract is versioned now so it
  can be enabled without exposing share tokens, claims, collaborators, or
  analytics.
- Development-only seed data and RLS smoke tests in `supabase/seed.sql` and
  `supabase/tests/rls_access.sql`.
- Live client service wiring for Keychain-persisted Supabase sessions, refresh,
  PKCE email magic links, native Apple token exchange, Stack CRUD, pins,
  follows, public-Stack copying, and private Storage upload/readback.
- One product-import path for camera, photo library, pasted links, and queued
  Share Sheet links: isolated image, minimum three-second shimmer during Apple
  Vision removal, completion haptic, then an editable product form.
- Linkless camera/photo items can be saved as **Unidentified Finds**; Buy stays
  disabled until an external URL is supplied.

### Still To Do

- Run the local database validation once Docker Desktop is installed and open:
  `supabase start`, `supabase db reset`, `supabase db lint --local`, then the
  RLS smoke test.
- Replace incomplete service implementations: gift claims, collaboration
  invitations, Realtime subscriptions, and profile/avatar editing persistence.
- Add provider credentials and production behavior: SerpApi search, a robust
  merchant parser/image-ranking fallback, a server removal fallback only if
  needed, and Sovrn wrapping for commissionable Buy links.
- Build the read-only web preview before publishing browser share links.
- Configure Sign in with Apple, email OTP, production secrets, separate
  development/staging/production Supabase projects, and monitoring/rate limits.
- Finalize the Privacy Policy, Terms of Service, support contact, account
  deletion verification, and App Store privacy disclosures.

### Backend Docs

- [Implementation status and service mapping](docs/BACKEND_IMPLEMENTATION.md)
- [Security, Storage, RLS, and deployment runbook](docs/SUPABASE_SECURITY_RUNBOOK.md)
- [V1 product/data contract](docs/V1_PRODUCT_CONTRACT.md)

### Local Backend Validation

Docker Desktop is required for the local Supabase database. Once it is running:

```bash
supabase start
supabase db reset
supabase db lint --local
psql "$LOCAL_DB_URL" -f supabase/tests/rls_access.sql
```

This is local-only validation. It does not deploy migrations or functions to a
hosted Supabase project.

## Live Product Search (SerpApi)

Stacks uses SerpApi's Google Shopping endpoint for live product search. The SerpApi key stays in Supabase; it is never added to the iOS app.

1. Create a SerpApi account and copy the API key from its dashboard. The free plan currently includes 250 searches per month.
2. Link the repository to your Supabase project, then set the secret and deploy the function:

   ```bash
   supabase secrets set SERPAPI_API_KEY=your_serpapi_key
   supabase functions deploy product-search
   ```

3. In Xcode, select the `Stacks` target, open **Info**, and set these two generated keys for Debug and Release:

   ```text
   STACKS_PRODUCT_SEARCH_URL = https://YOUR_PROJECT_REF.supabase.co/functions/v1/product-search
   STACKS_SUPABASE_ANON_KEY = your_supabase_anon_key
   ```

`STACKS_SUPABASE_ANON_KEY` is the public client key. Do not put `SERPAPI_API_KEY` or a Supabase service-role key in Xcode, source control, or the app binary.

With those values present, in-app product search uses the live Edge Function. Without them, Stacks deliberately falls back to its local demo results so the project remains runnable in Simulator.

## Design Notes

- App background: warm cream `#F5F2ED`.
- Stack detail canvas: pure white, matching the supplied reference image.
- Product stickers use stable free positions, subtle shadows, white halo treatment, and a vertical shimmer while background removal is processing.
- Liquid Glass helpers are guarded for iOS 26+ and fall back to native materials.

## Font Note

Product descriptions call `InstrumentSerif-Italic` via `Font.custom`. Add the font file to the app target later if you want exact typography; iOS will otherwise fall back while preserving the italic treatment.
