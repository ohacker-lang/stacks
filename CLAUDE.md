# Stacks

SwiftUI iPhone app (plus Share Sheet extension), Supabase backend, and the
stacks.spot website (Cloudflare Worker in `web/`). Product and engineering
tracking lives in Notion.

## Notion is the source of truth for work

Workspace: **Stacks HQ** — https://app.notion.com/p/40858338d8458175ba30c2eb91d7f2ad
(Backlog, Roadmap & Features, Releases, Sprints, Decision Log, Engineering Docs).
Follow its "How We Work" page. In short:

1. Only pick up Backlog stories with **Status = Ready**, **Assignee = Claude**
   and acceptance criteria filled in, highest priority first.
2. Move the story to **In progress** when starting. Branch name starts with the
   story ID, e.g. `stk-12-share-sheet-fix`.
3. When the PR is open: paste it into **PR link** and move the story to
   **In review**. Never move a story to Done (Neeha does that after merging).
4. If something is unclear or out of scope, comment on the story and stop.
5. Work that wasn't a story yet (bugs found along the way, follow-ups): add a
   Backlog story with Status = Backlog so Neeha can triage. Every story needs
   a **User story** ("As a [type of user], I want [goal], so that [benefit].",
   written for whoever benefits: shopper, friend, App Store visitor, reviewer
   or the team) and testable **Acceptance criteria**.
6. Record product or architecture decisions in **Decision Log**, and update
   **Engineering Docs → Architecture** when schema, environments or setup change.
7. Keep Notion current as you go — whenever a PR is opened or a story's state
   changes, update it in the same turn rather than at the end.

## Never commit secrets

Keys live in Supabase secrets, Cloudflare secrets or the password manager.
Public client values that are fine in the repo: Supabase URL and publishable
key, PostHog `phc_` key, Apple team ID.

## Quick facts

- Apple team `24H7V96T4Q`; bundle IDs `spot.stacks.app` / `spot.stacks.app.share`;
  app group `group.spot.stacks.app`. The app is light-mode only.
- Supabase project `whyufyttlvpiwlunosjm`. Schema in `supabase/migrations`,
  functions in `supabase/functions`.
- App settings come from `INFOPLIST_KEY_STACKS_*` build settings and reach the
  app only through `Stacks/Info.plist` (Xcode drops unknown generated keys).
- Analytics events are defined in `docs/ANALYTICS.md`; add new events there first.
- Stacks Pro is paused (`StacksPro.isEnabled = false`).

## Build and test

```bash
xcodebuild -project Stacks.xcodeproj -scheme Stacks -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build/DerivedData build CODE_SIGNING_ALLOWED=NO
```

- Offline demo account: launch the app with environment variable
  `STACKS_PRO_LOCAL_STOREKIT=1` (Debug builds).
- Unit tests: same command with `test` instead of `build`.
- Website tests: `cd web && npm test`.
