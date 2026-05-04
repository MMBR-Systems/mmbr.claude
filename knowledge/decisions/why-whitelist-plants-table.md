---
created: 2026-05-04
updated: 2026-05-04
owner: workspace owner
---

# Why introduce `mmbr.whitelist_plants` (intent layer for plant access)

## Context

Today, granting plant access to a new operator requires three steps with a chicken-and-egg timing problem:

1. INSERT into `mmbr.whitelist` (email + role).
2. Wait for the operator's first Auth0 login. `provisionUser` creates `mmbr.users` row.
3. INSERT into `mmbr.user_plants` linking the new `users.id` to the plant(s).

Step 3 cannot be done in advance because `mmbr.user_plants.user_id` is a FK to `mmbr.users(id)`, which only exists after the operator registers. Result: operators arrive at the home screen with **zero plants**, see nothing, and stay stuck until an admin manually re-runs the SQL after they've logged in.

This breaks both UX (silent dead-end on first login) and operational ergonomics (someone has to remember to run a follow-up SQL after each operator's first session).

The granularity in `mmbr.user_plants` (per-operator plant assignment) is intentional — it's not a degenerate "all enabled plants" mapping, otherwise `mmbr.plants.enabled` alone would suffice. So we cannot fix the problem by auto-assigning all enabled plants at registration without losing the per-operator decision.

## Decision

Introduce a new table `mmbr.whitelist_plants` that captures **plant-access intent at the whitelist level**, before the user exists.

```sql
CREATE TABLE mmbr.whitelist_plants (
  whitelist_id UUID NOT NULL REFERENCES mmbr.whitelist(id) ON DELETE CASCADE,
  plant_id     UUID NOT NULL REFERENCES mmbr.plants(id)    ON DELETE CASCADE,
  assigned_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (whitelist_id, plant_id)
);
```

Mental model:

- `whitelist` + `whitelist_plants` = **intent** (admin's decision; can exist before any user)
- `users` + `user_plants` = **reality** (created at registration; copied from intent)

At registration, `provisionUser()` copies `whitelist_plants` → `user_plants` for the matching whitelist row, in the same transaction that inserts into `users`. The operator arrives at the home screen with their plants already assigned.

For superadmin / admin roles, `whitelist_plants` is empty (or ignored) — those roles bypass plant-level scoping by design.

## Alternatives considered

### A. Auto-assign every plant where `enabled = true` to every new operator

```typescript
if (whitelist.role === 'operator') {
  await db.execute(sql`
    INSERT INTO user_plants (user_id, plant_id)
    SELECT ${user.id}, p.id FROM plants p WHERE p.enabled = true
  `);
}
```

**Rejected because:** removes the per-operator granularity that `user_plants` was designed for. `plants.enabled` is a kill-switch (a plant is on or off globally), not a default-access list. Today only Clairton is enabled so behavior is identical; tomorrow with multiple plants enabled, every operator would get blanket access regardless of admin intent.

### B. Pre-create `mmbr.users` row with placeholder `auth0_id`

Allow `auth0_id` to be NULL until first login fills it. Then `user_plants` works directly.

**Rejected because:** breaks the semantic that `mmbr.users` represents registered users. Forces every read path to handle a "ghost" state where `auth0_id` is null. Auth0 callbacks would need to find-or-create-by-email logic that's currently a clean find-or-create-by-auth0-id. High blast radius for a UX fix.

### C. Keep manual: re-run `INSERT INTO user_plants … SELECT …` after each first login

The current state. Cheap to implement (zero) but operationally fragile — depends on remembering to re-run SQL after each operator logs in. Doesn't scale beyond the current low volume (single-digit operators).

**Rejected because:** the friction is already showing up in operations (this very ADR was triggered by missing the manual step). Will get worse as operator count grows.

### D. DB trigger `AFTER INSERT ON mmbr.users`

PostgreSQL trigger that copies plants on `users` insert.

**Rejected (vs the chosen approach) because:** logic invisible to the app code; harder to reason about; harder to test. The `whitelist_plants` table makes the same intent **explicit and queryable** at the data layer. Trigger could be combined with this table later if needed — they're not exclusive — but the table alone is enough.

## Consequences

### What this locks us into

- A second source-of-truth for plant assignment. **Editing `whitelist_plants` after the operator has already registered does not propagate** to `user_plants` automatically; needs explicit reconciliation logic if we want it (and a product decision on whether changes should be retroactive).
- Admin UI/API needs to expose **two surfaces**: managing whitelist entries (email + role) and managing whitelist plants (which plants per entry). They could be one form, but the data is two tables.
- Backfill needed for existing whitelist rows: decide whether to map them to "all enabled plants" (keeps current implicit behavior) or leave empty (forces explicit assignment going forward). Recommend backfilling with current behavior to avoid surprising existing users.

### What it costs

- New migration in `web-platform/db/migrations/`.
- Change in `lib/auth/user-provisioning.ts` (`provisionUser()` copies on insert).
- Future: admin endpoints + UI for CRUD on `whitelist_plants`.
- Doc updates: `architecture/rbac.md` (currently outdated re: `users.role`), `reference/operations/whitelist-add-user.md` (new flow).

### What's left undecided

- **Editing existing whitelist plants** — do changes propagate live to `user_plants` (active session sees new plants on next request) or only at re-registration? Default: snapshot at registration; reconciliation is a follow-up feature.
- **Operator role change after registration** (`whitelist.role` updated from `operator` → `superadmin` or vice-versa). Today the role lookup is live via FK join, but `user_plants` survives a role change. Cleanup behavior on role transition is undefined.
- **Disabling a plant** — does it cascade to remove `user_plants` rows? Today no (the `enabled` flag is the gate). Same after `whitelist_plants` is added.

## Implementation outline (when this ships)

Two phases:

**Phase 1 — schema + provisioning code (single PR, can ship without UI):**
1. Migration: create `mmbr.whitelist_plants`.
2. Backfill: insert `(whitelist_id, plant_id)` for every existing operator whitelist row × every `enabled = true` plant.
3. Modify `provisionUser()` to copy `whitelist_plants` → `user_plants` after the `users` INSERT.
4. Update `findWhitelistEntry()` (optional) to return associated plant IDs alongside role.
5. New SQL pattern for manual operator additions (CTE-based — see `reference/operations/whitelist-add-user.md`).

**Phase 2 — admin endpoints + UI (separate PR):**
6. `POST /api/admin/whitelist` — create entry with `{ email, role, plantIds[] }`.
7. `PATCH /api/admin/whitelist/:id/plants` — replace plant set.
8. Admin UI form combining the two.

Phase 1 alone unblocks the operational pain immediately; Phase 2 is the UX delivery.
