# Decision — Read role from DB, not JWT claim

**Date:** 2026-04-08
**Status:** Accepted
**Context:** `feat/dev-rbac-mock` PR, v2 review feedback (H1)

## Decision

All authorization decisions read the user's role from `mmbr.users.role` in PostgreSQL at request time, not from the Auth0 ID token `https://mmbr.ai/role` claim.

## Context

When RBAC was first introduced, the middleware read the role from the Auth0 custom claim and injected it as an `x-user-role` header. Downstream code (API routes, page layouts) trusted that header for authorization decisions.

The v2 code review flagged a subtle but real problem: **dual sources of truth**.

- `(protected)/layout.tsx` read the role from the **DB** (for UI rendering)
- `(protected)/documents/layout.tsx` and `/api/documents` read from the **header** (for guarding)

These can drift. If an operator is promoted to superadmin in the DB but their existing Auth0 session still carries the stale `operator` claim:
- The sidebar shows Documents Panel (DB-correct) ✅
- Clicking it gets redirected to `/chat` (header-stale) ❌

Worse, the inverse: if a superadmin is demoted to operator, their stale token still shows as superadmin in the header and they keep full access **until the token expires** (could be hours or days).

## Alternatives considered

### Option 1: Keep header, add Auth0 Action to refresh claim on every token

**Pros**: No extra DB query per request.
**Cons**: Requires external infrastructure (Auth0 Action). Every token issuance hits our backend to fetch the role, which has its own operational cost. Still leaves a window between role change and next token refresh.

### Option 2: Read from DB at every request (chosen)

**Pros**: Single source of truth. Role changes take effect on the next request. No external infrastructure. `React.cache()` deduplicates multiple guards in the same request to a single DB query.
**Cons**: One extra DB query per request. Negligible for our traffic.

### Option 3: Use a cache (Redis/in-memory) of role lookups with TTL

**Pros**: Faster than DB lookup.
**Cons**: Cache invalidation problem returns. Not justified at our scale.

## Implementation

`lib/api/auth.ts`:

```ts
export const getUserRoleFromDb = cache(
  async (auth0Id: string): Promise<UserRole | null> => {
    const [row] = await db
      .select({ role: schema.users.role })
      .from(schema.users)
      .where(eq(schema.users.auth0Id, auth0Id))
      .limit(1);
    if (!row) return null;
    return parseUserRole(row.role);
  },
);

export async function requireAuthWithDbRole(request: NextRequest) {
  const { user, error } = requireAuth(request);
  if (error) return { user: null as never, error };
  const dbRole = await getUserRoleFromDb(user.auth0Id);
  if (!dbRole) return { user: null as never, error: unauthorized() };
  return { user: { ...user, role: dbRole }, error: null };
}
```

Used by:
- `/api/documents/route.ts` → `requireAuthWithDbRole(request)`
- `(protected)/documents/layout.tsx` → `getUserRoleFromDb(auth0Id)`
- `(protected)/layout.tsx` → queries the DB directly (same pattern)

The `React.cache()` wrapper means if both the layout and a nested API call query the role in the same request, it's one DB query, not two.

## The header is still set, but it's informational only

`middleware.ts` still sets `x-user-role` from the Auth0 claim (in prod) or the `DEV_USER_ROLE` env var (in dev). Consumers can read it for **display purposes** (e.g., showing the role in the sidebar footer) but **must not use it for authorization**.

## Never do

```ts
// ❌ BAD — header is untrusted for authorization
const { user } = requireAuth(request);
if (user.role !== "superadmin") return forbidden();
```

## Always do

```ts
// ✅ GOOD — DB is source of truth
const { user, error } = await requireAuthWithDbRole(request);
if (error) return error;
if (user.role !== "superadmin") return forbidden();
```

## Consequences

- All role-gated routes must use `requireAuthWithDbRole` (not `requireAuth`).
- All server-side guards (layout.tsx files) must call `getUserRoleFromDb` (not read the header).
- The extra DB query is acceptable; `React.cache()` deduplicates within a request.
- When a user's role is changed in the DB, the change is effective on their very next request. No need to invalidate tokens.

## References

- Surfaced as issue H1 during the v2 RBAC-mock review round (review notes are personal artifacts, not tracked).
- Commit `1b661d5` — refactor that implemented this decision
