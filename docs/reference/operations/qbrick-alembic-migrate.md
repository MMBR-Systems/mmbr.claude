---
created: 2026-05-27
updated: 2026-05-27
owner: hpeluzio
---

# qbrick Alembic — Manual Migration Runbook

How to run alembic migrations against a deployed `qbrick-{env}` service when the CI/CD pipeline did not (see [`known-issues/ai-platform-ci-cd-no-alembic-step.md`](../../known-issues/ai-platform-ci-cd-no-alembic-step.md)). Use this for incidents and ad-hoc upgrades until the pipeline gap is closed.

For web-platform (Drizzle, Node) migrations, see [`migrations-runbook.md`](./migrations-runbook.md) — different repo, different runner, mostly automatic.

For AWS connectivity basics (profiles, clusters, bastions), see [`aws-mmbr.md`](./aws-mmbr.md).

## When to use this

- Prod is broken with `UndefinedColumnError` / `UndefinedTableError` from asyncpg, immediately after a release.
- A QA deploy of a feature that ships a migration needs the schema to land before manual testing.
- Verifying alembic state in an env (read-only — same commands, just `alembic current`/`heads`).

## Pre-reqs

- AWS CLI v2, `session-manager-plugin` (`brew install --cask session-manager-plugin`).
- SSO session active for the env's profile (`aws sso login --profile <profile>`).
- `script` is part of macOS base (no install). Required to allocate a PTY — `aws ecs execute-command` rejects piped/null stdin with `Cannot perform start session: EOF`.

## Env → profile table

| Env | AWS profile | ECS cluster | Service | Account |
|---|---|---|---|---|
| dev | `AdministratorAccess-455842406405` | `ecs-dev` | `qbrick-dev` | 455842406405 |
| qa | `AdministratorAccess-542035162757` | `ecs-qa` | `qbrick-qa` | 542035162757 |
| prod | `AdministratorAccess-819743217049` | `ecs-prod` | `qbrick-prod` | 819743217049 |

Region is always `us-east-2`. Container name inside the task is `qbrick`.

## Procedure

### 1. Resolve the running task

```sh
ENV=prod   # or qa, dev
PROFILE=AdministratorAccess-819743217049   # match ENV
CLUSTER=ecs-${ENV}

TASK=$(aws ecs list-tasks \
  --cluster "$CLUSTER" --service-name "qbrick-${ENV}" \
  --profile "$PROFILE" --region us-east-2 \
  --query 'taskArns[0]' --output text | awk -F/ '{print $NF}')

echo "$TASK"
```

If empty, the service has no running tasks — investigate before migrating.

### 2. Diagnostic (read-only)

Confirm the env's actual alembic state before any write. Always do this first.

```sh
script -q /dev/null aws ecs execute-command \
  --cluster "$CLUSTER" --task "$TASK" --container qbrick \
  --interactive \
  --command "sh -c 'cd /app && alembic current 2>&1; echo === HEADS ===; alembic heads 2>&1; exit'" \
  --profile "$PROFILE" --region us-east-2
```

Expected output:

```
INFO  [alembic.runtime.migration] Context impl PostgresqlImpl.
INFO  [alembic.runtime.migration] Will assume transactional DDL.
<revision_id>
=== HEADS ===
<revision_id> (head)
```

If `current == head`, the env is up to date — no migration needed. Stop here.

If `current` < `head`, the env is behind. Continue to step 3.

> **PTY note.** Without `script`, the SSM session terminates immediately with `Cannot perform start session: EOF`. `script -q /dev/null <cmd>` allocates a pseudo-TTY and discards the typescript file, which is enough for `aws ecs execute-command --interactive`.

### 3. Apply migrations

For QA / dev, run directly.

For **prod**, get user confirmation first (this is a shared-state write — same rule as `db-migrate.sh prod` in [`aws-mmbr.md`](./aws-mmbr.md)).

```sh
script -q /dev/null aws ecs execute-command \
  --cluster "$CLUSTER" --task "$TASK" --container qbrick \
  --interactive \
  --command "sh -c 'cd /app && alembic upgrade head 2>&1; echo === POST-CURRENT ===; alembic current 2>&1; exit'" \
  --profile "$PROFILE" --region us-east-2
```

Expected output (per pending revision):

```
INFO  [alembic.runtime.migration] Running upgrade <from> -> <to>, <slug>
...
=== POST-CURRENT ===
<head_revision> (head)
```

### 4. Verify the fix

CloudWatch tail for the same error pattern, last 5 minutes:

```sh
aws logs tail "qbrick-${ENV}" --since 5m --format short \
  --filter-pattern '"UndefinedColumn"' \
  --profile "$PROFILE" --region us-east-2
```

Empty output is good. Also tail unfiltered for ~1 min to confirm normal traffic resumed:

```sh
aws logs tail "qbrick-${ENV}" --since 2m --format short \
  --profile "$PROFILE" --region us-east-2 | tail -20
```

Look for `200 OK` on chat/conversation routes.

## Safety notes

- **DATABASE_URI prints to the session.** When `aws ecs execute-command` connects, qbrick's container has already logged its `DATABASE_URI` (with embedded password) to stdout, and the SSM session replays the recent log buffer. Don't paste that line into Slack / PRs. Pipe through `grep -v 'DATABASE_URI'` if sharing output.
- **`alembic upgrade head` runs everything pending.** If the env is multiple revisions behind, all of them run in one shot. Read each `Running upgrade <from> -> <to>` line in the output — that's your audit trail.
- **Non-blocking is the norm.** Most MMBR alembic migrations are `ADD COLUMN ... nullable=True` — Postgres does not rewrite the table, so they are safe under traffic. Verify by reading the migration file before running. If a migration does `ALTER COLUMN ... SET NOT NULL` on a populated table, or rewrites data, treat it as a higher-risk op and coordinate first.
- **Lock contention.** Alembic acquires a transactional lock on `alembic_version`. If two operators run `upgrade` simultaneously, the second waits. Don't kill it — let it block.
- **Rollback.** If a migration fails partway, alembic transactional DDL means Postgres rolls back the failed revision automatically (column not added). The `alembic_version` row stays at the last successful revision. Re-running `upgrade head` after fixing the migration file is safe.

## When this becomes obsolete

When `ai-platform/.github/workflows/api-build-and-push.yaml` gains a `Run database migrations` step modeled on `web-platform`'s (one-off `aws ecs run-task` with `["sh", "-c", "alembic upgrade head"]` override, blocking service update on non-zero exit), this runbook becomes incident-only — kept as a fallback when the auto-run itself fails.

## Reference

- [`known-issues/ai-platform-ci-cd-no-alembic-step.md`](../../known-issues/ai-platform-ci-cd-no-alembic-step.md) — the gap this runbook works around.
- [`migrations-runbook.md`](./migrations-runbook.md) — web-platform equivalent (Drizzle, Node, auto-run already in place).
- [`aws-mmbr.md`](./aws-mmbr.md) — env → profile / cluster / bastion mappings.
- `ai-platform/alembic/versions/*.py` — migration files. Read before applying.
- `ai-platform/api/Dockerfile.release` — confirms the boot path has no alembic step.
- `ai-platform/.github/workflows/api-build-and-push.yaml` — confirms CI/CD has no alembic step.
