# RBAC — Role-Based Access Control

> How role-based authorization works in the MMBR web platform today.

## Roles (3)

Defined in `types/domain.ts` as `UserRole`:

| Role | Description |
|------|-------------|
| `operator` | Standard plant operator. Limited to chat with assigned plants. |
| `admin` | Plant manager. Access to metrics of assigned plants (TBD scope). |
| `superadmin` | System administrator. Full access: QBricks management, multi-plant metrics, Documents Panel. |

The `UserRole` alias is the **single source of truth**. Never inline the literal union.

## Source of truth: PostgreSQL (not the JWT claim)

The user's role is stored in `mmbr.users.role`. **Authorization decisions always read from the DB at request time**, never from the Auth0 ID token claim.

### Why DB and not the claim?

If a user is demoted from `superadmin` to `admin` in the DB, their existing Auth0 session still carries the stale `https://mmbr.ai/role` claim. If we trusted the claim, they'd keep superadmin access until the token expires (could be hours). Reading from the DB means the role change takes effect on the **next request**.

### How it works

1. **Middleware** (`proxy.ts`) extracts `sub` from Auth0 session, sets `x-user-id` header. The `x-user-role` header is still set from the claim but is **informational only** — downstream code should not trust it for authorization.
2. **`requireAuthWithDbRole`** (`lib/api/auth.ts`) — wraps `requireAuth` and queries `schema.users.role` by `auth0Id` using `getUserRoleFromDb(auth0Id)`.
3. **`getUserRoleFromDb`** is wrapped in `React.cache()` so multiple guards in the same request share one DB query.

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
```

## Defense in depth: Documents Panel (superadmin only)

The Documents Panel is a concrete example of layered RBAC. **All three layers query the DB**, not the header.

### Layer 1: UI hide (`Sidebar.tsx`)

```tsx
{userRole === "superadmin" && (
  <button onClick={() => router.push("/documents")}>Documents Panel</button>
)}
```

The `userRole` prop comes from `(protected)/layout.tsx`, which reads from the DB in production mode (and from `DEV_USER_ROLE` env var in dev bypass).

### Layer 2: Server-side route guard (`(protected)/documents/layout.tsx`)

```tsx
export default async function DocumentsLayout({ children }) {
  const headersList = await headers();
  const auth0Id = headersList.get("x-user-id");
  if (!auth0Id) redirect("/login");
  const role = await getUserRoleFromDb(auth0Id);
  if (role !== "superadmin") redirect("/chat");
  return <>{children}</>;
}
```

Direct URL visits to `/documents` are redirected to `/chat` for non-superadmins. This runs **before** any page content is rendered.

### Layer 3: API guard (`/api/documents/route.ts`)

```ts
const { user, error } = await requireAuthWithDbRole(request);
if (error) return error;
if (user.role !== "superadmin") return forbidden();
```

Returns `403 Forbidden` (no role leakage in the body — just `"Forbidden"`).

## Parsing untrusted role input: `parseUserRole`

Any time a role value comes from an untrusted source (HTTP header, env var, external API), pass it through `parseUserRole()` from `lib/auth/role.ts`:

```ts
export function parseUserRole(value: string | null | undefined): UserRole {
  if (value === "admin" || value === "superadmin") return value;
  return "operator";
}
```

**Never use `as UserRole` casts at the auth boundary.** A malformed value would propagate as a "valid" role through the type system.

### Why `lib/auth/role.ts` and not `lib/api/auth.ts`?

`proxy.ts` runs in the **Edge runtime** and cannot import Node-only code (`pg`, Drizzle, `crypto`). `lib/api/auth.ts` imports `db` from Drizzle, so importing it from middleware pulls Node code into Edge runtime and crashes with `"The edge runtime does not support Node.js 'crypto' module"`.

`lib/auth/role.ts` is intentionally standalone (only imports `UserRole` type) so the middleware can import `parseUserRole` safely.

## Role × Feature matrix (Req 9)

| Feature | Operator | Admin | SuperAdmin |
|---------|----------|-------|------------|
| Chat (assigned plants) | ✅ | ✅ | ✅ |
| Plant selector (own plants) | ✅ | ✅ | ✅ |
| Plant selector (all plants) | ❌ | ❌ | ✅ |
| Feedback on AI responses | ✅ | ✅ | ✅ |
| Documents Panel | ❌ | ❌ | ✅ |
| Metrics (assigned plant) | ❌ | ✅ | ✅ |
| Metrics (all plants) | ❌ | ❌ | ✅ |
| QBricks management | ❌ | ❌ | ✅ |
| Profile (view/edit own) | ✅ | ✅ | ✅ |

Matrix lives in `.kiro/specs/mmbr-web-phase1/requirements.md` (Req 9) — that's the canonical version. This file is a snapshot for quick reference.

## Dev mode: seeded users per role

In dev bypass mode (`DEV_BYPASS_AUTH=true`), the middleware injects a seeded user based on `DEV_USER_ROLE`:

| `DEV_USER_ROLE` | `x-user-id` | Full name |
|-----------------|-------------|-----------|
| `operator` (default) | `dev-user-001` | Dev Operator |
| `admin` | `dev-manager-001` | Dev Manager |
| `admin` | `dev-admin-001` | Dev Admin |

All three users are seeded in `db/seed.sql` with their corresponding role in `mmbr.users.role`, so the DB lookup in `getUserRoleFromDb` returns the correct role.

## Testing RBAC

Tests for `/api/documents` in `tests/unit/api/documents.test.ts` mock `requireAuthWithDbRole` directly (not the DB) and assert:

- Operator → 403
- Admin → 403
- Superadmin → 200 with MSW-mocked payload

See also `tests/unit/layout/Sidebar.test.tsx` for UI-level visibility tests (`renders Documents nav link for superadmin` and `does not render Documents nav link for operator`).

## When adding a new guarded route

See `.claude/knowledge/reference/patterns/adding-a-guarded-route.md`.

## When adding a new role

See `.claude/knowledge/reference/patterns/adding-a-new-role.md`.
