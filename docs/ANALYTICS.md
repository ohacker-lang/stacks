# Stacks analytics (PostHog)

Product analytics for the iPhone app and stacks.spot, sent to PostHog. This
file is the source of truth for event names; add new events here first.

## Setup

| Where | Setting | Notes |
| --- | --- | --- |
| iOS (Release) | `INFOPLIST_KEY_STACKS_POSTHOG_API_KEY` | The PostHog **project API key** (`phc_…`). It is a public, write-only client key. Empty = analytics off. |
| iOS (Debug) | same setting, Debug configuration | Leave empty, or use a separate "Stacks Dev" PostHog project so testing never pollutes launch metrics. |
| iOS | `INFOPLIST_KEY_STACKS_POSTHOG_HOST` | `https://us.i.posthog.com` (or `https://eu.i.posthog.com` for an EU project). |
| Web | `POSTHOG_KEY` / `POSTHOG_HOST` in `web/wrangler.toml` `[vars]` | Empty key = `/analytics.js` is a no-op. |

Never put a PostHog **personal** API key (`phx_…`) in the app, the website or Git.

## Identity and privacy

- Signed-in people are identified by their Stacks account UUID only. No email,
  name or username is sent as a person property.
- Signing out calls `reset()`, so a shared device does not merge two people.
- No cross-app tracking, no advertising identifiers, no ATT prompt needed.
- Session replay is **off**. Turning it on later needs a privacy-policy and
  App Store privacy-label update first.
- People can turn analytics off in **Settings → Privacy choices → Share usage
  analytics**; this opts the device out in PostHog.
- The website stores nothing on the visitor's device (`persistence: memory`),
  so it needs no cookie banner. Each page view is anonymous.
- App Store privacy answers: add **Product Interaction**, linked to the user,
  used for **Analytics**, not used for tracking.

## Metrics this supports

| Metric | How |
| --- | --- |
| DAU / WAU / MAU | Unique identified users with any event (`Application Opened` is captured automatically). |
| Activation funnel | `signed_in` → `profile_set_up` → `onboarding_completed` → `stack_created` → `item_saved` → `stack_shared` |
| Retention | Users returning with `Application Opened` or `item_saved` in week N. |
| Journeys / paths | `$screen` events plus the events below. |
| Import quality | `item_import_finished.outcome` and `background_removal_finished.result` by `source` / `retailer_host`. |
| Web reach | `$pageview` on stacks.spot by `page_type`, and `buy_clicked`. |

## App events

| Event | Properties | Fired when |
| --- | --- | --- |
| `Application Opened` / `Application Backgrounded` / `Application Installed` / `Application Updated` | (automatic) | App lifecycle, from the PostHog SDK. |
| `$screen` | `$screen_name` | A main screen appears: Home, Discover, Stack, Product, Profile, Settings, Add, Onboarding. |
| `signed_in` | `method` (apple, google, email), `is_new_user` | Sign-in succeeds. |
| `onboarding_step_viewed` | `step` | Each onboarding page. |
| `profile_set_up` | `has_photo` | The name and @handle step in onboarding is saved. |
| `onboarding_completed` | | Onboarding finishes. |
| `signed_out` | | Sign out. |
| `account_deleted` | | Account deletion succeeds. |
| `stack_created` | `visibility`, `wishlist` | A Stack is created anywhere in the app. |
| `stack_updated` | `visibility`, `visibility_changed`, `wishlist` | Title, visibility or wishlist mode saved. |
| `stack_deleted` | | |
| `stack_copied` | | Someone copies a public Stack. |
| `stack_pinned` / `stack_unpinned` | | |
| `creator_followed` / `creator_unfollowed` | | |
| `item_import_started` | `source` (link, barcode) | A link or barcode lookup begins. |
| `item_import_finished` | `source`, `outcome` (ok, no_image, failed), `has_price`, `retailer_host`, `duration_ms` | The lookup returns. |
| `background_removal_finished` | `result` (ok, failed), `source`, `duration_ms` | A cutout attempt ends. |
| `item_saved` | `source` (pastedLink, camera, photoLibrary, search, shareSheet, barcode, …), `has_link`, `has_price`, `stack_visibility` | An item is saved to a Stack. |
| `item_removed` | | |
| `stack_shared` | `visibility` | The Stack share button is tapped. |
| `profile_shared` | | Share profile is tapped. |
| `product_shared` | | A product's share button is tapped. |
| `buy_tapped` | `retailer_host`, `commissionable` | Buy is tapped on a product. |

## Web events (stacks.spot)

| Event | Properties | Fired when |
| --- | --- | --- |
| `$pageview` | `page_type` (home, profile, board, pin, explore, waitlist, demo, legal, wishlist), `profile_username`, `stack_slug` | Any page load. |
| `buy_clicked` | `retailer_host` | "View at …" on a pin page. |
| `share_clicked` | `page_type` | Share button on a profile or board. |
| `waitlist_joined` | | Waitlist signup succeeds. |
