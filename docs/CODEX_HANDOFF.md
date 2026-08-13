# Stacks Engineering Handoff

**Last audited:** August 13, 2026
**Audience:** a new Codex account or engineer continuing the project
**iOS baseline:** iOS 18+, SwiftUI, Swift 6 concurrency checks

## Read This First

Stacks is a visual wishlist and curation app. People save products, objects, and references as background-removed cutouts in a visual collection called a **Stack**. An item should remain useful even when product scraping fails: its title, image, brand, description, price, size, source URL, and buy URL are editable before save. Photo-only items without a known link are explicitly allowed as **Unidentified Finds**.

This repository contains a working SwiftUI app, a deployed Supabase foundation, and live client wiring. It is **not ready for App Store release yet**. The remaining work is mostly operational configuration, provider integrations, and a few intentionally unimplemented services. Do not replace live service code with mocks while iterating on UI. `AppServices.configured()` selects live Supabase whenever its public configuration is available and keeps mocks as an offline/preview fallback.

## Product Decisions Already Locked

| Decision | Current rule |
| --- | --- |
| Default Stack visibility | `private` |
| Sharing modes | `private`, `link_only`, `public` |
| Saved other-user Stack | **Pin / Pinned**. This replaces user-facing “bookmark.” |
| Copying | Every viewable public or link-only Stack may be copied; copies are private and attributed to their source. |
| Photo without a link | Allowed as an **Unidentified Find**. |
| Wishlist claims | Private to the claimer; the Stack owner must not see the claim or claimer. |
| Affiliate disclosure | Show only when a Buy link is commissionable. |
| Design | White editorial canvases, cutout products, SF Pro for UI/title treatments, Instrument Serif only where intentionally used in onboarding/editorial copy. |

The public support email, Privacy Policy URL, and Terms URL are still TBD.

## What Works Now

### Authentication and onboarding

- `AppSession` restores a Keychain-persisted Supabase session and refreshes it.
- Email sign-in uses a magic link with PKCE and handles `stacks://auth/callback`.
- Native Sign in with Apple exchanges the Apple identity token with Supabase.
- Finishing onboarding persists `profiles.onboarding_completed_at`.
- The Sign in with Apple entitlement is present in `Stacks/Stacks.entitlements`.

### Stack data and social actions

- Live Stack fetching, creation, update, item save/update/delete, pin/unpin, follow/unfollow, profile loading, and public/link-only Stack copying are implemented in `Stacks/Services/ProductionServicePlaceholders.swift`.
- Stack creation always writes `visibility: private`.
- Item media is private in Storage. The app stores final original/cutout files in the owner/Stack/item namespace on save, then reads them through authorized signed URLs.

### Product import and review

All import routes converge into the same staged review path:

1. Camera, photo library, pasted link, or Share Sheet URL produces an import draft.
2. The acquired or scraped image fills a white screen by itself.
3. Apple Vision foreground masking runs immediately. A vertical shimmer lasts at least three seconds so the state is legible.
4. The foreground PNG is revealed and a success haptic is issued.
5. The editable product form appears with title, details, brand, price, source link, and buy link. Scraped fields are filled when available; missing fields visibly invite input.
6. A linkless photo can save as an Unidentified Find. Its Buy action stays disabled until the user supplies an external HTTP(S) link.

The principal UI files are:

- `Stacks/Views/Stack/AddItemSheets.swift`
- `Stacks/Views/Product/ProductDetailView.swift`
- `Stacks/Models/StackItem.swift`
- `Stacks/Services/AppleVisionBackgroundRemovalService.swift`

### Supabase foundation

The development project ref is `hpjiphvgmhvvvfxkunwb`. Its URL and a **public anon/publishable client key** are presently configured in Debug and Release build settings. This is normal for a Supabase client; it is not a service-role credential. Never add a service-role key, Apple private key, SerpApi key, Sovrn secret, database password, or OAuth private credential to the Xcode project, Git, or a chat transcript.

Applied migrations:

1. `supabase/migrations/202608130001_initial_stacks_v1.sql`
2. `supabase/migrations/202608130002_access_hardening.sql`

They create profiles, Stacks, items, collaborators, pins, follows, claims, product-import drafts, blocks, reports, affiliate click records, RLS policies, and the private `stack-media` Storage bucket.

Deployed functions:

| Function | Current role | State |
| --- | --- | --- |
| `link-parser` | Fetch and normalize product metadata/image candidates | Live; authenticated |
| `product-search` | SerpApi shopping search wrapper | Live; returns `503` until `SERPAPI_API_KEY` is set |
| `background-removal` | Server-side fallback | Live endpoint; intentionally returns retryable `503` because iOS Apple Vision is primary |
| `affiliate-link` | Validate/wrap commissionable outbound links | Live; returns original link until Sovrn is configured |
| `ai-description` | Optional editable product copy | Live deterministic fallback |
| `create-upload-url` | Authorized collaborator upload support | Live |
| `media-url` | Authorize and issue signed private media URLs | Live |
| `copy-public-stack` | Copy allowed shared Stacks/media into a private Stack | Live |
| `delete-account` | Remove account and private media | Live |
| `web-preview` | Future read-only browser Stack page | Deployed but deliberately `501` until the web surface is built |

## What Is Intentionally Incomplete

Treat these as real engineering tasks, not cosmetic polish:

1. **Authentication dashboard setup:** Supabase needs `stacks://auth/callback` in redirect URLs, Email/Magic Link enabled, and Apple enabled with credentials. Xcode needs the final Apple Developer team selected. This cannot be safely committed from code.
2. **Product search:** Set `SERPAPI_API_KEY` as a Supabase Edge Function secret. Until then search returns a controlled unavailable response; local demo results may still appear in offline fallback mode.
3. **Link parsing quality:** The Edge Function is a reasonable first parser but merchant anti-bot pages, dynamic storefronts, and image ranking need observability, retry/fallback rules, and a real-device test matrix.
4. **Background-removal fallback:** Apple Vision is implemented locally. Add a server provider only for failed Vision cases; do not simulate a successful removal when it fails.
5. **Affiliate commerce:** Configure Sovrn before any commissionable link is marked as such. Add the disclosure only for wrapped/commissionable links.
6. **Claims and collaboration:** The schema/RLS exists, but client claim calls and collaborator invitation delivery still return configuration-required errors. Implement narrow server/RPC paths that retain gift-claim privacy.
7. **Realtime:** `SupabaseRealtimeService` is currently a no-op. Add subscriptions only after active Stack access rules and reconnection behavior are tested.
8. **Web preview:** Do not publish public web links until `web-preview` has a read-only web consumer with link-only token handling, no analytics leaks, and signed media refresh.
9. **Profile persistence:** Profile read works; avatar upload/edit/settings UI needs full persistence, validation, and account-delete confirmation UX.
10. **Launch operations:** privacy policy, terms, support email, App Store privacy nutrition labels, reporting/moderation operations, rate limits, monitoring, error reporting, and separate dev/staging/prod projects remain.

## Code Map

| Area | Start here |
| --- | --- |
| App composition and auth routing | `Stacks/StacksApp.swift`, `Stacks/ViewModels/AppSession.swift` |
| Service selection | `Stacks/Services/AppServices.swift` |
| Supabase REST/auth/storage client | `Stacks/Services/ProductionServicePlaceholders.swift` |
| Protocol boundaries | `Stacks/Services/ServiceProtocols.swift` |
| Native Vision removal | `Stacks/Services/AppleVisionBackgroundRemovalService.swift` |
| Import UI/state | `Stacks/Views/Stack/AddItemSheets.swift` |
| Existing product screen | `Stacks/Views/Product/ProductDetailView.swift` |
| Models | `Stacks/Models/` |
| Product specification | `docs/PRD.md`, `docs/V1_PRODUCT_CONTRACT.md` |
| Backend details | `docs/BACKEND_IMPLEMENTATION.md`, `docs/SUPABASE_SECURITY_RUNBOOK.md` |
| Schema/RLS | `supabase/migrations/` |
| Edge functions | `supabase/functions/` |
| RLS smoke test/data | `supabase/tests/rls_access.sql`, `supabase/seed.sql` |

## Verification Performed At This Handoff

- `xcodebuild` has succeeded against an iPhone Simulator destination with code signing disabled.
- `plutil -lint Stacks.xcodeproj/project.pbxproj` passes.
- `git diff --check` passes before this documentation-only consolidation.
- Unit coverage in `StacksTests/StacksModelTests.swift` covers core model behavior, mock persistence, shared-link queueing, parser fixtures, and Apple Vision transparent-PNG output.

Known local limitations: Simulator camera behavior and Vision masking quality are not representative of a physical iPhone. Test capture, Vision removal, Apple sign-in, magic-link callbacks, signed Storage URLs, and background/foreground transitions on a real iPhone before beta.

## Run and Validate

### iOS build

```bash
xcodebuild \
  -project Stacks.xcodeproj \
  -scheme Stacks \
  -sdk iphonesimulator \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build CODE_SIGNING_ALLOWED=NO
```

If that exact simulator name is unavailable, choose an installed iOS 18+ simulator in Xcode and adjust the destination.

### Local Supabase validation

Docker Desktop must be running. The Supabase CLI is intentionally not committed.

```bash
supabase start
supabase db reset
supabase db lint --local
psql "$LOCAL_DB_URL" -f supabase/tests/rls_access.sql
```

### Hosted deployment checks

1. Link the CLI to the intended non-production project.
2. Apply migrations with `supabase db push`.
3. Deploy functions with `supabase functions deploy <function-name>`.
4. Set provider secrets only with `supabase secrets set ...`.
5. Test each endpoint using two normal test users: owner, collaborator, public viewer, blocked viewer, and gift claimer.

## Recommended Next Work Order

1. **Finish a real-device auth and capture QA pass.** Configure redirect URLs and Apple/email providers, then test create Stack, each import route, Vision success/failure, private media reload, pin, follow, and copy.
2. **Make import reliability measurable.** Add structured failure reasons and tests for blocked merchants/no image/invalid URL/no network. Preserve drafts.
3. **Complete collaboration and wishlist claims.** Build server-authorized invitation and claim flows, then test that owners cannot infer claims.
4. **Add production product-search/affiliate secrets and disclosure behavior.** Treat vendor credentials as environment-only.
5. **Implement Realtime and a web preview only after RLS tests are expanded.**
6. **Do launch readiness work:** legal URLs, support, accessibility, error reporting, analytics consent, moderation operations, App Store metadata, screenshots, TestFlight, and privacy review.

## Working Rules For The Next Codex

- Read this file, `docs/V1_PRODUCT_CONTRACT.md`, and the current `git diff` before editing. Several agents have contributed work; preserve changes that are not part of the present task.
- Use the existing protocol/service boundaries. New backend calls should be authenticated Edge Functions or RLS-protected Supabase queries, never client service-role access.
- Keep `stack-media` private. Only issue signed URLs after authorization.
- Preserve the single capture-to-review pipeline. Do not create a separate product editor for camera, paste, and Share Sheet paths.
- Do not silently fabricate scrape data, background removal, affiliate status, or purchase links. Show editable fallbacks and retain the user's source URL.
- User-facing terminology is **Pin/Pinned**, not Bookmark. Existing code names may retain `bookmark` temporarily for compatibility; rename in a scoped pass.
- Run `git diff --check` and an iOS build before committing. Keep generated CLI state (`.tools/`, `supabase/.temp/`) and temporary screenshots out of Git.

## Definition Of Done For V1 Beta

A beta is ready when a real iPhone can authenticate, create a private Stack, import an image or product URL, review/edit it, see a genuine cutout or honest failure state, save/reload private media, pin/follow/copy an eligible Stack, and delete its account. It must do this without exposing private media, link-only capabilities, gift claims, or secret credentials.
