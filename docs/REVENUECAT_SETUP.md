# RevenueCat launch setup

> **Parked (October 2026).** Stacks Pro is paused for launch: `StacksPro.isEnabled = false` in the app and migration `202610280001` makes `user_has_pro` return true on the server, so no limits apply. Release builds may ship without a RevenueCat key while Pro is paused. The steps below are kept for turning Pro back on; the short checklist is in Notion (Engineering Docs → Stacks Pro & RevenueCat). Bundle ID is now `spot.stacks.app` and the Supabase project is `whyufyttlvpiwlunosjm`.

The app is wired for RevenueCat but intentionally contains no private RevenueCat credentials.

## Verified release blockers (September 26, 2026)

- The linked Supabase project's Pro migrations (including `202609210003`) and updated `sync-pro-entitlement` /
  `revenuecat-webhook` functions are deployed, but its secrets list still does **not** contain
  `REVENUECAT_SECRET_API_KEY` or `REVENUECAT_WEBHOOK_AUTHORIZATION`. The functions cannot
  complete a live subscription sync until those are configured.
- RevenueCat currently has no Apple App Store configuration. The project only has Test
  Store products `monthly`, `yearly`, and `lifetime`; the Stacks Pro offering uses the
  first two. Its actual entitlement identifier is `stacks_pro`, now used by the app
  and the two local Edge Functions. The account displayed a notice that its email is
  unconfirmed and a warning that it lacks permission to add app configurations.
- The existing dashboard paywall has unrelated sample artwork, a sample $79.99/year
  price, and an unverified Family Sharing control. The app now deliberately uses its
  own RevenueCat-backed paywall with live package prices instead of rendering that
  template. Do not enable the dashboard template until its content is reviewed.
- The Release build's public Apple SDK key is empty. The Debug Test Store key must not
  be copied into Release. An Apple-platform app, App Store Connect subscriptions, and
  the matching RevenueCat entitlement/offering/paywall must be configured first.
- The native paywall shows only actual products and localized App Store prices.
  It does not claim a free trial until the App Store offer is verified. The local
  StoreKit file models an annual trial only; it is not App Store Connect configuration.
  A draft or unassigned RevenueCat paywall falls back to this native Stacks screen
  rather than showing RevenueCat's generic default design.

An App Store submission is not ready until a signed TestFlight build proves purchase,
restore, entitlement sync, server-side Pro limits, cancellation/expiry, and the live
paywall/Terms/Privacy links on a real device.

1. Confirm the RevenueCat account email and use a project role that can add app configurations.
2. Complete Apple's Paid Apps Agreement, tax and banking setup, and create the two
   auto-renewable subscriptions in one App Store Connect group for bundle ID
   `spot.stacks.app`: `stacks.pro.monthly` at **$2.99/month** and
   `stacks.pro.annual` at **$14.99/year**. Configure equivalent regional tiers in
   App Store Connect; RevenueCat and the app must display Apple's localized price.
3. Create the iOS App Store configuration in RevenueCat and import those subscriptions.
   Attach both to the **existing `stacks_pro` entitlement**. Add them as the monthly
   and annual packages in the **existing `Stacks Pro` offering**. The generic
   `default` offering's lifetime test product must not be sold by the iOS app.
4. The native paywall can be submitted without publishing a RevenueCat dashboard
   template. If using workflow `wf99d6f78fd54844d6` later, replace all unrelated
   artwork/copy, price claims, and Family Sharing controls; then publish and verify it
   before changing the app to render it. The `wf...` value is not an offering ID.
5. If a seven-day annual trial is wanted, configure it in App Store Connect and show
   accurate trial/end-price copy before claiming it on the paywall. The local StoreKit
   file alone does not create a real introductory offer.
6. The Debug target uses the RevenueCat Test Store SDK key. Put the production
   **public Apple SDK key** in the Release target build setting
   `INFOPLIST_KEY_STACKS_REVENUECAT_API_KEY`. The Release key must start with `appl_`;
   never put a secret key or a `test_` key there. The app target's Release build
   validation step refuses to build without an Apple public key.
7. Add Supabase project secrets:
   - `REVENUECAT_SECRET_API_KEY`: RevenueCat secret key with read-only customer access.
   - `REVENUECAT_WEBHOOK_AUTHORIZATION`: a long random Authorization header value.
8. Migration `202609210003_revenuecat_entitlements.sql` is applied. The deployed
   `sync-pro-entitlement` and `revenuecat-webhook` now read `stacks_pro`.
9. In RevenueCat, create production and sandbox webhooks pointing to
   `https://whyufyttlvpiwlunosjm.supabase.co/functions/v1/revenuecat-webhook` and use the exact
   configured Authorization header.
10. Price alerts use `202610040001_price_alerts.sql`, `price-alerts`, and the hourly Cloudflare
    Cron trigger in `web/wrangler.toml`; individual products are checked approximately daily.
    Configure the Supabase secrets `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY`, and
    `APNS_BUNDLE_ID=spot.stacks.app` before enabling notifications on production devices.
    `APNS_PRIVATE_KEY` must be the contents of Apple's `.p8` key and must never be committed.
    The app remains useful without notification authorization: alert history and current status
    are visible in Profile > Settings > Price Alerts.

The app uses the authenticated Supabase UUID as RevenueCat's App User ID. This is required so
webhooks can update the correct server-side entitlement row and database limits cannot be bypassed.
The Test Store key in Debug can exercise the purchase UI but cannot prove the final
server-side limits. Validate those with the Apple sandbox and production public key.
