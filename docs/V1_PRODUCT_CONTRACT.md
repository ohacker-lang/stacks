# Stacks V1 Product Contract

**Status:** Proposed defaults for implementation
**Owner:** Stacks team
**Last updated:** August 13, 2026

## Purpose

This document fixes the product rules that the iOS client, Supabase backend, and edge functions must share. A change to one of these rules should be recorded here before it changes the app's behavior.

## V1 Product Promise

Stacks lets people keep products, objects, and references as visual collections. A saved item should retain enough information to find, understand, edit, share, or buy it later. Saving should remain useful when product scraping or background removal is imperfect.

## Accounts

- Authentication methods: Sign in with Apple and email magic link.
- An account is required to create, save, pin, follow, collaborate, claim a gift, or share a personal Stack.
- A future read-only public Stack page may allow unauthenticated viewing, but V1 iOS browsing requires an account.
- Required profile fields: immutable user ID, display name, username, and created timestamp.
- Optional profile fields: avatar, bio, website, and discovery eligibility.
- Users can update their profile and initiate permanent account deletion from Settings.

## Stack Rules

### Visibility

- Default visibility: **private**.
- A Stack can be made `private`, `linkOnly`, or `public` by its owner.
- `private`: visible to the owner and approved collaborators only.
- `linkOnly`: viewable by anyone holding the unguessable share link; not indexed in Discover.
- `public`: eligible for Discover, search, following, pins, and public sharing.
- Owners can change visibility at any time. Making a Stack private immediately removes it from Discover and invalidates public index visibility.

### Ownership and actions

- Only the owner and collaborators with edit permission can change a Stack or its items.
- **Pinning is the single saved-Stack action in V1.** It replaces all user-facing uses of “bookmark” and “save Stack.”
- A user can pin any Stack they are allowed to view, including their own private Stacks and other users’ public or link-only Stacks.
- Pinned Stacks appear in the Home Pinned bundle. A pin never changes the Stack's owner or visibility.
- A viewer can copy a public or link-only Stack to their own account. The new Stack and copied items belong to the viewer; the copied Stack retains an attribution reference to the source Stack.
- V1 uses two collaborator roles: `editor` and `viewer`.

### Wishlist mode

- Wishlist mode is optional and can be used with any visibility level.
- Gift claims are private to the claimer and must not reveal the claimer or claim state to the Stack owner.
- A claimed item remains visible and purchasable to the Stack owner.

## Item Rules

- Every item has an owner, parent Stack, title, source type, original image reference, and placement data.
- Link-based items require a valid HTTP(S) source URL. The source URL is also the fallback buy URL.
- A photo or camera item may be saved without a link as an **Unidentified Find**.
- Unidentified Finds visibly invite the owner to add a source/buy link later; they remain usable Stack items.
- Editable fields: title, brand, description, price, currency, size, source URL, buy URL, image, and Stack placement.
- A title is required before an item is saved. Brand, description, price, size, and buy link are optional for Unidentified Finds.
- Item source types are `search`, `pastedLink`, `manualPhoto`, and `shareExtension`.

## Save and Review Contract

Every capture route ends in the same review experience.

1. Acquire a source: search result, pasted URL, shared URL, camera image, or photo-library image.
2. For URLs, resolve redirects and extract the best available product metadata and main product image.
3. Present the acquired image alone on a white canvas.
4. Start background removal immediately and show a vertical shimmer while it is running.
5. On success, reveal the transparent cutout and provide a medium haptic. On failure, preserve the original image and show a clear retry or continue option.
6. Fade into the editable item review screen with every scraped field prefilled and every missing field visibly editable.
7. The user chooses an existing Stack or creates a Stack, then explicitly saves.

### Failure behavior

- Scrape failures must never discard the URL. The user can enter fields manually and continue.
- Missing or blocked image URLs must offer image replacement, photo-library selection, or save without an image only when explicitly confirmed.
- Background-removal failures must not prevent saving.
- Import, upload, and save failures provide a retry action and preserve the draft locally until resolved or dismissed.

## Sharing and Discovery

- Public Stacks are eligible for Discover only when the profile has opted into discovery.
- Discover supports Stack-title search, username search, follows, pins, and copying.
- Users can block another user. Blocking hides both users' public content from each other and prevents collaboration.
- Every public Stack and profile has a report action. Reports are kept private and sent to an internal moderation queue.
- V1 does not use algorithmic ranking beyond recency, follows, simple relevance, and manually curated suggestions.

## Monetization

- V1 monetization is affiliate revenue on eligible Buy clicks only.
- A server-side affiliate wrapper may add network tracking only when a retailer is eligible. Otherwise the original buy URL opens unchanged.
- Stacks records click attribution without storing sensitive browsing content beyond the minimum needed for fraud prevention, reporting, and payout reconciliation.
- The product detail screen displays a clear, nearby disclosure when an affiliate link is used: `Stacks may earn a commission from purchases.`
- Creator revenue sharing, subscriptions, paid boosts, ads, and checkout are out of scope for V1.

## Privacy, Data, and Safety

- Original camera and photo assets are private unless the owner publishes a Stack containing the item.
- Public visibility only shares the resulting Stack/item content needed for viewing; it does not expose private gift claims, account email, or raw analytics.
- User data and stored media are permanently deleted when an account deletion request completes, except data the business must retain by law or strictly aggregated operational records.
- Product URLs, image retrieval, and affiliate wrapping occur through controlled backend services. Client apps never contain secret API keys.
- The app must provide a Privacy Policy, Terms of Service, Support contact, report flow, and account deletion control before App Store submission.

## Explicitly Out of Scope for V1

- In-app checkout, inventory alerts, automatic price history, or price guarantees.
- Feed-ranking systems, comments, direct messages, or creator payouts.
- General web editing and Android.
- Full multi-role collaboration history or conflict resolution.

## Decisions Needed Before Backend Work Begins

These defaults are ready to implement unless the product direction changes:

## Confirmed Founder Decisions

1. `private` is the default Stack visibility.
2. Linkless photo items are allowed as Unidentified Finds.
3. All public and link-only Stacks can be copied. V1 has no `copyAllowed` setting.
4. The support email and final Privacy Policy / Terms domains are **TBD**. They are a required launch deliverable.
5. The affiliate disclosure appears only next to commissionable Buy links.
