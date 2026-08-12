# Stacks Brand and UI Guidelines

## 1. The Idea

**Stacks is the calm, editorial home for things worth keeping.** It makes saving a product feel tactile and personal: an object lands on a clean white page, joins a collection, and becomes easy to share. The interface should feel closer to a great independent magazine or a beautifully arranged bedside table than a shopping feed.

### Brand traits

- **Editorial, not precious:** Bold type and considered composition, with no unnecessary decoration.
- **Tactile, not toy-like:** Product cutouts, believable shadow, gentle momentum, and crisp feedback.
- **Native, not generic:** Apple-standard interactions, SF Pro typography, clear hierarchy, and familiar sheets and menus.
- **Personal, not performative:** Collections reflect taste. The product is always the hero.

### Visual personas

Every screen should have one dominant persona. Do not mix all three at once.

| Persona | Job | Visual behavior |
| --- | --- | --- |
| **The Curator** | Viewing or sharing a Stack | White editorial page, oversized title, objects arranged with confidence, minimal chrome. |
| **The Saver** | Adding a product, link, or photo | Native controls, clear fields, one obvious next action, glass only when it clarifies layering. |
| **The Host** | Discovering people and saved Stacks | Human avatars, clean vertical rhythm, product previews, easy follow/save actions. |

## 2. Foundations

### Color

| Token | Value | Use |
| --- | --- | --- |
| `stacksInk` | `#111111` | Primary type, icons, black actions. |
| `stacksMutedInk` | `#74716C` | Secondary metadata and quiet actions. |
| `stacksDivider` | Black at 12% | Hairline dividers only. |
| `stacksSuccess` | `#4CC467` | Positive status only, never as a decorative accent. |
| Canvas | `#FFFFFF` | Default app, Stack, product, onboarding, and profile background. |

White is intentional. It gives cutout products room to breathe and makes a Stack feel like a shareable page. Do not introduce colored page backgrounds, gradients, or ambient decorative shapes. Color belongs in the objects people save.

### Typography

Use two families only.

| Role | Typeface | Weight | Size | Rules |
| --- | --- | --- | --- | --- |
| Stack masthead | SF Pro Display / system default | Black (900) | 36-112 pt | One line only. Dynamic fit. Tracking is `size x -0.065`; horizontal scale is `0.94`. |
| Screen header | SF Pro Display / system default | Semibold | 24-31 pt | Tight, direct, never a decorative headline. |
| Product title | SF Pro Display / system default | Bold | 36-54 pt | Large, focused, and used sparingly. |
| Section label | SF Pro Text / system default | Semibold | 17-20 pt | Clear scanning hierarchy. |
| Body and metadata | SF Pro Text / system default | Thin, Regular, or Medium | 14-18 pt | Prefer Regular; use Thin only for quiet supporting copy. |
| Button label | SF Pro Text / system default | Semibold | 17-18 pt | Sentence case. |
| Onboarding editorial line | Instrument Serif Regular | Regular | 46-52 pt | Centered and reserved for onboarding storytelling only. |

**Stack titles are a system, not a style suggestion.** Use `StackTitle(text:)` for every primary Stack page title. It measures the title and chooses the largest fitting size between 36 and 112 pt. Never manually alter a title’s casing, tracking, scale, or line count.

### Type rules

- Use sentence case: `Summer fits`, never forced uppercase.
- Keep tracking at `0` for normal SF Pro text. The only exception is the Stack masthead token above.
- Never use a serif for a functional label, product detail, button, navigation, or Stack description.
- Do not use SF Pro Rounded or custom display fonts outside Instrument Serif on onboarding.
- Prefer short copy. One strong phrase beats a paragraph of product language.

### Spacing and geometry

| Token | Value | Use |
| --- | --- | --- |
| Page edge | 16 pt | Default content alignment, especially Stack mastheads. |
| Standard inset | 24 pt | Forms, sheets, and grouped content. |
| Tight gap | 8 pt | Icon/label pairs and compact metadata. |
| Standard gap | 12-16 pt | Related controls and rows. |
| Section gap | 24-32 pt | Distinct content groups. |
| Large breathing room | 40-56 pt | Editorial moments only. |
| Divider | 1 px at `stacksDivider` | Separate content without making a card. |

Use stable dimensions for controls. Do not let labels change a button’s visual height or cause nearby content to jump.

## 3. Core Components

### Stack page

- A Stack is a **white editorial canvas**. It is not a grid of cards.
- Place the back control at the top-left and the owner action at the top-right. They must never overlap the title.
- Use the reusable `StackTitle` flush to the 16 pt content grid, near the top of the page.
- Put product cutouts immediately below the masthead. Avoid a large empty band between the title and products.
- Owners see a simple `+` for adding products. Visitors see an ellipsis menu for Share and Copy Stack.
- Do not show a Stack description in the current product experience. The title and objects are the story.

### Product cutouts

- Use a transparent, background-removed PNG whenever possible.
- Favor the main forward-facing product image on a white or simple original background before removal.
- Give cutouts a restrained soft shadow: black at roughly 10-14% opacity, 4-6 pt blur, with a small downward offset. A very soft white halo is permitted for edge separation.
- Preserve each item’s natural aspect ratio. Do not put products in circles, framed tiles, or colored boxes on Stack and product pages.
- Placement can be playful, but must preserve tap targets and avoid accidental overlap with navigation or controls.
- Processing state: use a vertical shimmer only while Apple Vision removal is active. Never shimmer completed demo or saved images.

### Buttons and controls

| Control | Specification |
| --- | --- |
| Primary action | Solid `#111111`, white SF Pro Semibold 17-18 pt, capsule, 54-60 pt high. |
| Secondary action | Clear liquid glass / `.ultraThinMaterial`, dark content, matching primary action height. |
| Circular action | 40-44 pt hit target minimum; familiar SF Symbol or supplied brand icon, never text in a circle. |
| Add action | Use `plus`; owner-only inside a Stack. |
| Overflow action | Use `ellipsis`; visitor-facing Stack actions belong in a native `Menu`. |
| Native lists/sheets | Use for create, add, share, copy, and settings paths. Let iOS provide selection and dismissal behavior. |

Do not create a second primary button that repeats an already-obvious action. For example, the plus opens creation; a redundant `Create Stack` button inside that flow is not needed.

### Glass

Liquid glass is for **floating interface**, not for decoration.

- Use the shared `stacksGlass(cornerRadius:interactive:)` helper.
- Use it for sticky navigation, auth sheets, bottom navigation, search, and secondary/floating controls.
- On iOS 26 it uses native `glassEffect`; on iOS 18-25 it falls back to `ultraThinMaterial`.
- Keep the surface transparent enough to show context, with a white 55-60% border only when the edge needs definition.
- Glass never replaces the white editorial Stack canvas or creates stacked cards within cards.
- Default radii: 24 pt for panels, 29-31 pt for pill actions, 34 pt for auth sheets, and half the control size for circles.

### Icons

- Prefer SF Symbols for system actions: plus, ellipsis, search, share, bookmark, camera, link, and chevron.
- Custom navigation icons must be supplied as a 24 x 24 pt vector asset with template rendering, a visually balanced filled silhouette, and no baked background.
- Match visible icon weight, not merely the artboard size. Icons in the same navigation bar should feel equally present.
- Give unfamiliar custom icons an accessibility label and a tooltip where applicable.

## 4. Screen Standards

### Onboarding

- Background is pure white; retain the real system status bar.
- The first hero uses Instrument Serif, centered, in two lines: `Save the things you love`.
- Use the fixed, locally bundled product cutout composition. It must work without the network or loading flicker.
- `Start stacking` is the only hero action. It opens a clean, rounded glass auth sheet with Apple and Email choices.
- The later explainer steps use centered Instrument Serif titles and cutout objects. They should be airy but never leave the next action stranded at the bottom of an otherwise empty screen.
- Motion is a reward, not an obstacle: the post-auth product burst may use physics and device tilt, but it must have a graceful Simulator/no-motion fallback and respect Reduce Motion.

### Stacks home

- The page is a personal library, not a dashboard. Avoid descriptive marketing copy.
- Header controls remain sticky while content scrolls. At rest, the top bar is visually transparent; add only a subtle frosted blur and divider after content passes beneath it.
- Stack names in list rows use thin/regular SF Pro rather than masthead weight.
- Keep the create action compact and distinct from the profile/avatar control.

### Discover

- Purpose: find people and their taste, not an opaque recommendation algorithm.
- Keep the header uncluttered; search belongs at the top-right.
- Use a simple vertical Saved view with complete product previews. Do not show item-processing shimmer here.
- Follow and bookmark are direct, reversible, haptic actions.

### Product detail

- Pure white background.
- Product floats as a cutout; no circular image container.
- Lead with a large product title, then essential brand/price information.
- Buy is a glass action with the price when known and opens the stored affiliate or source link.

## 5. Motion, Haptics, and Accessibility

### Motion

- Transitions: 180-280 ms, ease out or spring with low bounce.
- Object launch/physics: lively on entry, then settles. Never continuously distract from reading or actions.
- Use physical constraints: objects can meet an edge but should not visibly clip through it.
- Respect `accessibilityReduceMotion`: show the final arrangement without the launch or physics simulation.

### Haptics

- Light impact: open a stack, save/bookmark, simple tab selection.
- Medium impact: add an item, create a Stack, claim a gift.
- No haptics for passive scrolling, image loading, or every small state change.

### Accessibility

- Minimum interactive target: 44 x 44 pt.
- Preserve dynamic type for all body and controls. Mastheads may shrink to fit but never clip.
- Give cutouts meaningful accessibility labels from the product title.
- Do not convey state through color alone; selected sections also need weight, icon, or structure.
- Check text contrast over all material surfaces.

## 6. Quality Bar

Before shipping a screen, ask:

1. Does it clearly belong to one visual persona?
2. Is the white canvas still doing most of the work?
3. Is the product or Stack title the strongest visual signal?
4. Could a card, label, subtitle, or button be removed?
5. Are SF Pro weights intentional: Thin/Regular for quiet text, Semibold for hierarchy, Black only for Stack mastheads?
6. Is glass limited to floating interface layers?
7. Does the screen feel natural on a small iPhone, a large iPhone, and with Reduce Motion enabled?

## 7. Implementation Source of Truth

Use these existing code tokens rather than re-creating variations in individual views:

- `Stacks/Extensions/Color+Stacks.swift`
- `Stacks/Extensions/Font+Stacks.swift`
- `Stacks/Extensions/View+Glass.swift`
- `Stacks/Views/Components/PrimaryButton.swift`
- `Stacks/Views/Components/GlassCircleButton.swift`

Any new design token should be added to one of these shared files first, then used by the view. This keeps the product quietly consistent as the app grows.
