# Pattern — Adding a New User Role

> How to add a brand-new role (beyond `operator`, `admin`, `superadmin`).

## Overview

We currently have three roles (see `.claude/docs/architecture/rbac.md`). Adding a fourth means updating every place that the union `operator | admin | superadmin` is referenced, plus the DB schema, the seed, and at least one permission in the feature matrix.

## Step-by-step

### Step 1: Update the type alias

`types/domain.ts`:

```ts
// Before
export type UserRole = "operator" | "admin" | "superadmin";

// After
export type UserRole = "operator" | "admin" | "superadmin" | "analyst";
```

All places that use `UserRole` will now typecheck against the new role automatically.

### Step 2: Update the role parser

`lib/auth/role.ts`:

```ts
export function parseUserRole(value: string | null | undefined): UserRole {
  if (value === "admin" || value === "superadmin" || value === "analyst") {
    return value;
  }
  return "operator";
}
```

### Step 3: Add a new migration

**Never mutate existing migration files.** Add a new migration in `db/migrations/0003_add_analyst_role.sql`:

```sql
DO $$
DECLARE
  c text;
BEGIN
  FOR c IN
    SELECT conname FROM pg_constraint
    WHERE conrelid = 'mmbr.users'::regclass
      AND contype = 'c'
      AND pg_get_constraintdef(oid) LIKE '%role%'
  LOOP
    EXECUTE format('ALTER TABLE mmbr.users DROP CONSTRAINT %I', c);
  END LOOP;
END $$;

ALTER TABLE mmbr.users
  ADD CONSTRAINT users_role_check
  CHECK (role IN ('operator', 'admin', 'superadmin', 'analyst'));

-- Repeat for mmbr.whitelist
DO $$
DECLARE
  c text;
BEGIN
  FOR c IN
    SELECT conname FROM pg_constraint
    WHERE conrelid = 'mmbr.whitelist'::regclass
      AND contype = 'c'
      AND pg_get_constraintdef(oid) LIKE '%role%'
  LOOP
    EXECUTE format('ALTER TABLE mmbr.whitelist DROP CONSTRAINT %I', c);
  END LOOP;
END $$;

ALTER TABLE mmbr.whitelist
  ADD CONSTRAINT whitelist_role_check
  CHECK (role IN ('operator', 'admin', 'superadmin', 'analyst'));
```

The `DO $$` block is defensive — it drops any existing CHECK constraint on the role column regardless of the auto-generated name (see `.claude/docs/adr/0002-db-role-not-jwt-claim.md` for why in-place migration edits are banned).

### Step 4: Add a dev user for the new role

`db/seed.sql`:

```sql
INSERT INTO mmbr.users (id, auth0_id, email, full_name, role) VALUES
  ('10000000-0000-0000-0000-000000000001', 'dev-user-001', 'dev@mmbr.ai', 'Dev Operator', 'operator'),
  ('10000000-0000-0000-0000-000000000003', 'dev-manager-001', 'manager@mmbr.ai', 'Dev Manager', 'admin'),
  ('10000000-0000-0000-0000-000000000002', 'dev-admin-001', 'admin@mmbr.ai', 'Dev Admin', 'superadmin'),
  ('10000000-0000-0000-0000-000000000004', 'dev-analyst-001', 'analyst@mmbr.ai', 'Dev Analyst', 'analyst')  -- new
ON CONFLICT (auth0_id) DO NOTHING;

-- Don't forget to assign plants
INSERT INTO mmbr.user_plants (user_id, plant_id) VALUES
  -- ... existing rows ...
  ('10000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000001'),
  ('10000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000002')
ON CONFLICT (user_id, plant_id) DO NOTHING;
```

### Step 5: Update the dev-bypass role switcher

`lib/dev-bypass.ts`:

```ts
export const DEV_USER_AUTH0_IDS: Record<UserRole, string> = {
  operator: "dev-user-001",
  admin: "dev-manager-001",
  superadmin: "dev-admin-001",
  analyst: "dev-analyst-001",  // new
};

export const DEV_USER_NAMES: Record<UserRole, string> = {
  operator: "Dev Operator",
  admin: "Dev Manager",
  superadmin: "Dev Admin",
  analyst: "Dev Analyst",  // new
};
```

These are `Record<UserRole, string>` so TypeScript will force you to fill them in when you add the role to the union.

### Step 6: Update the Sidebar role label map

`components/layout/Sidebar.tsx`:

```tsx
const ROLE_LABELS: { [K in UserRole]: string } = {
  operator: "Operator",
  admin: "Admin",
  superadmin: "Super Admin",
  analyst: "Analyst",  // new
};
```

### Step 7: Update the Role × Feature matrix

`.kiro/specs/mmbr-web-phase1/requirements.md` (Req 9):

Add a new column:

```markdown
| Feature | Operator | Admin | SuperAdmin | Analyst |
|---------|----------|-------|------------|---------|
| Chat (assigned plants) | ✅ | ✅ | ✅ | ✅ |
| ...
```

Define what the new role can and cannot do in every feature row.

### Step 8: Update route guards and tests

For every existing guarded route (see `.claude/docs/reference/patterns/adding-a-guarded-route.md`), decide whether the new role should be allowed and update the guard logic + tests accordingly.

Example for Documents Panel:

```tsx
// Sidebar UI gate
{(userRole === "superadmin" || userRole === "analyst") && (
  <button onClick={...}>Documents Panel</button>
)}

// Layout guard
if (role !== "superadmin" && role !== "analyst") {
  redirect("/chat");
}

// API guard
if (user.role !== "superadmin" && user.role !== "analyst") {
  return forbidden();
}
```

Or, if the permissions are getting complex, extract a helper:

```ts
// lib/auth/permissions.ts
export function canAccessDocumentsPanel(role: UserRole): boolean {
  return role === "superadmin" || role === "analyst";
}
```

And use `canAccessDocumentsPanel(role)` everywhere.

### Step 9: Run migrations + reseed

```bash
docker compose down -v
docker compose up -d postgres
pnpm db:seed
```

### Step 10: Manually verify

Edit `.env.local`:

```bash
DEV_USER_ROLE=analyst
```

Restart `pnpm dev` and navigate around the app. Verify:
- Sidebar shows the correct role label ("Analyst")
- User info footer shows the role
- Accessible routes work
- Denied routes redirect correctly

### Step 11: Update docs

- `.claude/docs/architecture/rbac.md` — add the new role to the description and matrix
- `.env.local.example` — update the comment to mention the new role
- This doc — add a line at the top of the "Overview" if the role count changed

## Checklist

- [ ] `UserRole` union updated
- [ ] `parseUserRole` updated
- [ ] New migration added (not in-place edit)
- [ ] Seed updated with new dev user
- [ ] `DEV_USER_AUTH0_IDS` + `DEV_USER_NAMES` updated
- [ ] `ROLE_LABELS` updated in Sidebar
- [ ] Req 9 matrix updated
- [ ] All existing guards reviewed for new-role access decision
- [ ] Tests updated
- [ ] Migrations applied + DB reseeded
- [ ] Manual verification with `DEV_USER_ROLE=<new-role>`
- [ ] Docs updated

## References

- `.claude/docs/architecture/rbac.md`
- `.claude/docs/adr/0002-db-role-not-jwt-claim.md`
- `.claude/docs/reference/patterns/adding-a-guarded-route.md`
