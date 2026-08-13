# Supabase Security Runbook

This is the operating contract for Stacks data in development, staging, and
production. Apply it before allowing real users to share Stacks.

## Access Rules

| Resource | Private | Link-only | Public |
| --- | --- | --- | --- |
| Stack and item rows | Owner and accepted collaborators | Opaque-token RPC only | Authenticated viewers, except blocked pairs |
| Discover | Never | Never | Only if owner has enabled discovery |
| Pins | The pinning user only | Token-backed app flow | Authorized viewer only |
| Editing | Owner or accepted editor | Owner or accepted editor | Owner or accepted editor |
| Gift claims | Claimer only | Eligible non-owner via token RPC | Eligible non-owner viewer |
| Media bytes | Short-lived edge-function signed URL | Token-backed signed URL | Short-lived edge-function signed URL |

`stack-media` must remain a **private** bucket. Mobile clients store Storage
paths, never public URLs. Never toggle it public, add a broad Storage SELECT
policy, or put a service-role key in Xcode.

The unauthenticated `web-preview` function is the only public sharing surface.
It accepts a public Stack ID or a link-only Stack ID plus its opaque token,
returns a read-only allowlist of Stack/item fields, and creates five-minute
media URLs itself. It never returns collaborator data, gift claims, imports,
analytics, or share tokens.

## Media Path Contract

All Stack media uses this exact path:

```
<stack-owner-id>/<stack-id>/<item-id>/<variant>.<extension>
```

Direct client uploads are limited to the signed-in user root. Collaborators use
`create-upload-url`, which verifies editor access then grants a signed upload
to the Stack owner namespace. `media-url` validates both Stack access and this
path before returning a URL valid for 60 to 600 seconds. It signs only paths
referenced by a visible `stack_items` record, never stray draft files.

## Copying a Stack

Public and link-only Stacks are always copyable. `copy-public-stack` verifies
access, creates a private destination owned by the copier, records
`copied_from_stack_id`, copies the actual media bytes into the copier’s own
namespace, and clears affiliate URLs. Never implement copying as a client-side
row clone: reusing another owner’s Storage path leaks access and breaks copies.

## Local Development

`supabase/seed.sql` is local demo data only. Use it with:

```bash
supabase db reset
```

It creates two deterministic Auth-backed fixtures only because `profiles` is
foreign-keyed to `auth.users`; treat them as database fixtures, not as a
production login flow. Do not run this seed in staging or production;
`supabase db push` does not apply seed files.

Run the database RLS smoke check after a reset:

```bash
psql "$LOCAL_DB_URL" -f supabase/tests/rls_access.sql
```

Before promotion, verify with two non-admin test accounts that private Stack
rows and media remain unavailable to non-collaborators, editors cannot publish
or rotate a share token, link-only media only works with a valid token, blocked
users lose direct access, and copied Stacks still render after their source is
made private.

## Deployment Checklist

1. Run `supabase db lint` and local RLS checks.
2. Apply migrations to development with `supabase db push`.
3. Add `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and
   `SUPABASE_SERVICE_ROLE_KEY` only as Edge Function secrets.
4. Deploy `media-url`, `create-upload-url`, and `copy-public-stack` with JWT
   verification enabled.
5. Confirm `stack-media` is private in the dashboard.
6. Repeat tests in staging with normal accounts, then deploy production.
