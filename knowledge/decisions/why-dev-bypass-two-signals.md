# Decision — DEV_BYPASS_AUTH gated on two signals

**Date:** 2026-04-08
**Status:** Accepted
**Context:** `feat/dev-rbac-mock` PR, v1 review feedback (H2)

## Decision

The authentication bypass (`DEV_BYPASS_AUTH`) is gated on **two independent signals** instead of one, with a hard-fail guard at module load time in production.

- **Signal 1**: `NODE_ENV === "development"`
- **Signal 2**: `DEV_BYPASS_AUTH === "true"`
- **Failsafe**: `lib/dev-bypass.ts` throws at module load time if `NODE_ENV=production && DEV_BYPASS_AUTH=true`

## Context

The original implementation used only `NODE_ENV === "development"` as the guard:

```ts
const DEV_BYPASS_AUTH = process.env.NODE_ENV === "development";
```

This worked, but had a subtle risk. Next.js hardcodes `NODE_ENV=production` in `next build`, so in theory it should be impossible to ship a production build with the bypass active. But:

1. A misconfigured Docker image could set `NODE_ENV=development` at runtime
2. A Vercel preview environment running the dev script (`pnpm dev`) by mistake
3. A custom deployment pipeline that copies `.env.local` into the image
4. An engineer testing "will my staging env pick up my local changes?" and forgetting to revert

In each of those cases, the bypass would silently skip Auth0 entirely and any request would be logged in as the seeded user. **Before the 3-role RBAC work this was an "operator access" leak. After it's a "superadmin access" leak** — because `DEV_USER_ROLE` can elevate.

The v1 code review flagged that making the bypass a one-signal gate was "fine before, but the blast radius is now worse because of role elevation."

## Alternatives considered

### Option 1: Keep it at one signal, improve deploy pipeline hygiene

**Pros**: Simpler.
**Cons**: Relies on operational discipline that can't be enforced in code. One misconfigured env var away from a prod-side auth bypass.

### Option 2: Two signals (chosen)

**Pros**: Requires two independent mistakes to trigger. The second signal (`DEV_BYPASS_AUTH=true`) is explicit and grep-able in deploy configs. Documented in `.env.local.example`.
**Cons**: Slightly more verbose setup for new devs (one extra env var to set).

### Option 3: Two signals + runtime failsafe (chosen, expanded)

**Pros**: Even if somehow both signals were accidentally set in production, the server crashes at module load before serving a single request. Noisy failure mode is better than silent bypass.
**Cons**: None significant. The throw only fires in a specific (invalid) state.

## Implementation

`lib/dev-bypass.ts`:

```ts
// Hard fail if anyone tries to enable the bypass in a production build.
// This runs at module load and crashes the server before any request is handled.
if (
  process.env.NODE_ENV === "production" &&
  process.env.DEV_BYPASS_AUTH === "true"
) {
  throw new Error(
    "DEV_BYPASS_AUTH must NOT be set in production. " +
      "Remove the env var from the deploy config.",
  );
}

export const DEV_BYPASS_AUTH =
  process.env.NODE_ENV === "development" &&
  process.env.DEV_BYPASS_AUTH === "true";
```

The throw runs **at module load time** (not per-request), so the server crashes during boot in a misconfigured production build. This is louder than a silent auth bypass and easier to detect in logs.

## Dev onboarding

New developers need to set `DEV_BYPASS_AUTH=true` in `.env.local`. This is documented in `.env.local.example`:

```bash
# Dev: bypass Auth0 entirely and inject a seeded dev user (set to "true" to activate).
# MUST NEVER be set in production — the server will throw at boot if it is.
DEV_BYPASS_AUTH=true
```

If they forget, `/chat` redirects to `/login` (because the middleware goes through the normal Auth0 path and doesn't find a session). The failure mode is "login page shows up" — easy to diagnose and fix.

## Consequences

- Slightly more friction for new dev setup (two env vars instead of one). Mitigated by `.env.local.example`.
- A production-built server will **crash on boot** if both signals are accidentally set. This is the correct failure mode.
- The bypass is now impossible to ship to production without multiple layers of mistakes.

## References

- Surfaced as issue H2 during the v1 RBAC-mock review round (review notes are personal artifacts, not tracked).
- Commit `f04aadc` — refactor that implemented this decision
- `lib/dev-bypass.ts` — the single source of truth for the bypass
