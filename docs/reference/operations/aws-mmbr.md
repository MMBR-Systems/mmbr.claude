---
title: AWS Operations — MMBR
created: 2026-04-30
updated: 2026-04-30
---

# AWS Operations — MMBR

How we reach the deployed stack (web-platform, qbrick, backend-ui) running on
ECS in each MMBR AWS account. This is the single source of truth for
profile / cluster / bastion / RDS mappings and the day-to-day recipes.

For first-time AWS SSO setup, see [`../setup/aws-sso-setup.md`](../setup/aws-sso-setup.md).

## Environments

Region is constant across all envs: **`us-east-2`**.

| Env  | Account                      | AWS profile                            | ECS cluster | Web service        | Bastion (EC2)            | RDS Proxy host                                                          |
|------|------------------------------|----------------------------------------|-------------|--------------------|--------------------------|-------------------------------------------------------------------------|
| dev  | MMBR-Knowledge-dev (455842406405)  | `AdministratorAccess-455842406405` | `ecs-dev`   | `web-platform-dev` | `i-0c3297763d5e2f501`    | `mmbr-dev-rds-proxy.proxy-cfq0o6q0ocfv.us-east-2.rds.amazonaws.com`     |
| qa   | MMBR-Knowledge-demo (542035162757) | `AdministratorAccess-542035162757` | `ecs-qa`    | `web-platform-qa`  | `i-0159859cb317ed24d`    | `mmbr-qa-rds-proxy.proxy-cfia6guo0e4z.us-east-2.rds.amazonaws.com`      |
| prod | MMBR-Knowledge-prod (819743217049) | `AdministratorAccess-819743217049` | `ecs-prod`  | `web-platform-prod`| `i-08bbb0ebb0e55dfce`    | `mmbr-prod-rds-proxy.proxy-cbukqk42yxep.us-east-2.rds.amazonaws.com`    |

Each cluster has three services: `web-platform-{env}`, `qbrick-{env}`,
`backend-ui-{env}`. The recipes below target `web-platform-{env}` because
that's where `db/migrations/` and `db/seed.sql` live.

## Prerequisites

- AWS CLI v2
- `session-manager-plugin` for SSM port forwarding and ECS Exec
  (`brew install --cask session-manager-plugin`)
- `aws sso login --profile <profile>` for the env you want to touch

## Recipes

All scripts live under [`scripts/`](./scripts/) and take the env as their
first argument. They source [`_env.sh`](./scripts/_env.sh) to resolve
profile / cluster / bastion / RDS for that env, so adding a new env is one
file edit. Scripts refuse to run if the SSO session for the env is expired
and tell you which `aws sso login` to run.

### DBeaver / psql via the bastion

Open an SSM port-forward to the env's RDS Proxy:

```sh
.claude/docs/reference/operations/scripts/bastion-tunnel.sh qa          # default local port: 5433
.claude/docs/reference/operations/scripts/bastion-tunnel.sh qa 5433     # custom local port
```

Keep the terminal open while you use the connection. DBeaver / psql connect
to `localhost:<local_port>` with `DB_USER` / `DB_PASSWORD` from the env's
web-platform secret in Secrets Manager (e.g. `mmbr-qa-web-platform`).

### Shell into a running container (ECS Exec)

```sh
.claude/docs/reference/operations/scripts/ecs-exec.sh qa                # /bin/sh in web-platform container
.claude/docs/reference/operations/scripts/ecs-exec.sh dev qbrick        # other container in the task
```

The script discovers the running task ID for `web-platform-{env}` and
attaches. Useful for poking at env vars, running ad-hoc node, or inspecting
the filesystem.

### Run migrations against an env

```sh
.claude/docs/reference/operations/scripts/db-migrate.sh qa
```

Runs every `*.sql` under `/app/db/migrations` in lexicographic order, using
the DB credentials from `process.env.SECRETS` inside the container. No
transaction wrapping — for staged dry-run/commit migrations or partial
re-runs, write a one-off command instead of using this script.

### Run seed against an env

```sh
.claude/docs/reference/operations/scripts/db-seed.sh qa
```

`web-platform/db/seed.sql` is idempotent (uses `ON CONFLICT DO ...`), so
re-running is safe and is the supported way to add or fix up seed rows in
a deployed env.

## Reading and updating secrets

Each env has `mmbr-{env}-web-platform` in Secrets Manager. Today the entire
JSON is injected into the task as a single `SECRETS` env var, and the
codebase reads it through [`web-platform/lib/runtime-env.ts`](../../../web-platform/lib/runtime-env.ts)
(`getRuntimeEnv` / `getAuth0Domain`).

Scripts pick the right AWS profile by parsing the env from the secret name
(`mmbr-{env}-...`).

### Read

```sh
# Pretty-print full JSON
.claude/docs/reference/operations/scripts/get-secret.sh mmbr-qa-web-platform

# Single key
.claude/docs/reference/operations/scripts/get-secret.sh mmbr-qa-web-platform DB_HOST
.claude/docs/reference/operations/scripts/get-secret.sh mmbr-prod-backend-ui NEXTAUTH_SECRET
```

### Add or update keys (merge, never replace)

`set-secret-keys.sh` reads JSON from stdin, shows a key-level diff (no
values printed), asks for confirmation, then writes a new version of the
secret. Existing keys not in the input are preserved.

```sh
# Inline
echo '{"AUTH0_BASE_URL":"https://mem-brain.com"}' \
  | .claude/docs/reference/operations/scripts/set-secret-keys.sh mmbr-prod-web-platform

# From a file
.claude/docs/reference/operations/scripts/set-secret-keys.sh mmbr-prod-web-platform < additions.json
```

Direct code reads via `process.env.X` only work for keys that are mapped
individually in the task definition's `secrets` array (`QAP_*` are mapped
this way, most others are not). Anything not mapped must be read through
`getRuntimeEnv`. See PR #36 for the bug this caused on signup/login.

## CloudWatch logs

```sh
# Tail the web-platform-qa log group for the last 30 minutes
aws logs tail web-platform-qa \
  --since 30m --format short \
  --profile AdministratorAccess-542035162757 \
  --region us-east-2

# Filter while tailing
aws logs tail web-platform-qa --since 30m --format short \
  --filter-pattern '"signup"' \
  --profile AdministratorAccess-542035162757 \
  --region us-east-2
```

Log group names match service names: `web-platform-{env}`, `qbrick-{env}`,
`backend-ui-{env}`.

## Force a redeploy

If you only changed a Secrets Manager value (not the task definition),
ECS will not pick it up automatically. Force a new deployment:

```sh
aws ecs update-service \
  --cluster ecs-qa --service web-platform-qa --force-new-deployment \
  --profile AdministratorAccess-542035162757 --region us-east-2 \
  --query 'service.{status:status,desired:desiredCount}' --output json
```

## Adding prod (or a new env)

1. Get the values from a prod operator: account ID, ECS cluster name, web
   service name, bastion EC2 ID, RDS Proxy host.
2. Edit the table at the top of this file.
3. Add the matching `case` branch in [`scripts/_env.sh`](./scripts/_env.sh).
4. Verify with `bastion-tunnel.sh prod` and `ecs-exec.sh prod` before
   trusting `db-migrate.sh prod` or `db-seed.sh prod`.
