# Stacks

Stacks is a SwiftUI iOS 18+ wishlist and curation app. It opens through onboarding, then lets users create visual Stacks of background-removed product stickers, add items by search/link/photo, open product details with buy links, and discover/follow/bookmark other creators.

## Product Requirements

The product vision, V1 scope, user flows, launch criteria, and the camera-first **Stack Scout** capture experience are maintained in [docs/PRD.md](docs/PRD.md). Treat that document as the canonical product reference when making product or UX decisions.

## Open in Xcode

1. Clone or download this repository.
2. Open `Stacks.xcodeproj`.
3. Select the `Stacks` scheme.
4. Choose an iOS 18+ simulator.
5. Run.

The current build uses mock services and demo data by default, so it does not need Supabase, Replicate, SerpAPI, Sovrn, or Apple developer credentials to launch in Simulator.

## Live Backend Swap

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

Replace `AppServices.mock()` in `StacksApp.swift` with `AppServices.supabaseBackedPlaceholder()` after implementing the Supabase and edge-function clients.

Starter Supabase Edge Function stubs live in `supabase/functions` for product search, link parsing, background removal, AI descriptions, affiliate wrapping, and web previews.

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
