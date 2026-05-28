# DEV_BYPASS_AUTH gated on two signals

The Auth0 bypass activates only when **both** `NODE_ENV === "development"` **and** `DEV_BYPASS_AUTH === "true"`, and `lib/dev-bypass.ts` throws at module load if `NODE_ENV=production && DEV_BYPASS_AUTH=true` — crashing the server at boot rather than silently serving every request as the seeded user. A single `NODE_ENV` gate was one misconfigured env var (bad Docker image, stray `pnpm dev`, copied `.env.local`) away from a prod auth bypass, and after 3-role RBAC that leak became a *superadmin* leak because `DEV_USER_ROLE` can elevate. A loud boot crash is the correct failure mode over a silent bypass.

## Consequences

New devs set two env vars instead of one (documented in `.env.local.example`); forgetting just shows the login page. Shipping the bypass to production now requires multiple independent mistakes and still fails closed at boot.
