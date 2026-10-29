# Stacks

Stacks is a SwiftUI iOS 18+ wishlist and curation app. It opens through onboarding, then lets people create visual Stacks of background-removed product cutouts, add items by link/photo/search/Share Sheet, keep linkless **Unidentified Finds**, open editable product details with buy links, and discover, follow, pin, or copy other creators' public Stacks.

## Where things live

Product and engineering context is kept in Notion: **[Stacks HQ](https://app.notion.com/p/40858338d8458175ba30c2eb91d7f2ad)**
(Backlog, Roadmap, PRDs, Releases, Decision Log, Engineering Docs, Metrics).
The repo docs below cover what you need while working in the code; if they
disagree with Notion, Notion wins. Working rules for Claude and Codex sessions
are in [CLAUDE.md](CLAUDE.md).

## Current state (October 2026)

- **Backend:** Supabase project `whyufyttlvpiwlunosjm` (US East). 26 migrations
  and 20 Edge Functions are deployed. The earlier projects
  `iuovmgjcfwgwozfnsdgf` and `hpjiphvgmhvvvfxkunwb` are retired.
- **Apple:** team `24H7V96T4Q`, bundle IDs `spot.stacks.app` (app) and
  `spot.stacks.app.share` (Share Sheet extension), app group
  `group.spot.stacks.app`.
- **Sign-in:** Sign in with Apple, Google (Supabase web OAuth) and email magic
  link.
- **Visibility:** new Stacks are **public** by default; link-only and private
  remain options. Every account has a public page at `stacks.spot/<username>`
  with its public Stacks as boards.
- **Stacks Pro:** paused for launch (`StacksPro.isEnabled = false`, limits
  lifted on the server by migration `202610280001`).
- **Price alerts:** `price-alerts` stores alerts; an hourly Cloudflare cron calls
  `check-price-alerts`, which sends APNs pushes.
- **Analytics:** PostHog in Release builds and on stacks.spot. Events are
  defined in [docs/ANALYTICS.md](docs/ANALYTICS.md).
- **Hidden or off:** in-app product search (SerpApi) is hidden and Sovrn
  affiliate wrapping is not configured, so Buy opens the plain retailer link.
- **Website:** stacks.spot is the Cloudflare Worker in `web/`.
- The app is light-mode only.

## Open in Xcode

1. Clone this repository and open `Stacks.xcodeproj`.
2. Select the `Stacks` scheme and an iOS 18+ simulator.
3. Run.

`StacksApp` starts with `AppServices.configured()`: it uses the Supabase-backed
services when the Supabase URL and publishable key are configured, and falls
back to local demo services otherwise. To use the offline demo account in a
Debug build, set the launch environment variable `STACKS_PRO_LOCAL_STOREKIT=1`.

App settings come from `INFOPLIST_KEY_STACKS_*` build settings and reach the
app only through `Stacks/Info.plist`, because Xcode's generated Info.plist
drops unknown keys. Add new settings in both places.

Command-line build and tests:

```bash
xcodebuild -project Stacks.xcodeproj -scheme Stacks -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build/DerivedData build CODE_SIGNING_ALLOWED=NO
cd web && npm test
```

## Live Backend

The app is split behind protocols in `Stacks/Services`:

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
- `SafetyService`

The production client supports:

- secure Keychain-backed session restore and token refresh
- Sign in with Apple identity-token exchange and Google sign-in
- email magic links with PKCE callback validation
- onboarding completion persisted to `profiles.onboarding_completed_at`
- Stacks, pins, follows, gift claims, collaboration invites, storage and Edge
  Function clients

Sign-in also needs dashboard setup in Supabase **Authentication**: the redirect
URL `stacks://auth/callback`, the Email provider with magic links, and the
Apple and Google providers. Provider keys go into the Supabase dashboard, never
into the app or Git.

The Supabase publishable key is a public client credential. Never place a
service-role key, Apple private key, SerpApi key, or affiliate secret in the
iOS target. The full list of secrets and where each one is set is in Notion
(Engineering Docs → Secrets & configuration checklist).

## Backend

The Supabase schema and functions are versioned in this repository.

### Implemented

- Schema migrations in `supabase/migrations` for profiles, Stacks, items,
  collaborators, pins, follows, claims, imports, moderation, price alerts, push
  tokens and affiliate click records.
- `public` as the default Stack visibility, with `link_only` and `private`
  options, plus public profile RPCs for stacks.spot.
- Row Level Security for owners, accepted collaborators, public viewers, pins,
  follows, product-import drafts, blocks, reports, and private gift claims.
  `SECURITY DEFINER` functions are not callable by anonymous users except the
  waitlist RPCs (migrations `202610290001` and `202610290002`).
- A private `stack-media` Storage bucket with short-lived signed URLs through
  `media-url`, and a public `profile-media` bucket for avatars.
- Signed collaborator uploads through `create-upload-url`, written into the
  Stack owner's media namespace.
- Public/link-only Stack copying through `copy-public-stack`. It creates a
  private copy and duplicates media into the new owner's Storage namespace.
- `web-preview`, which serves Stack, profile and policy data to stacks.spot.
  Policy pages return 503 until the legal name and support email secrets are
  set.
- Gift claims (`claim-gift`, `update-gift-claim`) and collaboration invites
  (`create-`, `preview-`, `accept-collaboration-invite`).
- Price alerts (`price-alerts`, `check-price-alerts`) and push token
  registration (`register-push-token`).
- One product-import path for camera, photo library, pasted links, barcodes and
  queued Share Sheet links: link parsing, on-device Apple Vision background
  removal, then an editable product form.
- Linkless camera/photo items can be saved as **Unidentified Finds**; Buy stays
  disabled until an external URL is supplied.
- Development seed data and RLS smoke tests in `supabase/seed.sql` and
  `supabase/tests/rls_access.sql`.

### Not done yet

- Realtime subscriptions (`RealtimeService` is a no-op).
- `ai-description` and `background-removal` Edge Functions are placeholders;
  cutouts run on device.
- Live product search and Sovrn affiliate links are off until their keys are
  set and the features are switched back on.

Open work is tracked in the Notion Backlog, not in this file.

### Backend Docs

- [Engineering handoff](docs/CODEX_HANDOFF.md)
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

## Live Product Search (SerpApi, currently hidden)

Product search is hidden in the app for launch and `SERPAPI_API_KEY` is not set. To turn it back on: Stacks uses SerpApi's Google Shopping endpoint for live product search. The SerpApi key stays in Supabase; it is never added to the iOS app.

1. Create a SerpApi account and copy the API key from its dashboard. The free plan currently includes 250 searches per month.
2. Link the repository to your Supabase project, then set the secret and deploy the function:

   ```bash
   supabase secrets set SERPAPI_API_KEY=your_serpapi_key
   supabase functions deploy product-search
   ```

3. The search endpoint is derived from the Supabase URL. To override it, set the `INFOPLIST_KEY_STACKS_PRODUCT_SEARCH_URL` build setting (Debug and Release):

   ```text
   https://whyufyttlvpiwlunosjm.supabase.co/functions/v1/product-search
   ```

`STACKS_SUPABASE_ANON_KEY` is the public client key. Do not put `SERPAPI_API_KEY` or a Supabase service-role key in Xcode, source control, or the app binary.

With those values present, in-app product search uses the live Edge Function. Without them, Stacks deliberately falls back to its local demo results so the project remains runnable in Simulator.

## Design Notes

- App background and Stack canvas: white (`stacksCream` is `Color.white`). The app is light-mode only.
- Product stickers use stable free positions, subtle shadows, white halo treatment, and a vertical shimmer while background removal is processing.
- Liquid Glass helpers are guarded for iOS 26+ and fall back to native materials.

## Font Note

`InstrumentSerif-Regular` and `WinkyRough-Black` are bundled in `Stacks/Resources/Fonts`. Product descriptions call `InstrumentSerif-Italic`, which is not bundled, so iOS falls back to a system italic.
