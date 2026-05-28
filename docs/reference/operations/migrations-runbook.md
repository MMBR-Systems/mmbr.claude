---
title: Database Migrations — Runbook
created: 2026-05-04
updated: 2026-05-04
---

# Database Migrations — Runbook

How we author, apply, and validate `mmbr.*` schema migrations across dev / qa / prod. This is the single source of truth for the day-to-day procedure and the trade-offs behind the current and target state.

For AWS connectivity (bastion, RDS Proxy, ECS Exec, secrets) see [`aws-mmbr.md`](./aws-mmbr.md).

## State summary (as of 2026-05-04)

| Layer | Status |
|---|---|
| Migration files in `web-platform/db/migrations/*.sql` | ✅ versioned, lexicographically ordered |
| Idempotency (`IF NOT EXISTS`, etc.) | ✅ since `0001-0005` refactor on 2026-05-04 |
| Drizzle journal (`db/migrations/meta/_journal.json`) | ✅ entries for `0001`–`0005` claimed as applied. The first deploy after this is merged seeds `drizzle.__drizzle_migrations` in each env by replaying the (idempotent) SQL files; subsequent deploys skip already-applied entries. |
| Auto-run in CI/CD | ✅ implemented (`web-build-and-push.yaml` runs an ECS one-off task with `node scripts/run-migrations.js` between registering the new task definition and updating the ECS service). ⚠️ **First deploy after merge exercises it for real** — verify in dev before promoting to QA/prod. See [Auto-run](#auto-run). |
| Auto-run on local first start | ✅ `docker-compose.yml` mounts `db/migrations/` into Postgres `initdb.d` (only fires on volume creation) |

## How to author a new migration

1. Update the Drizzle schema in `web-platform/lib/db/schema.ts`.
2. Generate the SQL file:
   ```sh
   cd web-platform
   pnpm db:generate
   ```
   This writes `db/migrations/NNNN_<slug>.sql` and updates `db/migrations/meta/_journal.json`.
3. Hand-edit the generated SQL to keep it idempotent and explicit:
   - `CREATE TABLE IF NOT EXISTS`
   - `CREATE INDEX IF NOT EXISTS`
   - `ALTER TABLE ... ADD COLUMN IF NOT EXISTS`
   - `ALTER TABLE ... DROP COLUMN IF EXISTS`
   - `ADD CONSTRAINT` — wrap in a `DO` block (PostgreSQL has no `IF NOT EXISTS` for constraints):
     ```sql
     DO $$
     BEGIN
       IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'my_constraint') THEN
         ALTER TABLE mmbr.my_table ADD CONSTRAINT my_constraint ...;
       END IF;
     END $$;
     ```
4. Add a one-line comment at the top of the file explaining the *why* (not the *what* — the SQL describes itself).
5. Run `pnpm test` locally — the schema changes may affect Drizzle types and break compilation in route handlers / tests.
6. Apply locally (`docker compose down -v && docker compose up -d postgres && pnpm db:seed` to recreate from scratch, or run the file directly via `docker compose exec postgres psql`).
7. Open a PR. Once merged to `development`, the next deploy applies it automatically (see [Auto-run](#auto-run)).

## Auto-run

The `web-build-and-push.yaml` workflow runs migrations via a one-off ECS task in each deploy job (dev / qa / prod). Sequence:

1. Build the new image, push to ECR.
2. Update the env's SSM `web-platform-image-tag-{env}` parameter.
3. Register a new task definition revision pointing at the just-pushed image. This step **does not** call `update-service` yet — that is now a later step.
4. **`Run database migrations`** step: pulls the running web-platform service's `networkConfiguration` (subnets, security groups, public-IP setting) so the one-off task lands in the same network path. Calls `aws ecs run-task` with:
   - the new task definition (so SQL files in the new image are present),
   - the same `awsvpcConfiguration` as the service,
   - a container override that runs `node scripts/run-migrations.js` instead of the default `node server.js`.
5. Waits for the task to stop, reads `containers[0].exitCode`. Non-zero → workflow fails, the next step is **skipped**, ECS service is left untouched.
6. **`Update ECS service`** step (only on migration success): `aws ecs update-service --task-definition <new>` flips traffic to the new revision.
7. **`Wait for service stability`** step (unchanged): waits for `services-stable`.

Why this shape:
- The migration runner reads `db/migrations/meta/_journal.json` and `drizzle.__drizzle_migrations`, applies only files not yet recorded, and writes new rows on success. Re-running on an already-up-to-date DB is a no-op.
- Each SQL file is itself idempotent (`IF NOT EXISTS`, `DO`-block constraint guards, `ON CONFLICT` for seeds), so even if `__drizzle_migrations` is somehow out of sync (e.g. dropped manually), re-applying does no harm.
- The migration runs **before** traffic flips. If the schema change isn't compatible with the new code, the migration fails and the old code keeps serving — no half-rolled-out state.
- The runner is `scripts/run-migrations.js`, a self-contained Node script using only `pg` (already in the runtime image, since the app uses it). Drizzle-kit is not in the runtime image and is not needed.

### Required IAM permissions on the GitHub Actions role (`vars.AWS_ROLE`)

The role already had `ecs:DescribeServices`, `ecs:RegisterTaskDefinition`, `ecs:UpdateService`. The new step additionally needs:

- `ecs:RunTask`
- `ecs:DescribeTasks`
- `iam:PassRole` on the task definition's `taskRoleArn` and `executionRoleArn` (usually already granted because `RegisterTaskDefinition` requires it, but worth checking on first failure).

If the first auto-run deploy fails with `AccessDeniedException` on `ecs:RunTask`, add these to the deploy role and retry.

### CloudWatch logs

The migration task writes to the same CloudWatch log group as the web-platform service (`web-platform-{env}`), tagged with the task ARN. To find a specific run's logs:

```sh
aws logs tail web-platform-dev --since 30m --format short \
  --filter-pattern '"Migration task"' \
  --profile AdministratorAccess-455842406405 --region us-east-2
```

## Manual application (fallback / hotfix)

Use this when:
- Auto-run failed and you need to investigate.
- You're applying a one-off DDL not yet captured in a migration file (e.g. an emergency UPDATE in prod — see the `enabled = false` ops we did on 2026-05-04).

### 1. Open a tunnel

```sh
.claude/docs/reference/operations/scripts/bastion-tunnel.sh dev
.claude/docs/reference/operations/scripts/bastion-tunnel.sh qa
.claude/docs/reference/operations/scripts/bastion-tunnel.sh prod
```

Default local port is `5433`. Keep the terminal open.

### 2. Get DB credentials (don't echo to chat)

The keys in the secret are `DATABASE_*`, **not** `DB_*` (the doc was wrong before 2026-05-04).

```sh
.claude/docs/reference/operations/scripts/get-secret.sh mmbr-dev-web-platform DATABASE_USER
.claude/docs/reference/operations/scripts/get-secret.sh mmbr-dev-web-platform DATABASE_PASSWORD
.claude/docs/reference/operations/scripts/get-secret.sh mmbr-dev-web-platform DATABASE_NAME
```

### 3. Connect via DBeaver or psql

| Field | Value |
|---|---|
| Host | `127.0.0.1` (see "IPv4 vs IPv6" gotcha below) |
| Port | `5433` |
| Database | output of `DATABASE_NAME` (currently `mmbr`) |
| Username | output of `DATABASE_USER` |
| Password | output of `DATABASE_PASSWORD` |
| SSL | enabled |

### 4. Apply the migration

For a hand-written migration, paste the SQL inside `BEGIN; ... COMMIT;` and verify with a `SELECT` before committing:

```sql
BEGIN;

ALTER TABLE mmbr.plants
  ADD COLUMN IF NOT EXISTS enabled BOOLEAN NOT NULL DEFAULT true;

SELECT column_name FROM information_schema.columns
 WHERE table_schema = 'mmbr' AND table_name = 'plants';

-- if the column appears: COMMIT
-- if not: ROLLBACK
COMMIT;
```

For an emergency one-off ops query (e.g. data re-pointing) the same pattern applies — wrap in `BEGIN/COMMIT`, verify, then commit.

### 5. Order matters in the manual flow

When deploying code that depends on a migration manually:

```
✅ migration first → then deploy code
❌ deploy code first → then migration
```

The wrong order produces a window where the new code queries a non-existent column → 500s on `/api/<x>` until the migration lands.

For columns added with a DEFAULT value, applying the migration before the deploy is safe: old code ignores the column, new code finds it ready.

## Gotchas

### Local Postgres + tunnel collide on port 5433

`docker-compose.yml` exposes the local Postgres at host port `5433`. The tunnel scripts also default to `5433`. Both can be running at the same time — they bind different stack levels:

- Local Docker: `*:5433` (IPv6, all interfaces)
- SSM tunnel: `127.0.0.1:5433` (IPv4, loopback only)

When clients connect to **`localhost:5433`** the OS resolver may pick either, depending on `/etc/hosts` order and resolver behaviour. macOS commonly prefers `::1` (IPv6) → ends up on the **local Docker**, not the deployed env.

**Always use `127.0.0.1` explicitly** in DBeaver / psql / connection strings when going through a tunnel. This forces IPv4 → SSM tunnel → real env DB.

To verify which DB you're actually on, run:
```sql
SELECT inet_server_addr() AS server_ip, current_database() AS db;
```
A real RDS server returns a 10.x.x.x internal IP. Local Docker returns 127.0.0.1 or 172.x.

### `db-migrate.sh` runs **all** migrations every time

The script (in `scripts/db-migrate.sh`) does not consult any journal. It runs every `*.sql` in `db/migrations/` in lexicographic order. Before the 2026-05-04 idempotency refactor this would fail on the second run with `relation already exists`. After the refactor, it's safe — but still wasteful, since drizzle-kit's `migrate` knows the journal and only runs new files.

Prefer `pnpm db:migrate` (drizzle-kit) over `db-migrate.sh` going forward. The script remains for the rare case where you need to force-replay everything from scratch on an empty DB.

### "Current transaction is aborted" in DBeaver

If a statement inside a `BEGIN;` block fails, Postgres rejects everything afterwards with `25P02 — current transaction is aborted, commands ignored until end of transaction block`. The fix is to close the failed transaction first:

```sql
ROLLBACK;
-- now you can run statements again
```

If you're pasting multiple `SELECT`s into one DBeaver tab, run them **one at a time** rather than all at once. A single bad `SELECT` (e.g. a table that doesn't exist in that env) shouldn't be allowed to invalidate the next two queries.

### `mmbr.conversations` may not exist in older envs

Migration `0004_add_conversations_and_feedback_conversation_id.sql` creates `mmbr.conversations`. Some long-lived QA/prod databases were created before this migration was applied, so a query like `SELECT … FROM mmbr.conversations` errors with `relation does not exist`. Always check `information_schema.tables` first if you're unsure of an env's state:

```sql
SELECT table_name FROM information_schema.tables WHERE table_schema = 'mmbr';
```

### Plant UUIDs vary by env

The dev seed uses fixed UUIDs (`00000000-0000-0000-0000-00000000000{1..4}`) for the four canonical plants. **Production** and **QA** historically used random UUIDs, because plants were created manually before the seed was canonicalised. As of 2026-05-04, QA was reconciled to use the canonical UUIDs (see the dedup procedure in [Plant dedup](#plant-dedup) below).

When writing a migration that touches plants by ID across envs, prefer **`WHERE name = '...'`** over hardcoded UUIDs — names are stable across envs, IDs are not.

## Plant dedup

A QA-specific cleanup we ran on 2026-05-04. Documented here in case it happens again.

Symptoms: two rows in `mmbr.plants` with the same `name`. One is the canonical seeded UUID (`00000000-...-002` for Clairton), the other is a random UUID created earlier when the plant was inserted manually. Conversations and `user_plants` may reference either.

Procedure:

1. **Identify the keeper** — the row with conversations / users attached:
   ```sql
   SELECT p.id, p.name, p.created_at,
          (SELECT COUNT(*) FROM mmbr.user_plants  WHERE plant_id = p.id) AS users,
          (SELECT COUNT(*) FROM mmbr.conversations WHERE plant_id = p.id) AS convos
     FROM mmbr.plants p
    WHERE p.name = '<name>'
    GROUP BY p.id, p.name, p.created_at;
   ```

2. **Re-point all FKs** to the canonical UUID, **then** delete the duplicate:
   ```sql
   BEGIN;
   INSERT INTO mmbr.plants (id, name)
   VALUES ('<canonical-uuid>', '<name>')
   ON CONFLICT (id) DO NOTHING;

   UPDATE mmbr.user_plants  SET plant_id = '<canonical-uuid>'::uuid WHERE plant_id = '<old-uuid>'::uuid;
   UPDATE mmbr.conversations SET plant_id = '<canonical-uuid>'::uuid WHERE plant_id = '<old-uuid>'::uuid;

   DELETE FROM mmbr.plants WHERE id = '<old-uuid>'::uuid;

   SELECT id, name FROM mmbr.plants WHERE name = '<name>';  -- expect 1 row, canonical
   COMMIT;
   ```

Caveat: QAP (qbrick) has its own indexed view of conversations keyed by `plant_id`. Re-pointing the FK in `web-platform` does **not** propagate to QAP — old conversations may "disappear" from QAP's per-plant filter. Confirm whether the historical conversations matter before doing this in any env that has real user data.

## Baseline note

On 2026-05-04 we adopted Drizzle's journal mechanism with the existing 0001–0005 SQL files as the baseline. Specifically:

- The journal `db/migrations/meta/_journal.json` has 5 entries (idx 0–4) tagged `0001_create_mmbr_schema` … `0005_add_plants_enabled`. The corresponding `meta/0004_snapshot.json` represents the schema after migration idx 4 (i.e. the current schema), so `pnpm db:generate` will diff future schema changes against it.
- The runtime `__drizzle_migrations` tracking table is created lazily by `scripts/run-migrations.js` on first execution per env. The first auto-run deploy after this PR will: (a) create the table, (b) attempt to apply all five migrations, (c) succeed with each as a no-op against the already-populated schema (because the SQL is idempotent), (d) record all five hashes. Subsequent deploys skip everything.
- For a brand new env (empty DB), the same pipeline applies 0001–0005 in order, doing real work this time, and ends at the same state.

## Target state vs current state

The pipeline + idempotency + journal achieve "no human in the loop for routine migrations". The remaining manual steps are reserved for situations the runbook explicitly calls out:

- Hand-applied DDL during an incident (rare, with the runbook for guidance).
- One-off ops queries (like the Clairton-only UPDATE we ran on 2026-05-04 — those are not migrations, they are operations).
- Plant dedup or other data reconciliation (procedure above).

## Reference: scripts and config files

- [`web-platform/db/migrations/`](../../../../web-platform/db/migrations/) — SQL files, ordered.
- [`web-platform/db/migrations/meta/_journal.json`](../../../../web-platform/db/migrations/meta/_journal.json) — Drizzle journal of applied migrations (added 2026-05-04).
- [`web-platform/drizzle.config.ts`](../../../../web-platform/drizzle.config.ts) — schema source + journal output path.
- [`web-platform/lib/db/schema.ts`](../../../../web-platform/lib/db/schema.ts) — Drizzle table definitions (single source of truth).
- [`web-platform/.github/workflows/web-build-and-push.yaml`](../../../../web-platform/.github/workflows/web-build-and-push.yaml) — CI/CD with the auto-run step.
- [`scripts/db-migrate.sh`](./scripts/db-migrate.sh) — legacy "run-everything" script, kept for empty-DB scenarios only.
