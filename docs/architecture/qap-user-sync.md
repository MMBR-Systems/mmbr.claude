<!--
Last updated: 2026-04-28
Owner: hpeluzio
-->

# QAP user sync

How MMBR users are mirrored into the QAP `users` table, and why the sync runs in two places instead of one.

## Two systems, one identity

| System | Owns | Key |
|---|---|---|
| `mmbr.users` (web-platform Postgres) | Whitelist enforcement, role, plant assignments | `id` (UUID), `auth0Id` (text) |
| `qbrick.users` (ai-platform Postgres) | Conversation/message ownership inside QAP | `id` (UUID), `(provider, external_id)` unique |

Auth0 is the identity provider but holds no domain data. `mmbr.users.auth0Id` ↔ `qbrick.users.external_id` is the link, with `provider = "auth0"`.

QAP needs its own `users` row before any conversation can be inserted with a non-NULL `user_id` (see `known-issues/qap-user-id-silent-null.md`). Web-platform is responsible for creating that row.

## Two sync sites

Both call `syncUserWithAgent` in `lib/api/qbricks.ts`, which POSTs to QAP `/auth/login`. The QAP endpoint upserts on `(provider, external_id)`, so the call is idempotent.

### 1. First login — `provisionUser`

`lib/auth/user-provisioning.ts:18` runs when an Auth0-authenticated user has no `mmbr.users` row yet. After inserting into `mmbr.users` (whitelist-gated), it fires `syncUserWithAgent` so QAP gets the row at the same moment.

### 2. Every subsequent login — `ensureQapUserSynced`

`lib/auth/user-provisioning.ts:43` runs in the protected layout (`app/(protected)/layout.tsx:30`) on every authenticated request where the user already exists in `mmbr.users`. It re-fires `syncUserWithAgent` unconditionally.

## Why the every-login backfill exists

`provisionUser` alone is not sufficient because users can exist in `mmbr.users` *without* a corresponding `qbrick.users` row in two real scenarios:

1. **Deployment ordering.** web-platform was deployed and provisioning users before `qbrick` was reachable in dev. Those users have no QAP row and would never get one if sync only ran at first registration.
2. **QAP DB resets.** Wiping `qbrick`'s Postgres (`docker compose down -v`, environment rebuild) drops every QAP user. The `mmbr.users` rows survive, so without the backfill those users would 404 inside QAP forever.

Running the sync on every login closes both gaps without any reconciliation job. The cost is one extra HTTP call per request to the protected layout, which is acceptable because:

- The call is fire-and-forget — failures are logged, never thrown, and never block the layout render.
- QAP `/auth/login` is a single indexed upsert.

## Contract for both call sites

- **Non-blocking.** Both wrap `syncUserWithAgent(...).catch(...)`. A QAP outage must not break login or layout.
- **Idempotent.** Safe to call any number of times per session; QAP upserts on `(provider, external_id)`.
- **Identity payload is fixed:** `{ email, provider: "auth0", provider_user_id: auth0Id, name, avatar_url: null }`. Changing the shape requires a coordinated update in `ai-platform`.

## When this can be simplified

The every-login backfill becomes redundant once both are true:

1. Every existing `mmbr.users` row has a confirmed match in `qbrick.users` (one-time reconciliation).
2. QAP DB resets are no longer expected (i.e. dev/QA stop being rebuilt from scratch).

Until then, keep both call sites.
