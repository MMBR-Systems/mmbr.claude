# Pattern — Adding a Role-Guarded Route

> How to add a new route that should only be accessible to certain roles.

## Overview

A "guarded route" is a route that requires the user to have a specific role (e.g., `superadmin`). In our system, guarding is applied in **three layers** (defense in depth):

1. **UI** — hide the nav item in `Sidebar.tsx`
2. **Page/layout** — server-side redirect in `(protected)/<route>/layout.tsx`
3. **API** — 403 Forbidden in the corresponding API route

All three layers read the role **from the DB**, not from the JWT claim or the request header.

## Step-by-step

### Step 1: UI gate in Sidebar

Edit `components/layout/Sidebar.tsx`:

```tsx
{userRole === "superadmin" && (
  <button
    type="button"
    onClick={() => {
      router.push("/my-route");
      onNavigate?.();
    }}
    className={cn(
      "flex w-full items-center gap-1 overflow-clip px-4 py-3 text-base transition-colors",
      pathname.startsWith("/my-route")
        ? "border-r-2 border-primary bg-accent text-foreground"
        : "text-foreground hover:bg-secondary",
    )}
  >
    <MyIcon className="size-6 shrink-0" />
    <span>My Route</span>
  </button>
)}
```

**Rules:**
- Use the `userRole` prop that comes from the context / server layout (not a header read).
- Match the styling pattern of the existing `New Conversation` / `Documents Panel` buttons.

### Step 2: Add a server-side layout guard

Create `app/(protected)/<route>/layout.tsx`:

```tsx
import { redirect } from "next/navigation";
import { headers } from "next/headers";
import { getUserRoleFromDb } from "@/lib/api/auth";

export default async function MyRouteLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const headersList = await headers();
  const auth0Id = headersList.get("x-user-id");

  if (!auth0Id) {
    redirect("/login");
  }

  const role = await getUserRoleFromDb(auth0Id);

  if (role !== "superadmin") {
    redirect("/chat");
  }

  return <>{children}</>;
}
```

**Rules:**
- Use `getUserRoleFromDb(auth0Id)` — NEVER trust the `x-user-role` header for authorization decisions (see `.claude/knowledge/decisions/why-db-role-not-jwt-claim.md`).
- The layout runs **before** the page renders, so non-authorized users never see the content.
- Redirect to `/chat` for authorized-but-wrong-role users. Redirect to `/login` only for genuinely unauthenticated users.

### Step 3: Add API route guard

In your API route (`app/api/<resource>/route.ts`):

```ts
import { requireAuthWithDbRole } from "@/lib/api/auth";
import { forbidden, handleApiError } from "@/lib/api/errors";

export async function GET(request: NextRequest) {
  const { user, error } = await requireAuthWithDbRole(request);
  if (error) return error;

  if (user.role !== "superadmin") {
    return forbidden();
  }

  // ... your actual route logic
}
```

**Rules:**
- Use `requireAuthWithDbRole` (not `requireAuth`) for any role-gated endpoint.
- Return `forbidden()` with no arguments — the default body is `"Forbidden"` which doesn't leak which role is required.
- `React.cache()` inside `requireAuthWithDbRole` deduplicates the DB query if the layout and route run in the same request.

### Step 4: Update the Role × Feature matrix

Edit `.kiro/specs/mmbr-web-phase1/requirements.md` (Req 9) to add your new feature row:

```markdown
| My Feature | ❌ | ❌ | ✅ |
```

This keeps the matrix canonical and forces you to think about which role(s) should get access.

### Step 5: Add tests

#### API route test (`tests/unit/api/<resource>.test.ts`):

```ts
const mockRequireAuthWithDbRole = jest.fn();
jest.mock("@/lib/api/auth", () => ({
  requireAuthWithDbRole: (req) => mockRequireAuthWithDbRole(req),
}));

import { GET } from "@/app/api/<resource>/route";

describe("GET /api/<resource> — RBAC", () => {
  it("returns 403 for operator", async () => {
    mockRequireAuthWithDbRole.mockResolvedValue({
      user: { auth0Id: "x", role: "operator", selectedPlantId: null },
      error: null,
    });
    const res = await GET(makeRequest());
    expect(res.status).toBe(403);
  });

  it("returns 403 for admin", async () => {
    mockRequireAuthWithDbRole.mockResolvedValue({
      user: { auth0Id: "x", role: "admin", selectedPlantId: null },
      error: null,
    });
    const res = await GET(makeRequest());
    expect(res.status).toBe(403);
  });

  it("returns 200 for superadmin", async () => {
    mockRequireAuthWithDbRole.mockResolvedValue({
      user: { auth0Id: "x", role: "superadmin", selectedPlantId: null },
      error: null,
    });
    // Add MSW handler for the downstream QBricks call if needed
    const res = await GET(makeRequest());
    expect(res.status).toBe(200);
  });
});
```

#### Sidebar visibility test:

Add to `tests/unit/layout/Sidebar.test.tsx`:

```tsx
it("renders My Route link for superadmin", () => {
  renderSidebar({ userName: "John Admin", userRole: "superadmin" });
  expect(screen.getByText("My Route")).toBeInTheDocument();
});

it("does not render My Route link for operator", () => {
  renderSidebar({ userName: "John Operator", userRole: "operator" });
  expect(screen.queryByText("My Route")).not.toBeInTheDocument();
});
```

## Checklist

Before opening a PR for a new guarded route:

- [ ] Sidebar nav is gated by `userRole === "..."`
- [ ] `(protected)/<route>/layout.tsx` exists and calls `getUserRoleFromDb`
- [ ] API route uses `requireAuthWithDbRole` + `forbidden()` on role mismatch
- [ ] Req 9 matrix updated
- [ ] Sidebar test covers both allowed and denied roles
- [ ] API route test covers 403 for each denied role + 200 for the allowed role
- [ ] Manual test: set `DEV_USER_ROLE=operator` → visit `/my-route` → redirected to `/chat`
- [ ] Manual test: set `DEV_USER_ROLE=superadmin` → visit `/my-route` → loads correctly

## Example

The `Documents Panel` route is the canonical example. See:

- `components/layout/Sidebar.tsx` — UI gate
- `app/(protected)/documents/layout.tsx` — server-side redirect
- `app/api/documents/route.ts` — API 403
- `tests/unit/api/documents.test.ts` — tests
- `tests/unit/layout/Sidebar.test.tsx` — UI visibility tests

## References

- `.claude/knowledge/architecture/rbac.md` — how RBAC works overall
- `.claude/knowledge/decisions/why-db-role-not-jwt-claim.md` — why we read from DB
- `.claude/knowledge/reference/patterns/adding-a-new-role.md` — if your route introduces a new role entirely
