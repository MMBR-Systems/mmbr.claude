---
created: 2026-05-01
updated: 2026-05-01
owner: hpeluzio
---

# `web-platform` env vars live inside a `SECRETS` JSON, not as individual env vars

## Symptom

Routes return `INTERNAL_ERROR` in QA / prod even after the relevant key is added to the env's secret in Secrets Manager. Stack trace points at code reading `process.env.X` directly, where `X` is something like `AUTH0_ISSUER_BASE_URL`, `AUTH0_CLIENT_ID`, `QAP_JWT_SECRET`, `QAP_AGENT_ID`, etc.

Concrete signatures observed:

- `TypeError: fetch failed` from `https://undefined/oauth/token` (the `domain` template literal interpolated `undefined`)
- `Error: QAP_JWT_SECRET is required. Add it to your .env.local.` (custom message)
- `Error: Missing required environment variable: QAP_AGENT_ID` (after switching to `requireEnv`, the canonical message)

Local dev does not reproduce — `.env.local` exposes the keys as normal `process.env.X`.

## Where

- ECS task definitions for `web-platform-{env}` inject the entire `mmbr-{env}-web-platform` JSON into a single env var named `SECRETS`. Individual keys are not mapped via `valueFrom` (compare with `QAP_*` keys, which were mapped per-key in earlier task def revisions).
- Helper that hides the JSON: `web-platform/lib/runtime-env.ts`. It reads `process.env[name]` first, falls back to parsing `process.env.SECRETS` and looking the key up there.
  - `getRuntimeEnv(name, fallback?)` — returns `string | undefined`
  - `requireEnv(name)` — same but throws `"Missing required environment variable: ..."` on miss
  - `getAuth0Domain()`, `getDatabaseUrl()`, `getQbrickBaseUrl()` — convenience wrappers
- Code paths that historically bypassed the helper and read `process.env.X` directly, all surfaced as production bugs and were fixed in PRs #36 and #38:
  - `app/api/auth/signup/route.ts` (Auth0 ROPG)
  - `app/api/auth/login/route.ts` (Auth0 ROPG)
  - `app/api/auth/forgot-password/route.ts`
  - `app/api/users/me/password/route.ts`
  - `lib/api/auth0-management.ts` (Management API token)
  - `proxy.ts` (Bearer token JWKS lookup)
  - `lib/api/qbricks.ts` (`requireQapSecret`, `requireQapAgentId`)

## Cause

The IaC convention chose a single `SECRETS` env var injected as a JSON blob, instead of mapping each key individually in the task definition's `secrets` array. Trade-off: adding a new key in Secrets Manager is zero infra work (no task-def change), but every code path reading the key has to go through `runtime-env`. There is no compile-time check that catches a missed call site; `process.env.X` returns `undefined` silently in deployed envs and works in local dev. The bug is only visible when the failing route is exercised in QA or prod.

The auto-redirect to `https://undefined/...` is the most user-visible flavor: `domain = process.env.AUTH0_ISSUER_BASE_URL?.replace("https://", "")` returns `undefined`, the template literal stringifies it to `"undefined"`, and `fetch` reports a generic `TypeError: fetch failed`.

## Workaround

Use the `runtime-env` helper for every read of a key that lives in the `SECRETS` JSON. The two safe helpers:

```ts
import { getRuntimeEnv, requireEnv, getAuth0Domain, getQbrickBaseUrl } from "@/lib/runtime-env";

// Optional + fallback
const audience = getRuntimeEnv("AUTH0_AUDIENCE");

// Required (throws on miss with a clear message)
const clientId = requireEnv("AUTH0_CLIENT_ID");

// Convenience for Auth0 / qbrick base URLs
const domain = getAuth0Domain();
```

Sweep regex when auditing: `process\.env\.(AUTH0_|QAP_|DB_|VALKEY_|RAG_AGENT|QBRICK_|MMBR_ENV)`. Exclude `node_modules`, `.next`, and `tests/`. Hits in `runtime-env.ts` itself (the entry-point reading `process.env.SECRETS`), `dev-bypass.ts` (dev-only toggles), and `qbricks-mock.ts` are legitimate. `NEXT_PUBLIC_*` reads are also legitimate since those are inlined at build time and cannot be read via the helper.

## Fix (deferred)

Long-term idiomatic fix is to map each key individually in the task definition `secrets` array, the way `QAP_*` keys were mapped in earlier task defs:

```json
{ "name": "AUTH0_CLIENT_ID", "valueFrom": "arn:aws:secretsmanager:...:KEY::AUTH0_CLIENT_ID::" }
```

After that, `process.env.X` works directly and the helper becomes optional. The IaC PR `feat/mmbr-144` keeps the JSON-blob shape — this is a separate cleanup nobody owns yet. Tracked verbally with infra; no ticket as of 2026-05-01.

## Related

- `decisions/why-jwt-not-db-role-claim.md` (if/when written) — same `runtime-env` consumer
- `architecture/auth-flow.md` — Auth0 + QAP token flow
- `setup/aws-sso-setup.md` — env profiles
