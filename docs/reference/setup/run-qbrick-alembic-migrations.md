<!--
Last updated: 2026-04-27
Owner: hpeluzio
-->

# Run qbrick alembic migrations on a deployed environment

Apply pending Alembic migrations to a qbrick database in `dev`, `qa`, or `prod`. The migrations live at `ai-platform/alembic/versions/`.

## Prerequisites

- AWS CLI installed
- `aws sso login` already done
- AWS profile for the target environment (dev: `AdministratorAccess-455842406405`)
- ECS `enableExecuteCommand` must be `true` on the qbrick service (see step 1)
- `mmbr-dev-qbrick.DATABASE_URI` must point at the real RDS proxy (not docker-compose defaults). See `.claude/docs/known-issues/qbrick-dev-secret-template-defaults.md`.

## Steps (dev)

```bash
export AWS_PROFILE=AdministratorAccess-455842406405
```

### 1. Confirm execute-command is enabled

```bash
aws ecs describe-services --cluster ecs-dev --services qbrick-dev \
  --query 'services[0].enableExecuteCommand' --output text
```

Expected: `True`. If `False`, enable it and force a redeploy:

```bash
aws ecs update-service --cluster ecs-dev --service qbrick-dev \
  --enable-execute-command --force-new-deployment
```

Wait until the new deployment reaches `COMPLETED` (~2 min):

```bash
aws ecs describe-services --cluster ecs-dev --services qbrick-dev \
  --query 'services[0].deployments[0].[rolloutState,runningCount]' --output text
```

### 2. Open a shell inside the running qbrick container

```bash
TASK=$(aws ecs list-tasks --cluster ecs-dev --service-name qbrick-dev \
  --query 'taskArns[0]' --output text)

aws ecs execute-command --cluster ecs-dev --task "$TASK" \
  --container qbrick --interactive --command "/bin/bash"
```

If the container does not have bash, try `/bin/sh`.

### 3. Inspect current state (inside the container)

```bash
# revision currently applied to the DB
alembic current

# revision the code expects (head of the migration tree)
alembic heads

# full migration history with descriptions
alembic history --verbose
```

If `current` and `heads` match, there is nothing to do. Otherwise, the gap between them is what will be applied.

### 4. (Optional but recommended) Preview the SQL

```bash
alembic upgrade head --sql > /tmp/pending.sql
cat /tmp/pending.sql
```

`--sql` prints the SQL that would be executed without running it. Review before applying.

### 5. Apply migrations

```bash
alembic upgrade head
```

Output is one `INFO ... Running upgrade <prev> -> <next>, <description>` line per migration applied.

### 6. Verify

```bash
alembic current
```

Should now match `alembic heads`.

Exit the container shell:

```bash
exit
```

## QA equivalent

Same sequence with the QA profile and cluster:

```bash
export AWS_PROFILE=AdministratorAccess-542035162757   # MMBR-Knowledge-demo
# replace cluster name and service name with the QA equivalents
```

Confirm the cluster name first:

```bash
aws ecs list-clusters --query 'clusterArns' --output text
```

## Rollback

To revert a single migration:

```bash
alembic downgrade -1
```

To revert to a specific revision:

```bash
alembic downgrade <revision-id>
```

Rollback runs the `downgrade()` function defined in each migration file. Some destructive migrations (drop column, drop table) cannot be reverted to their original state, only the schema is restored. Treat rollback as a recovery tool, not a routine workflow.

## Common errors

| Error | Cause | Fix |
|---|---|---|
| `relation "alembic_version" does not exist` | DB has no migration history table; never been initialized | First run: `alembic upgrade head` will create it |
| `Can't locate revision identified by 'X'` | Local code does not include the revision recorded in DB. Migration file deleted or branch switch | Pull the right code branch, or stamp the DB with `alembic stamp <revision-id>` if you know what you are doing |
| `password authentication failed` | `DATABASE_URI` in the secret has wrong credentials | Fix `mmbr-<env>-qbrick.DATABASE_URI` and force redeploy before retrying |
| `Name or service not known` | DB host in `DATABASE_URI` does not resolve from inside ECS | Same fix as above; the host must be the RDS proxy endpoint |

## What gets created when migrations run end-to-end

Reference of the 17 migrations and what each adds. Useful for predicting what will appear in the DB:

| File | Adds |
|---|---|
| `d8f418e0ecdd_initial_version` | Base schema |
| `f1299bf1f5a5_users_table_created` | `users` table (required for login) |
| `f49b8599b63f_add_conversation_history` | `conversations`, `messages` |
| `f97e4fd7be33_add_user_to_conversation` | `conversations.user_id` |
| `da839dfe355e_add_api_keys_and_published_status` | `api_keys`, workflow status (required for RAG agent creation) |
| `c8a3d923c9c4_add_user_to_wd` | `workflow_descriptions.user_id` |
| `a1b2c3d4e5f6_drop_user_id_from_workflow_descriptions` | reverts the column |
| `b58f157f1e63_add_published_at_to_workflows` | workflow publishing |
| `8c35ca43d2c4_add_direct_inputs_to_workflows` | workflow inputs |
| `8a1b2c3d4e5f_add_judges_and_evaluators` | evaluators (RAG eval) |
| `0e964c596664_add_sample_rate_to_evaluators` | evaluator tuning |
| `ebe94c4aac7c_createdby_field_added_into_jugdges` | judge audit |
| `f1a285v7aad6_add_google_drive_tables` | Google Drive integration |
| `31a109f6ad6c_file_management_migrations` | file management |
| `e8e3769c525f_add_last_executed_at_to_workflow_` | workflow tracking |
| `75c068edac12_drop_flow_position_column` | cleanup |
| `67fd23164ccd_fix_wrong_router_reference_in_flowsteps` | schema fix |
