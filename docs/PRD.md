# Stacks Product Requirements Document

**Status:** Draft for review  
**Product:** Stacks  
**Platform:** iOS 18+  
**Version:** V1  
**Last updated:** July 28, 2026

## 1. Product Summary

Stacks is a visual wishlist and curation app for people who save products, objects, and references across the web. Instead of collecting links in notes, browser tabs, or screenshots, people save an item into a visual **Stack**: a white editorial canvas of clean, background-removed product cutouts. Every item retains its source and purchase link, so a Stack is both a personal collection and a shareable way to express taste.

The product begins as a personal utility: save an object from a link, a search result, or a photo. It becomes social when people share a Stack with a friend or discover the collections of people they follow. Wishlist Stacks add an optional gift-claiming layer without exposing who has claimed an item to the Stack owner.

## 2. Problem

People find products constantly, but their saving tools are fragmented:

- Browser bookmarks are functional but not visual or expressive.
- Screenshots lose the link, price, and product context.
- Notes and messages are difficult to browse and share.
- Existing moodboards are often image-first and do not preserve a useful buying path.
- Gift lists are transactional rather than personal or beautiful.

Stacks makes the saved object the center of the experience: a product is easy to save, visually satisfying to revisit, and ready to buy or share later.

## 3. Goals

### Primary goals

1. Let a user save a product from a URL, a search, a camera capture, a photo, or the iOS Share Sheet in under one minute.
2. Convert saved product imagery into a clean transparent cutout whenever possible.
3. Let users organize products into highly visual Stacks with a clear title and optional editorial description.
4. Preserve a reliable source/buy link for every saved product.
5. Make a Stack attractive enough to share as a personal collection or wishlist.
6. Establish a simple social loop: discover creators, follow them, and bookmark their Stacks.

### Product principles

- **Visual first, link-backed:** the product should feel like a visual collection without losing commerce utility.
- **Fast capture:** saving should not require filling out a long form before a product is safe.
- **Editorial, not cluttered:** Stacks should feel closer to a printed gift guide than a dashboard.
- **Native by default:** use Apple-native interaction patterns for navigation, sheets, sharing, feedback, and accessibility.
- **Trustworthy data:** users must be able to edit scraped title, image, price, brand, description, and link before saving.
- **Private when needed:** personal Stacks and wishlists should not be public by default.

## 4. Non-Goals for V1

- A fully automated recommendation algorithm or feed ranking system.
- Marketplace checkout inside Stacks.
- Guaranteed product availability, inventory, or price monitoring.
- Full collaborative editing history, comments, or role management beyond basic invitations.
- Creator analytics, paid subscriptions, or advertising tools.
- Universal background-removal quality for every photograph, especially complex scenes or multiple objects.
- Android, web editing, or a public web profile editor. A read-only shared web view may be added later.

## 5. Target Users

### The collector

Saves clothing, home objects, travel finds, books, and niche products. They need a better place than browser tabs to keep ideas until they are ready to buy.

### The gift giver / recipient

Builds a wishlist for birthdays, holidays, and major life moments. They need to share a list while allowing friends to claim gifts privately.

### The taste-led creator

Shares visual edits such as “Summer,” “Apartment Objects,” or “Gifts Under $100.” They need a compact link-in-bio destination that can turn personal taste into useful product discovery.

## 6. Core Concepts

### Stack

A named collection of products. A Stack has:

- Title (required)
- Short editorial description (optional)
- Owner and visibility
- Optional wishlist mode
- Ordered product items
- Optional collaborators in later V1 work

The Stack detail screen is a pure-white editorial canvas. It has a large SF Pro Display-style title, a centered Instrument Serif description, a back control, and an owner-only add control. Products appear as background-removed cutouts in an intentional, scrollable four-column composition.

### Stack Item

A saved product or object. Every item stores:

- Title and brand
- Short description
- Price and currency when known
- Source URL and buy URL
- Affiliate URL when available
- Original image and removed-background image
- Background-removal state
- Source type: search, pasted link, photo/manual
- Placement metadata for future freeform layouts

### Wishlist Mode

An optional Stack setting. A wishlist can be shared privately or publicly. Recipients can claim an item through a private claim flow; the Stack owner must not see which items have been claimed.

### Saved / Bookmarked Stack

A Stack created by another person that a user saves for later. Saved Stacks appear in a clean vertical scrolling view and in the profile's Bookmarked section.

## 7. V1 User Experience

### 7.1 Authentication and onboarding

**Entry:** A new user sees a white, editorial onboarding hero with real product cutouts and the headline, “Save the things you love.”

**Primary action:** `Start stacking` opens an Apple-native authentication sheet with Continue with Apple and Continue with Email.

**After authentication:**

1. Explain the three capture methods: photo, pasted link, and Share Sheet.
2. Explain that saved items become visual Stacks.
3. Explain sharing and Discover.
4. Prompt the user to create their first Stack, add an item, and optionally share it.
5. Offer a persistent Skip action so onboarding never blocks app access.

**Success criteria:** A user can reach the Stacks tab without completing first-Stack setup.

### 7.2 Stacks home

**Purpose:** The personal library.

**Navigation:** This is the first tab, labelled `Stacks`. The bottom navigation is native Liquid Glass on supported systems and contains only `Stacks` and `Discover`.

**Header:**

- No large page title on the left.
- Profile avatar opens Profile.
- Compact plus button opens a native sheet with `New Stack` and `Paste Product Link`.

**Content:**

- `Your Stacks` and `Bookmarked` selector.
- Rows display the Stack title, a four-item product strip, and a chevron.
- Empty states clearly direct users to create or save a Stack.

**Create Stack:** A native sheet asks for a title and lets the user toggle Wishlist mode. Creation is confirmed from the sheet toolbar; there is no redundant in-list action button.

### 7.3 Add an item

Users may add an item through three in-app paths, plus the iOS Share Sheet. The primary visual capture path is **Stack Scout**, a camera-first experience that makes noticing and keeping an object feel immediate and satisfying.

#### A. Search

1. User searches by product name.
2. Results show product title, image, brand, price, and source.
3. User selects a result, reviews editable fields, chooses an existing or new Stack, and saves.

#### B. Paste link

1. User pastes a product URL.
2. Stacks fetches the page and extracts structured product fields, Open Graph metadata, and the best available forward-facing, studio-style product image.
3. Stacks favors a main product image with a white or uncluttered background when selecting among images.
4. The user reviews and edits title, brand, description, price, image, and source/buy link.
5. The user chooses an existing Stack or creates a new Stack before saving.

#### C. Stack Scout: camera/manual entry

**Intent:** Turn seeing an object in the world into a capture moment, not a data-entry task. The camera interaction may feel playful and rewarding, but must remain calm, useful, and native to Stacks rather than becoming a separate game.

1. The plus menu presents `Scan a find` as the first, visually prioritized option, followed by `Paste a link` and `Search`.
2. `Scan a find` opens a full-screen live camera viewfinder with a restrained center reticle and the prompt `Spot an object`.
3. When the user frames a likely object, the app may provide a light haptic and a subtle white contour or focus treatment. Object detection is assistive only; it must never prevent the shutter from working.
4. User taps the shutter to capture. The captured object freezes briefly, then appears to lift away from the photo as background removal begins.
5. While removal is running, use the existing vertical shimmer over the pending item. Once complete, display the transparent cutout on a clean white review canvas.
6. User chooses `Add to existing Stack` or `Start a Stack` before finishing capture.
7. The review flow asks for a title and optionally a source/buy link, brand, price, and description.
8. If the user does not know the link yet, they may save the item as an **Unidentified Find**. It remains a usable visual Stack item but is visibly marked as needing a link; the user can complete product details later.
9. Saving gives a medium haptic and an animation of the new cutout settling into its Stack.

**Stack Scout UI requirements:**

- Camera must request permission in context, with a clear photo-library import fallback.
- The viewfinder is edge-to-edge and uses system camera controls where possible.
- Camera, import, shutter, review, and cancel controls must be reachable one-handed on compact iPhones.
- The capture screen must work when no object is detected. Detection is a delight, not a dependency.
- The camera image itself is private and stored only as needed to create the original/removed product image.
- An imported photo follows the same review and background-removal flow as a camera capture.
- The experience must remain accessible: VoiceOver labels describe the shutter, reticle state, captured item, and removal progress; haptics are supplemental rather than the only feedback.

#### D. Share Extension

1. In Safari or another app, the user selects Share > Stacks.
2. The extension stores the shared URL as a pending import in the shared App Group container.
3. Stacks opens to the import review flow.
4. The user verifies/edit fields and selects a Stack before saving.

**Required validation:** Link-based imports require a valid HTTP(S) source/buy link. Stack Scout items may be saved without a link only as an `Unidentified Find`; a visible completion state prompts the owner to add a source/buy link later. If scraping fails, the user may complete the item manually rather than losing it.

### 7.4 Capture motivation and collection milestones

Stacks uses lightweight progress and celebration to make collecting feel rewarding without encouraging compulsive behavior or cluttering the product with badges.

**Requirements:**

- Profile may show a quiet `Finds this week` count based on newly captured or saved items.
- The first successful camera save, first completed Stack, first shared Stack, and first completed Unidentified Find may each trigger a one-time acknowledgement.
- Acknowledgements are brief, visual, and dismiss automatically. They must not interrupt an active capture flow or require users to share externally.
- Eligible copy includes short moments such as `You found something worth keeping.` No points, leaderboards, streak penalties, countdowns, or artificial scarcity are part of V1.
- Milestone state is private by default and never shown to followers unless a future social feature explicitly adds that choice.

### 7.5 Background removal

1. Every newly added image begins in a queued or processing state.
2. The product sticker shows a vertical shimmer while processing.
3. On a device, Stacks uses Apple Vision foreground-instance masking and composites the detected object to a transparent PNG.
4. If Vision cannot isolate an object, the app falls back to a white-background transparency pass where appropriate; otherwise it preserves the original image and marks removal as failed.
5. The user can still save and open the product if removal fails.

**Quality bar:** The UI must never show a processing shimmer for a completed item. Product images without a successful removal should be clearly distinguishable during review, rather than appearing as broken or empty content.

### 7.6 Stack detail

**Purpose:** The editorial, shareable representation of a collection.

**Layout requirements:**

- Pure white, uninterrupted canvas.
- No persistent bottom tab bar while viewing a Stack.
- Back control in the upper-left.
- Owner-only compact plus control for adding an item.
- Stack title is one line, ultra-heavy SF Pro Display style, as large as available width permits.
- Description is centered Instrument Serif Regular, constrained to a two-line editorial measure.
- Items use the Stack's actual product data and image URLs; demo fixtures use bundled transparent product assets only for offline preview.
- Products appear in a balanced four-column editorial composition with subtle shadow/halo, not raw photo rectangles or a masonry-card UI.
- Tapping any product opens Product Detail.

### 7.7 Product detail

**Purpose:** Make a product actionable without losing the calm visual presentation.

**Requirements:**

- Pure white background.
- Large floating product cutout, no circular image container.
- Large product title, brand, and price.
- Instrument Serif Italic short description.
- Translucent Liquid Glass detail treatment where supported, with material fallback on iOS 18–25.
- Prominent Buy action that opens the affiliate URL when present, otherwise the buy URL.
- Clear fallback for missing price or image.

### 7.8 Discover

**Purpose:** The social and inspiration side of Stacks.

**Requirements:**

- Second tab labelled `Discover`.
- Search icon opens a username and Stack-title search field.
- Browse recent Stacks, saved Stacks, and suggested creators.
- Follow/unfollow creators.
- Bookmark/unbookmark Stacks.
- Saved Stacks use a legible vertical scroll rather than a dense horizontal collage.
- Demo/seed content must not remain in a processing shimmer state.

### 7.9 Profile

**Purpose:** A user's personal public-facing library.

**Requirements:**

- Accessed from the avatar on Stacks home, rather than a dedicated tab.
- White editorial profile layout with avatar, name, Stack count, follower count, and bookmark count.
- Switcher for `Your Stacks` and `Bookmarked`.
- Each Stack row previews its first four product cutouts and opens Stack detail.
- Settings entry point is visible.

## 8. Data and Service Requirements

The app must remain usable with mock services during development. Production services are behind protocols so implementation can be swapped without changing views.

| Capability | V1 implementation target |
| --- | --- |
| Auth | Supabase Auth / Sign in with Apple / email |
| Data and realtime | Supabase Postgres, Storage, Realtime |
| Product scraping | Supabase Edge Function or equivalent server-side worker |
| Product search | Edge function wrapping a search provider |
| Background removal | Apple Vision on device; server fallback optional later |
| Affiliate wrapping | Edge function wrapping the affiliate provider |
| Sharing | iOS Share Extension and universal/deep links |
| Web previews | Read-only Stack URL in a later V1 increment |

No affiliate or product-search secret belongs in the app bundle.

## 9. Monetization

The initial monetization path is affiliate revenue. When a user presses Buy, Stacks routes the purchase URL through an affiliate wrapper where a supported merchant relationship exists. The product must never degrade an item’s destination just to force an affiliate link.

Potential post-V1 revenue paths:

- Creator storefront or link-in-bio upgrades.
- Brand/creator affiliate tooling.
- Premium private collaboration or advanced collection organization.
- Sponsored placements that are visually and clearly labeled.

V1 does not require paid subscriptions, in-app checkout, or advertising.

## 10. Success Metrics

### Activation

- Authentication completion rate.
- Percentage of new users who create a first Stack.
- Percentage of new users who add a first item.
- Time from first launch to first saved item.

### Engagement

- Stacks created per active user.
- Items saved per active user.
- Stack Scout captures per active user.
- Percentage of Stack Scout captures saved as a completed linked product versus an Unidentified Find.
- Share Sheet imports per active user.
- Product-detail open rate and Buy-link click-through rate.
- Stack share rate.

### Social

- Follow and bookmark conversion rate in Discover.
- Return rate after saving another creator’s Stack.
- Shared Stack views and repeat visits.

### Quality

- Background-removal success rate.
- Metadata extraction success rate for pasted links.
- Percentage of imports edited before save.
- Import failure rate and manual-completion rate.

## 11. Launch Criteria

V1 is ready for a controlled beta when:

1. Apple and email sign-in work with production configuration.
2. A user can create, edit, and view a Stack.
3. A user can save an item from search, pasted link, Stack Scout camera capture, photo import, and the Share Extension.
4. All added products retain a valid source/buy link.
5. Background removal is functional on supported physical devices and fails gracefully.
6. Stack detail matches the approved white editorial canvas direction on compact and large iPhones.
7. Product detail opens and Buy reliably routes to the stored purchase URL.
8. Discover supports search, follow, bookmark, and opening a Stack.
9. Profile displays the user’s Stacks and bookmarked Stacks.
10. No critical crash, broken navigation, duplicate sheet, blocked onboarding, or persistent loading state remains.

## 12. Risks and Decisions Needed

### Open decisions

- Is every Stack private by default, or should public sharing be suggested at creation time?
- Should a user be able to add an item without any link during capture, then be prompted to complete it later? The current V1 recommendation is no: preserve the link requirement, but allow a draft if user research shows capture friction.
- Should public Stack web previews be part of beta, or follow the native-app beta?
- Which affiliate provider and merchant coverage should define the first supported Buy integration?
- Will creator accounts have a different profile capability set from personal accounts in V1?

### Product risks

- Product pages vary widely; scraping must be treated as a helpful draft, not a guaranteed source of truth.
- Vision removal quality depends on image composition. Product review/edit is required.
- The shared visual direction depends on quality cutout imagery; poor source photography will lower the perceived quality of a Stack.
- Social content will be sparse before enough users create public Stacks, so early Discover needs intentional seed content and creator onboarding.

## 13. Phased Delivery

### Phase 1: Private alpha

- Mock-to-production auth and Stack persistence.
- Create Stack, add from link/manual photo, Apple Vision removal, Stack detail, Product detail.
- Internal seed content and direct Stack sharing.

### Phase 2: Capture and social beta

- Product search and Share Extension.
- Discover search, follow, bookmarks, profile.
- Read-only public Stack preview.

### Phase 3: Commerce and collaboration

- Affiliate URL wrapping and click reporting.
- Private wishlist claims.
- Basic collaborator invitations and realtime updates.

## 14. Acceptance Checklist

- [ ] A new user can reach the app after Apple or email authentication.
- [ ] Every onboarding screen is legible on compact and large iPhones.
- [ ] A user can create a normal Stack and a wishlist Stack.
- [ ] A user can add a linked product through search, pasted link, Stack Scout, photo import, and the Share Extension.
- [ ] A user can save an Unidentified Find during Stack Scout and complete its source link later.
- [ ] Stack Scout gives clear visual progress and optional haptic feedback without blocking capture when object detection is unavailable.
- [ ] A user can correct imported title, brand, price, image, description, and link before saving.
- [ ] Each item opens a Product detail screen with a working Buy action.
- [ ] A Stack detail canvas contains no persistent bottom navigation and no raw rectangular demo images.
- [ ] Active removal shows shimmer; completed removal does not.
- [ ] Discover search, following, and bookmarking have working loading and empty states.
- [ ] Profile accurately separates owned and bookmarked Stacks.
- [ ] The app builds and launches on an iOS 18+ simulator and is verified on a physical device for Vision removal.
