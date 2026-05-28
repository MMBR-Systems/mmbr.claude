---
created: 2026-05-27
updated: 2026-05-27
owner: hpeluzio
---

# ai-platform CI/CD does not run alembic on deploy

## Symptom

After a release that ships a new alembic migration on `ai-platform/` (the qbrick service), the new code starts hitting the env's Postgres expecting columns/tables that don't exist. Symptom in `qbrick-{env}` CloudWatch logs:

```
(sqlalchemy.dialects.postgresql.asyncpg.ProgrammingError)
<class 'asyncpg.exceptions.UndefinedColumnError'>:
column conversation_messages.<new_col> does not exist
```

Users see "The assistant couldn't respond. Please try again." in the chat UI. Any route that touches the affected model returns 500.

## Where

- Workflow: `ai-platform/.github/workflows/api-build-and-push.yaml` (deploy-dev / deploy-qa / deploy-prod jobs, ~565 lines total)
- Container image: `ai-platform/api/Dockerfile.release` (CMD is `python cli.py api-server`, no alembic step)
- Local-only counterpart that *does* run alembic: `ai-platform/api/local-entrypoint.sh` (`uv run alembic upgrade head`)

## Cause

The three deploy jobs (dev/qa/prod) do, in order: checkout → AWS creds → buildx → ECR login → build+push → SSM tag update → register new task definition → `update-service` → wait stable → publish summary. **No step launches a one-off ECS task to run `alembic upgrade head` before the service update.**

The `alembic/**` paths under `on.pull_request.paths` and `on.push.paths` are trigger filters only (they decide *when* the workflow runs, not *what* it does). They do not execute migrations.

For comparison, `web-platform/.github/workflows/web-build-and-push.yaml` has a `Run database migrations` step in each deploy job that:
1. Reads the running service's `networkConfiguration` via `describe-services`.
2. Calls `aws ecs run-task` with the **new** task definition plus a container override of `["node", "scripts/run-migrations.js"]`.
3. `aws ecs wait tasks-stopped`, then reads `containers[0].exitCode`. Non-zero → `exit 1` → service update step is skipped, traffic stays on the old revision.

The ai-platform pipeline has none of this. Result: image and code go live, schema stays behind, prod breaks until someone runs alembic manually.

## How to verify quickly

For any deployed env, exec into the qbrick task and compare current vs head:

```sh
TASK=$(aws ecs list-tasks --cluster ecs-prod --service-name qbrick-prod \
  --profile AdministratorAccess-819743217049 --region us-east-2 \
  --query 'taskArns[0]' --output text | awk -F/ '{print $NF}')

script -q /dev/null aws ecs execute-command \
  --cluster ecs-prod --task "$TASK" --container qbrick \
  --interactive \
  --command "sh -c 'cd /app && alembic current 2>&1; echo === HEADS ===; alembic heads 2>&1; exit'" \
  --profile AdministratorAccess-819743217049 --region us-east-2
```

If `alembic current` < `alembic heads`, the env is behind. See [`reference/operations/qbrick-alembic-migrate.md`](../reference/operations/qbrick-alembic-migrate.md) for the manual upgrade procedure.

## Workaround

Run `alembic upgrade head` manually against the affected env's qbrick container immediately after any release that ships a migration. Procedure: [`reference/operations/qbrick-alembic-migrate.md`](../reference/operations/qbrick-alembic-migrate.md).

Order matters: schema first, then traffic. If the new code is already live (which is the case for any release that triggered this incident), apply the migration ASAP — the column addition is non-blocking for nullable columns, so it's safe under traffic.

## Fix (planned)

Mirror the web-platform pattern in `api-build-and-push.yaml`: add a `Run database migrations` step between "Register new task definition" and "update-service", using `aws ecs run-task` with override `["sh", "-c", "cd /app && alembic upgrade head"]`. Same image, same task definition, same network config as the running service. Non-zero exit → block service update.

No ticket yet — incident on 2026-05-27 (column `conversation_messages.plant_id` missing in prod) was the trigger.

## Related

- [`reference/operations/qbrick-alembic-migrate.md`](../reference/operations/qbrick-alembic-migrate.md) — manual procedure (current workaround until pipeline gap is closed)
- [`reference/operations/migrations-runbook.md`](../reference/operations/migrations-runbook.md) — web-platform's auto-run setup; the model to copy
