---
created: 2026-05-04
updated: 2026-05-04
owner: workspace owner
---

# Add a user to the access whitelist

The MMBR access model is whitelist-based: an email cannot register or log in until an entry exists in `mmbr.whitelist`. The whitelist row determines the role the user gets at first registration.

For users with role `operator`, **whitelist alone is not enough** — they also need at least one row in `mmbr.user_plants` to see any plant. `superadmin` bypasses plant assignment (full access to all plants).

## Schema

```sql
mmbr.whitelist (
  id          UUID PK,
  email       VARCHAR(255) UNIQUE,                      -- case-sensitive at constraint; queries use LOWER()
  role        VARCHAR(20) DEFAULT 'operator'
              CHECK (role IN ('operator', 'admin', 'superadmin')),
  created_at  TIMESTAMPTZ
)

mmbr.users (
  id            UUID PK,
  auth0_id      VARCHAR(255) UNIQUE,
  email         VARCHAR(255) UNIQUE,
  full_name     VARCHAR(255),
  whitelist_id  UUID NOT NULL FK → mmbr.whitelist(id),  -- role lives there, not here
  created_at    TIMESTAMPTZ,
  updated_at    TIMESTAMPTZ
)
```

Index: `idx_whitelist_email_lower ON mmbr.whitelist(LOWER(email))` — lookups are case-insensitive.

**Important historical note:** earlier versions of the schema had `mmbr.users.role`. It was dropped in migration `0002_add_whitelist_fk_to_users.sql`. **Role is now resolved via the whitelist FK join** (`mmbr.users.whitelist_id → mmbr.whitelist.role`). This means changing `mmbr.whitelist.role` for a registered user's email **takes effect immediately** on the next request — there is no "copy at registration" anymore.

## How registration uses it

`web-platform/app/api/auth/check-email/route.ts` queries the whitelist on login attempt. If no row matches `LOWER(email)`, the response is `EMAIL_NOT_WHITELISTED` with the user-facing message *"This email doesn't have access to MemBrain yet."* On match, registration creates a row in `mmbr.users` with `whitelist_id` pointing at the whitelist row. Authorization queries always join through this FK to read the current role — so editing the whitelist row updates the live role.

## When to use this runbook

- Add a new team member or stakeholder before they can register.
- Bulk-add users from a confirmed list (Slack, ticket, email).

## When NOT to use

- **Changing a role of an already-registered user** — update `mmbr.users.role` directly. The whitelist value is only consulted at first registration; later edits to the whitelist row do not propagate.
- **Removing access for a user who's already registered** — revoke at Auth0 (so the session can't refresh) and delete from `mmbr.users`. Removing from the whitelist alone won't kick out an active session.

## SQL template

Always insert in **lowercase**. UNIQUE is case-sensitive at the constraint, but lookups normalize via `LOWER()`. Mixed casing risks duplicate rows that match the same login attempt.

```sql
INSERT INTO mmbr.whitelist (email, role) VALUES
  ('lowercase.email@example.com', 'operator'),
  ('another.user@example.com', 'superadmin')
ON CONFLICT (email) DO NOTHING;
```

### Gotcha — `ON CONFLICT DO NOTHING` does NOT update existing roles

If an email is already in the whitelist with the wrong role, `ON CONFLICT (email) DO NOTHING` is a **no-op for that row**. You'll insert the new ones successfully but the existing one stays with its old role, even if the same INSERT statement specifies a new one.

**Variant that bites in batch CTE patterns:** the trick `ON CONFLICT (email) DO UPDATE SET email = EXCLUDED.email` is sometimes used to force `RETURNING id` on conflict (so the CTE gets the row id for downstream INSERTs). This **also does not update the role** — `email` is the only column "updated", and to itself. Existing `role` is preserved.

**To upsert role explicitly** (overwrite role of pre-existing entries in the same statement):

```sql
INSERT INTO mmbr.whitelist (email, role) VALUES
  ('user@example.com', 'operator')
ON CONFLICT (email) DO UPDATE SET role = EXCLUDED.role;
```

Use this with care — overwriting role on conflict is a behavior change. Often safer to inspect first and run a separate `UPDATE` for any role corrections:

```sql
UPDATE mmbr.whitelist SET role = 'operator'
WHERE LOWER(email) IN ('user1@example.com', 'user2@example.com');
```

Roles propagate live through the `users.whitelist_id` FK join, so a role correction takes effect on the user's next request — no re-login required.

## Two paths to apply it

### Path A — Recommended: edit `seed.sql` + redeploy + run `db-seed.sh`

Best for entries that should live in the repo's source of truth. `db/seed.sql` is idempotent (`ON CONFLICT DO NOTHING`).

1. Edit `web-platform/db/seed.sql` and append the whitelist INSERT plus, for each operator, the plant-assignment INSERT (see [Plant assignment](#plant-assignment-operators-only) above for the SQL shape).
2. Commit, then push a release branch for the target env (`release-qa/<slug>` or `release-prod/<slug>`).
3. Wait for deploy to complete.
4. Run the seed script:
   ```
   .claude/knowledge/reference/operations/scripts/db-seed.sh <env>
   ```
5. Verify whitelist:
   ```sql
   SELECT email, role, created_at FROM mmbr.whitelist
   WHERE email = ANY(ARRAY['email1@example.com', 'email2@example.com']);
   ```
6. After each operator's first login, re-run the seed (`db-seed.sh <env>`) to retroactively create their `user_plants` link. The plant-assignment SELECT…INSERT is idempotent and only fires once `mmbr.users` has the row.

### Path B — Quick: direct SQL via bastion (one-off)

For ad-hoc additions that don't need to live in `seed.sql` (e.g. testing access for a single email).

1. Open the bastion tunnel:
   ```
   .claude/knowledge/reference/operations/scripts/bastion-tunnel.sh <env>
   ```
2. Connect with psql / DBeaver to `localhost:5433`.
3. Run the INSERT manually.

The row won't be in `seed.sql`. Re-running seed later won't recreate or remove it — the existing whitelist row stays untouched.

## Roles

- `operator` — default. Standard plant access (chat with assigned plants only). **Requires plant assignment** (see next section).
- `admin` — plant manager. Access scope TBD; behaves between operator and superadmin.
- `superadmin` — full system access (QBricks management, multi-plant metrics, Documents Panel). **Bypasses plant assignment** — sees all plants without any `user_plants` entry.

The schema CHECK constraint only allows these three values (added by migration `0003_add_admin_role.sql`). Anything else fails with a constraint violation.

## Plant assignment (operators only)

`mmbr.user_plants` is a many-to-many link between users and plants:

```sql
mmbr.user_plants (
  user_id     UUID FK → mmbr.users(id)   ON DELETE CASCADE,
  plant_id    UUID FK → mmbr.plants(id)  ON DELETE CASCADE,
  assigned_at TIMESTAMPTZ,
  PRIMARY KEY (user_id, plant_id)
)
```

An operator with no row in `user_plants` sees no plants in the UI and effectively has no usable access, even though they're whitelisted and registered.

### Timing problem

`user_plants` references `mmbr.users(id)`, which is only created at **first login** (registration). So you can't pre-insert the link before the user has authenticated at least once.

### Idempotent SQL that handles both timings

The cleanest approach is to use a `SELECT … FROM mmbr.users WHERE email = …` subquery in the INSERT. It's safe to run repeatedly:

```sql
-- Assign a plant to a whitelisted operator. Safe before or after first login.
INSERT INTO mmbr.user_plants (user_id, plant_id)
SELECT u.id, '<plant-uuid>'
FROM mmbr.users u
WHERE LOWER(u.email) = LOWER('operator.email@example.com')
ON CONFLICT DO NOTHING;
```

- **Before the operator's first login**: the SELECT returns 0 rows → the INSERT is a no-op.
- **After first login**: the SELECT returns the user → the INSERT creates the link (or is a no-op if it already exists).

This means you can run this statement together with the whitelist INSERT in seed.sql and it will eventually link the operator the next time `db-seed.sh` runs after they've logged in.

### Plant UUIDs (current)

From `seed.sql`:

| Plant | UUID |
|---|---|
| Double Eagle | `00000000-0000-0000-0000-000000000001` |
| Clairton | `00000000-0000-0000-0000-000000000002` |
| Briar Creek | `00000000-0000-0000-0000-000000000003` |
| Camp Swift | `00000000-0000-0000-0000-000000000004` |

Today only **Clairton** is the live/enabled plant for real operators.

### Don't assign plants to a superadmin

There's no harm at the schema level (the FK and PK accept it), but it's noise. Authorization for superadmin doesn't consult `user_plants` at all.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| User reports *"This email doesn't have access to MemBrain yet"* | Email not in whitelist (or wrong env). | `SELECT email FROM mmbr.whitelist WHERE LOWER(email) = LOWER('<email>')` to confirm. Add if missing. |
| User registered with the wrong role | Role at first-login was copied from the whitelist row that existed at that moment. Whitelist edits after the fact don't propagate. | `UPDATE mmbr.users SET role = '<correct>' WHERE LOWER(email) = LOWER('<email>')`. |
| INSERT fails with `value violates check constraint` | Role outside `('operator', 'superadmin')`. | Use one of the two allowed values; for anything else (e.g. `admin`), check the corresponding migration first. |
| Two whitelist rows for the same email | One was inserted with mixed case, the other lowercase. UNIQUE didn't dedupe because constraint is case-sensitive. | Delete the non-lowercase row: `DELETE FROM mmbr.whitelist WHERE email = '<MixedCase>'`. |
