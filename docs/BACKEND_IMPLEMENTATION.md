# Stacks Backend Implementation Plan

## Status

**Deployed to the Stacks Supabase project on August 13, 2026.** The two
migrations are applied, the private `stack-media` bucket is in place, and all
10 Edge Functions are active. The iOS project contains the project URL and
publishable anon key; Row Level Security protects that key. Server secrets and
third-party provider credentials remain in Supabase only.

The canonical migrations are ready at:

`supabase/migrations/202608130001_initial_stacks_v1.sql`

`supabase/migrations/202608130002_access_hardening.sql`

Together they are the production source of truth for account profiles, Stacks,
collaborators, items, pins, follows, private gift claims, import drafts, safety
controls, affiliate click records, and private media storage. Read
`docs/SUPABASE_SECURITY_RUNBOOK.md` before deploying them.

### Development environment

- Supabase project reference: `hpjiphvgmhvvvfxkunwb`
- Project URL: `https://hpjiphvgmhvvvfxkunwb.supabase.co`
- Database password, service-role key, provider credentials, and edge-function secrets must never be committed or sent in chat.

## Deploy Order

1. Create separate Supabase **development**, **staging**, and **production** projects.
2. Install the Supabase CLI and run `supabase link --project-ref hpjiphvgmhvvvfxkunwb` from this repository.
3. Review the migration in the Supabase SQL editor, then run `supabase db push` against development.
4. Enable Apple and email authentication in Supabase Auth. Configure the iOS bundle ID, redirect URLs, and Apple provider credentials.
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
- `public`: eligible for Discover when the owner has enabled discovery.

### Media

The client stores image paths, not public URLs. Originals and removal output live under a user-owned `stack-media/<user-id>/...` prefix. The backend returns short-lived signed URLs only after it checks Stack visibility.

### Unidentified Finds

`source_url` and `buy_url` are nullable for camera, photo-library, and manual-photo items. The generated `needs_link` column drives the UI prompt to complete a find later.

### Gift claims

The Stack owner has no select policy on `gift_claims`. This preserves the core wishlist promise that owners cannot see who has claimed an item.

## Required Edge Functions

| Function | Caller | Responsibility | Status |
| --- | --- | --- | --- |
| `product-search` | authenticated app | Search provider wrapper and normalization | active; requires `SERPAPI_API_KEY` |
| `link-parser` | authenticated app | SSRF-safe URL fetch, metadata extraction, image ranking | active |
| `background-removal` | authenticated app / worker | Server fallback for removal | active; returns an honest retryable failure until configured, while iOS uses Apple Vision first |
| `affiliate-link` | authenticated app | Validate target and wrap eligible retailer URL | active; preserves original URL until Sovrn credentials are configured |
| `ai-description` | authenticated app | Generate an optional short editable description | active with deterministic fallback copy |
| `media-url` | authenticated app | Authorize a Stack, then issue a short-lived private media URL | implemented |
| `create-upload-url` | authenticated app | Authorize editor upload into the Stack owner media namespace | implemented |
| `copy-public-stack` | authenticated app | Copy authorized public/link-only Stack rows and media into a private Stack | implemented |
| `web-preview` | unauthenticated viewer | Resolve only public/link-only stacks to a read-only signed-media payload | deliberately disabled (`501`) until its public web experience is implemented |
| `delete-account` | authenticated app | Remove nested private media and delete auth user | active |

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
| `ClaimService` | `gift_claims` through a narrow RPC/function that preserves owner privacy |
| `CollaborationService` | `stack_collaborators` plus invitation edge function/email sender |
| `RealtimeService` | Supabase Realtime subscription scoped to the active Stack |

## Remaining Production Configuration

The deployed backend does not invent accounts or credentials. Before release:

1. Enable Email OTP and Sign in with Apple in Supabase Auth, then add Apple’s
   Services ID, key, team, and final bundle identifier.
2. Set `SERPAPI_API_KEY` in Supabase Edge Function secrets to enable search.
3. Add a server image-removal provider only if Apple Vision needs a fallback.
4. Add Sovrn Commerce credentials before commissionable Buy links are enabled.
5. Add support email, Privacy Policy URL, and Terms URL before App Store review.
6. Implement `web-preview` before advertising browser-share links.

## Current Client Integration and Next Steps

`StacksApp` now starts with `AppServices.configured()`. It selects the
Supabase-backed service bundle whenever the public project URL and anon key are
available, while retaining `AppServices.mock()` for offline previews and UI
work. The live service layer covers auth, Stack CRUD, pins, follows, copying,
and final Storage persistence; see `docs/CODEX_HANDOFF.md` for the exact
boundary.

- Prove RLS policies with two test accounts before beta.
- Enable Email/Magic Link and Apple in Supabase, configure the redirect URL,
  then test the live service bundle on a physical device.
- Rename remaining user-facing Bookmark labels and compatibility code paths to
  Pin in a focused pass.
- Implement gift claims, collaboration invitations, Realtime subscriptions,
  and profile/avatar edits before representing them as live features.
- Add Development, Staging, and Production configurations. Commit only public
  project URL and publishable key configuration; inject sensitive server
  secrets in Supabase.
