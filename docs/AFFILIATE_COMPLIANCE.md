# Affiliate commerce compliance for Stacks

> **Notion is the source of truth.** The current, corrected version of this document lives in Notion: [Launch & Compliance](https://app.notion.com/p/40858338d845819b8ae3daadd5fc2602). This file is the original import and may be out of date (for example, new Stacks are now public by default, sign-in includes Google, Stacks Pro is paused and price alerts are in scope). Update Notion first.

This is an implementation and release-control document, not legal advice. Have
qualified counsel confirm the final policy, operator details, and launch
regions before release.

## Product design that must remain true

- Stacks links to physical products purchased and consumed outside the app.
  Those purchases happen with an independent retailer, not through Apple In-App
  Purchase.
- A link is treated as commissionable only after the server confirms an eligible
  affiliate destination for the visitor's region. Any error, unsupported region,
  missing configuration, or ineligible retailer falls back to the original URL.
- Immediately before every confirmed commissionable Buy action, show this
  disclosure in readable text:

  > Ad · If you buy through this link, Stacks earns a commission. Your price is unchanged.

- Do not rely on “affiliate link,” a policy-page link, an icon, or a disclosure
  shown after the click. The explanation must be visible with the call to action
  before the user decides to visit the retailer.
- Keep the full Affiliate Disclosure accessible from the product screen, Profile
  settings, and every public web viewer footer.
- Do not claim that Stacks earns a commission beside an original or unconfirmed
  link. Do not imply retailer endorsement, guaranteed availability, or a price
  advantage.

## Current data-flow decision

The app currently sends the destination URL and two-letter country code to the
Stacks server-side affiliate resolver. The resolver does not receive the user's
Stacks account ID, name, email, advertising identifier, or device identifier.
There is no affiliate advertising SDK in the app. On that implementation,
Stacks does not use this feature to track a user across other companies' apps
or websites.

Reassess App Tracking Transparency, the privacy manifest, consent flows, and
App Store Connect privacy answers before adding any affiliate/ad SDK, click
identifier tied to a user or device, cross-company profiling, data-broker
sharing, or targeted-ad measurement. Do not ship such a change on the basis of
this document.

## Where disclosures and policies appear

| Surface | Required treatment |
| --- | --- |
| Product detail in the app | Plain-language `Ad` disclosure directly before a confirmed commissionable Buy button, plus an Affiliate Disclosure link |
| Public Stack browser viewer | If browser affiliate monetization is later enabled, show the same disclosure before each qualifying retailer link and use `rel="sponsored noopener noreferrer"` |
| Profile settings | Links to Privacy Policy, Privacy Choices, Terms, and Affiliate Disclosure |
| Public site footer and legal navigation | Links to Privacy Policy, Privacy Choices, Terms, Affiliate Disclosure, Security, and Support |
| App Store Connect | Public Privacy Policy URL; Support URL; accurate App Privacy answers; affiliate behavior explained in Review Notes |
| Promotional or creator content | Any person with a material brand/seller relationship must make an additional clear, prominent disclosure in that content |

## App Review notes

Use accurate wording similar to this after production verification:

> Stacks helps users save and share links to physical products. Purchases are
> completed on independent retailers' websites and are not digital content or
> app functionality. The app's server checks whether a product link is eligible
> for affiliate attribution in the user's region. When—and only when—a link is
> confirmed commissionable, the product screen displays “Ad · If you buy
> through this link, Stacks earns a commission. Your price is unchanged.” before
> the Buy button. Unsupported and unresolved destinations use the original
> retailer link without a commission claim. The full Affiliate Disclosure and
> Privacy Policy are available in Profile > Settings.

Give App Review a working account and exact navigation steps. Test that the
policy URL is public without sign-in and returns HTTP 200 before submitting.

## Release checks by region

For the United States, ensure the material connection is clear and conspicuous
and close to the recommendation/link. For the UK, make affiliate content
obviously identifiable as advertising before engagement; do not rely on
“affiliate” alone or a generic site-wide statement. For the EU, treat affiliate
marketing as advertising and keep disclosures prominent; separately assess
privacy consent, consumer, platform, and trader-information obligations. Apply
the conservative in-product disclosure globally rather than creating a weaker
experience elsewhere.

For each enabled affiliate country, test an eligible retailer, an ineligible
retailer, a resolver failure, and regional fallback. Record screenshots and the
resolved destination. Only list country codes in `SOVRN_ENABLED_COUNTRIES` after
that validation.

## Authoritative references

- [Apple App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/uk/)
- [Apple: User privacy and data use](https://developer.apple.com/app-store/user-privacy-and-data-use/)
- [Apple: Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy)
- [FTC Endorsement Guides FAQ](https://www.ftc.gov/business-guidance/resources/ftcs-endorsement-guides-what-people-are-asking)
- [European Commission Influencer Legal Hub](https://commission.europa.eu/topics/consumers/consumer-rights-and-complaints/influencer-legal-hub_en)
- [UK ASA: Affiliate marketing](https://www.asa.org.uk/advice-online/affiliate-marketing.html)
- [UK CMA: Social media endorsements](https://www.gov.uk/government/publications/social-media-endorsements-guidance-for-content-creators)

