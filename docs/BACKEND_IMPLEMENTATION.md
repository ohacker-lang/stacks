# Stacks Backend Implementation Plan

## Status

**Current as of October 29, 2026.** The backend runs on Supabase project
`whyufyttlvpiwlunosjm`, created in October 2026 to replace the earlier
`iuovmgjcfwgwozfnsdgf` and `hpjiphvgmhvvvfxkunwb` projects. All 26 migrations
in `supabase/migrations` are applied, the private `stack-media` and public
`profile-media` buckets are in place, and all 20 Edge Functions are deployed.
The iOS project contains the project URL and publishable key; Row Level
Security protects that key. Server secrets and third-party provider
credentials remain in Supabase only.

The migrations in `supabase/migrations` are the production source of truth for
account profiles, Stacks, collaborators, items, pins, follows, private gift
claims, import drafts, safety controls, price alerts, push tokens, affiliate
click records, and media storage. Read `docs/SUPABASE_SECURITY_RUNBOOK.md`
before deploying them. The secrets each function needs are listed in Notion
(Engineering Docs → Secrets & configuration checklist).

### Development environment

- Supabase project reference: `whyufyttlvpiwlunosjm`
- Project URL: `https://whyufyttlvpiwlunosjm.supabase.co`
- Database password, service-role key, provider credentials, and edge-function secrets must never be committed or sent in chat.

## Deploy Order

1. Create separate Supabase **development**, **staging**, and **production** projects.
2. Install the Supabase CLI and run `supabase link --project-ref whyufyttlvpiwlunosjm` from this repository.
3. Review the migration in the Supabase SQL editor, then run `supabase db push` against development.
4. Enable Apple, Google and email authentication in Supabase Auth. Configure the bundle ID `spot.stacks.app`, the redirect URL `stacks://auth/callback`, and the Apple and Google provider credentials.
5. Create the private `stack-media` bucket through the migration. Do not make product photos public.
6. Add edge-function secrets only in Supabase: retailer/search credentials, affiliate credentials, and any optional server-side image-removal token. Never add these to Xcode, Git, or an iOS build setting.
7. Deploy functions to development, test every failure path, then repeat against staging before production.

## Data Model Decisions

### Pins, not bookmarks

`stack_pins` is the only saved-Stack table. The app's existing `isBookmarked` and `toggleBookmark` names are temporary client compatibility names and should be renamed to `isPinned` / `togglePin` when the Supabase repository is implemented.

### Visibility

The schema uses three exact values:

- `private`: owner and accepted collaborators only.
- `link_only`: fetched by an opaque `public_link_token` through `get_link_only_stack(token)`; it is not broadly readable through normal table queries.
- `public`: eligible for Discover when the owner has enabled discovery, and shown on the owner's stacks.spot profile page.

New Stacks default to `public` (migration `202610280002`); owners can switch any Stack to `link_only` or `private`.

### Media

The client stores image paths, not public URLs. Originals and removal output live under a user-owned `stack-media/<user-id>/...` prefix. The backend returns short-lived signed URLs only after it checks Stack visibility.

### Unidentified Finds

`source_url` and `buy_url` are nullable for camera, photo-library, and manual-photo items. The generated `needs_link` column drives the UI prompt to complete a find later.

### Gift claims

The Stack owner has no select policy on `gift_claims`. This preserves the core wishlist promise that owners cannot see who has claimed an item.

## Edge Functions

All functions require a Supabase user JWT except `web-preview`,
`revenuecat-webhook` and `check-price-alerts` (see `supabase/config.toml`).

| Function | Caller | Responsibility | Status |
| --- | --- | --- | --- |
| `product-search` | app | Search provider wrapper and normalization | deployed; search is hidden in the app and `SERPAPI_API_KEY` is not set |
| `link-parser` | app | SSRF-safe URL fetch, metadata extraction, image ranking | live |
| `background-removal` | app | Server fallback for removal | placeholder; cutouts run on device with Apple Vision |
| `affiliate-link` | app | Validate target and wrap eligible retailer URL | deployed; returns the original URL until Sovrn is configured |
| `ai-description` | app | Optional short editable description | placeholder with deterministic fallback copy |
| `media-url` | app | Authorize a Stack, then issue a short-lived private media URL | live |
| `create-upload-url` | app | Authorize editor upload into the Stack owner media namespace | live |
| `copy-public-stack` | app | Copy authorized public/link-only Stack rows and media into a private Stack | live |
| `claim-gift` / `update-gift-claim` | app | Claim or release a wishlist item without revealing the claimer to the owner | live |
| `create-collaboration-invite` / `preview-collaboration-invite` / `accept-collaboration-invite` | app | Invite, preview and accept Stack collaborators | live |
| `register-push-token` | app | Store the device's APNs token | live |
| `price-alerts` | app | Create, list and delete price alerts | live |
| `check-price-alerts` | Cloudflare cron (hourly) | Re-check prices and send APNs pushes; requires `PRICE_CHECK_SECRET` | live once APNs secrets are set |
| `web-preview` | stacks.spot (no JWT) | Public profile, board, pin and policy data for the website | live; policy pages return 503 until `STACKS_LEGAL_NAME` and `STACKS_SUPPORT_EMAIL` are set |
| `sync-pro-entitlement` | app | Sync RevenueCat entitlement | parked while Stacks Pro is paused |
| `revenuecat-webhook` | RevenueCat (no JWT) | Entitlement webhook | parked; returns 500 until its secret is set |
| `delete-account` | app | Remove nested private media and delete auth user | live |

## Security Contract for Edge Functions

- Require and validate the Supabase user JWT for every app-facing function except a tightly scoped public web preview.
- Treat all source URLs as hostile: allow only `http`/`https`, block private/local IP ranges, cap redirects, cap response size, timeout requests, and validate returned content types.
- Use the service-role key only inside edge functions. It must never be compiled into the app.
- Rate-limit searches, URL parsing, AI descriptions, background removal, follows, reports, and affiliate wrapping per user and IP.
- Store only the parsed fields and image assets required for the import; never persist product-page HTML.
- Use signed media URLs with a short expiration. Regenerate them on reload rather than making the bucket public.

## iOS Service Mapping

| Current app protocol | Production implementation |
| --- | --- |
| `AuthService` | `SupabaseAuthService` using Supabase Swift + native Authentication Services |
| `StackRepository` | Supabase queries/RPCs for private data; edge functions for copy and public web-link resolution |
| `ProfileRepository` | `profiles`, follows count, pins count, signed avatar URLs |
| `ProductSearchService` | `product-search` and `link-parser` edge functions |
| `BackgroundRemovalService` | Apple Vision first, then `background-removal` only as a fallback / asynchronous retry |
| `StorageService` | Supabase Storage upload + signed URL service |
| `AffiliateService` | `affiliate-link` edge function |
| `ClaimService` | `claim-gift` and `update-gift-claim`, which preserve owner privacy |
| `CollaborationService` | `stack_collaborators` plus the three collaboration-invite functions |
| `RealtimeService` | Supabase Realtime subscription scoped to the active Stack (not implemented yet; currently a no-op) |

## Remaining Production Configuration

The deployed backend does not invent accounts or credentials. Before release:

1. Add the Apple and Google provider credentials and Resend SMTP in Supabase Auth.
2. Set the APNs secrets (`APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_BUNDLE_ID=spot.stacks.app`, `APNS_PRIVATE_KEY`) so price-alert pushes send.
3. Set `STACKS_LEGAL_NAME`, `STACKS_SUPPORT_EMAIL` and `STACKS_PUBLIC_SITE_URL` so the policy pages on stacks.spot work.
4. Prove RLS policies with two test accounts on a physical device.

Later, and only when the features are switched back on: `SERPAPI_API_KEY` for
product search, Sovrn credentials for commissionable Buy links, and the
RevenueCat secrets for Stacks Pro. Open work is tracked in the Notion Backlog.
