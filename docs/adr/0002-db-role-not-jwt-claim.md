# Read role from DB, not the JWT claim

All authorization reads the user's role from `mmbr.users.role` in Postgres at request time (`requireAuthWithDbRole` / `getUserRoleFromDb`, deduplicated per-request via `React.cache()`), not from the Auth0 `https://mmbr.ai/role` token claim. The original header-based approach created **dual sources of truth** — UI read the DB while guards read the stale claim — so a role change didn't take effect until the token expired (a demoted superadmin kept full access for hours). DB-at-request-time is a single source of truth that takes effect on the next request, at the cost of one extra (cached) query; an Auth0 Action to refresh the claim and a Redis TTL cache were both rejected as more infrastructure for no real gain at our scale.

## Consequences

Role-gated routes must use `requireAuthWithDbRole` (not `requireAuth`); server guards must call `getUserRoleFromDb` (not read the header). The `x-user-role` header is still set but is **display-only** — never use it for authorization.
