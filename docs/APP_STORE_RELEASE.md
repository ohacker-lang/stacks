# Stacks release gates

This is a release checklist, not a statement that the app is approved or legally reviewed.
Do not select **All Countries or Regions** until every gate below is complete.

## Current code paths

- iPhone-only target; the unfinished in-app product-search entry is hidden.
- Discover Stacks and public profiles offer report and block actions backed by
  `content_reports` and `user_blocks`.
- Account deletion now removes avatar and Stack media, hard-deletes the auth
  user so profile cascades run, and shows success only after the server returns
  successfully. This still needs a two-account production verification.
- Product Buy resolves a region-specific Sovrn Link Check result. If the network is
  unavailable, unconfigured, or says a retailer is ineligible, Buy uses the
  original retailer URL. A plain-language `Ad`/commission disclosure is displayed
  directly before Buy only for a confirmed commissionable link. The full
  Affiliate Disclosure is linked from the product screen and Profile settings.
- Link-only and public Stacks can be shared via the `web-preview` Edge Function.
  A browser request receives a white Stack view with cutout placements and
  product details. Browser wishlist claims require an email code.
- The same endpoint has `?page=privacy`, `privacy-choices`, `terms`, `affiliate`,
  `security`, and `support`.
  Policy pages return 503 until a real operator name and support email are set.

## Configuration and deployment

1. Reconcile local SQL migrations against the linked project. Run RLS tests
   with distinct owner, collaborator, public viewer, blocked viewer, and gift
   claimant accounts. Include the inviter-foreign-key account-deletion migration.
   The remote migration-list check last failed on a database
   connection timeout; **do not assume the schema matches local files**.
2. Configure a real support address, legal operator name, and approved App
   Store listing URL in Supabase Edge Function secrets:

   - `STACKS_SUPPORT_EMAIL`
   - `STACKS_LEGAL_NAME`
   - `STACKS_APP_STORE_URL` (after Apple supplies the listing)
   - `SOVRN_COMMERCE_API_KEY` (after the campaign and Link Check API are approved)
   - `SOVRN_ENABLED_COUNTRIES` (comma-separated ISO country codes validated
     for monetization; leave unset to use original retailer links everywhere)

3. Configure the Supabase email template to include a one-time code. The web
   claim flow calls `/auth/v1/otp` and `/auth/v1/verify`; test that a new guest
   can receive, enter, and verify the code before relying on browser claims.
4. Test `web-preview`, `affiliate-link`, and `delete-account` in staging, then deploy those
   functions to production. Keep the `web-preview` JWT check disabled and its
   Stack visibility/token checks intact. Keep `affiliate-link` JWT-protected.
5. Obtain a domain. Host or proxy the viewer and policy routes there, set up
   Apple App Site Association and Associated Domains, and replace the temporary
   Supabase-function share URLs with domain URLs. Do not submit temporary URLs
   as final App Store policy/support URLs.

## Affiliate release gate

- Read and complete `docs/AFFILIATE_COMPLIANCE.md`. Have counsel review the live
  Privacy Policy, Terms, Affiliate Disclosure, creator-content rules, and the
  operator/contact information for the intended launch countries.
- Test that the disclosure is already visible before every confirmed
  commissionable Buy action. “Affiliate link,” a footer-only policy, or a notice
  shown after the click is not sufficient.
- Keep browser product links non-affiliate until the browser has the same
  pre-click disclosure and server-side regional eligibility check. When browser
  monetization is added, mark qualifying outbound links with
  `rel="sponsored noopener noreferrer"`.
- Confirm the affiliate resolver receives only destination URL and country code.
  Before adding an affiliate/ad SDK or sending a user, device, advertising, or
  cross-company identifier, reassess ATT, consent, the privacy manifest, the
  privacy policy, and App Store Connect privacy answers.
- In App Store Review Notes, explain that links sell physical goods outside the
  app, identify the exact disclosure text and navigation path, and provide a
  review account plus a commissionable test product if one is available.
- Test eligible, ineligible, failure, and original-link fallback cases in every
  enabled affiliate region. The app must never claim a commission for an
  unconfirmed or unsupported destination.

## Apple and legal

- Enroll in the paid Apple Developer Program; finish signing, Sign in with
  Apple, App Store Connect record, age rating, privacy nutrition labels,
  screenshots, review credentials, and support/privacy URLs.
- In App Store Connect, set the public Privacy Policy URL and Support URL; keep
  App Privacy answers accurate for app code, server processing, and all partners.
  The current server-side flow has no ad SDK or user/device identifier sharing;
  any future change requires a new ATT and privacy review before release.
- Review the privacy and terms copy with counsel. Verify the operator identity,
  contact information, data retention, international transfers, consumer
  rights, tracking/consent, and affiliate disclosure for intended regions.
- Apply `202609210001_legal_acceptance.sql` and
  `202609210002_legal_acceptance_evidence.sql` before distributing a build that
  requires legal acceptance. Verify Apple, Google, and email sign-in each writes
  an append-only `legal_acceptances` row with version `2026-09-21`, a
  server-generated timestamp, and the app version/build. Also verify the current
  accepted version is reflected on the authenticated user's profile. Keep the
  linked legal notice immediately beside the Continue actions and preserve the
  exact Terms version shown.
- Declare and verify EU Digital Services Act trader status/contact details if
  applicable. Test region-specific affiliate eligibility; the app must never
  imply a commission on an ineligible original link.
- Run signed TestFlight and real-iPhone checks for sign-in, Share Sheet,
  imports, private media, collaboration, claims, report/block, deletion,
  browser links, offline errors, accessibility, and app review navigation.
- Only after the above pass, select **All Countries or Regions** in App Store
  Connect. English is the initial UI language; add localizations where needed.
