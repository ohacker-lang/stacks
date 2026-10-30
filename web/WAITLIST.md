# Website waitlist

> **Notion is the source of truth.** The current, corrected version of this document lives in Notion: [Waitlist](https://app.notion.com/p/40858338d845814aa2bac067082f9536). This file is the original import and may be out of date (for example, new Stacks are now public by default, sign-in includes Google, Stacks Pro is paused and price alerts are in scope). Update Notion first.

The public `/waitlist` page saves signups in Supabase `public.waitlist_entries`.
Open the project's **Table Editor → waitlist_entries** and sort by `created_at`
to track signups in order. The table contains the requested `username`, `email`,
and signup timestamp; it is not publicly readable. `/download` redirects to
the waitlist until an App Store listing exists.

The reservation function checks both the waitlist and app `profiles` usernames.
A profile trigger prevents app accounts from taking a reserved name, except
when the account has a verified email matching the reservation. The website
checks availability first, then saves the email and username atomically.

Important: website emails are **not yet verified**. `confirmed_at` stays null.
Before treating these as confirmed accounts or sending launch mail at scale,
configure a production email sender for Supabase Auth and add an email
confirmation/reconciliation flow. Cloudflare Email Routing only forwards
incoming mail to support; it is not an outbound sender. Do not export the
waitlist publicly or send unrelated marketing without separate consent.
