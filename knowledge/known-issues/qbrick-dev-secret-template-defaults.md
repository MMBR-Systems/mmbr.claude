<!--
Last updated: 2026-04-27
Owner: hpeluzio
-->

# qbrick dev was deployed with unmodified `.env.api.example` defaults

## Symptom

Login at https://ui.dev.mem-brain.com/login fails with `Error: AccessDenied` after Google consent. The visible error is the same regardless of which underlying layer is broken, so debugging requires reading `qbrick-dev` CloudWatch logs (the qap-ui `signIn` callback returns `false` whenever qbrick's `/auth/login` returns non-OK or a body with `success: false`, which collapses every backend failure into the same "AccessDenied" surface).

Underlying log lines vary as each layer is fixed:

1. `[Errno -2] Name or service not known` — DNS failure (qbrick can't resolve the DB host)
2. `The password that was provided for the role postgres is wrong` — auth failure
3. `relation "users" does not exist` — DB connected but schema is empty

## Where

- AWS Secrets Manager (us-east-2 / account `455842406405`): `mmbr-dev-qbrick`
- Source template: `ai-platform/.env.api.example`
- ECS task definition `dev-qbrick:N` pulls **every** env var from `mmbr-dev-qbrick` via `valueFrom` with no overrides. The secret is ground truth.
- qbrick startup code that consumes the bad values:
  - `ai-platform/api/config.py:9` — reads `API_HOST`, `API_PORT` (Pydantic Settings, `env_prefix="API_"`)
  - `ai-platform/services/db_manager/settings.py:14-21` — reads `DATABASE_URI` directly via `os.getenv`

## Cause

When dev was provisioned, the upstream `ai-platform/.env.api.example` template was copied verbatim into `mmbr-dev-qbrick` without adapting to AWS values. Concrete misconfigurations and their effect:

| Var in secret | Bad value | Why it broke |
|---|---|---|
| `API_HOST` | `localhost` | uvicorn binds to 127.0.0.1; qap-ui's POST through ECS Service Connect cannot reach the container |
| `DATABASE_URI` | `postgresql+asyncpg://qap_api_dev:qap_api_dev@postgres:5432/qap_api_dev` | hostname `postgres` is the docker-compose service name; does not resolve in ECS DNS. Even with the host fixed, password and DB name were also wrong |
| `CORS_ORIGINS` | `http://localhost:3000,http://localhost:3001,http://localhost:8080` | excludes `https://ui.dev.mem-brain.com`. Does not affect server-to-server calls but blocks any browser-direct call |
| `GOOGLE_OAUTH_CALLBACK_URL`, `GOOGLE_OAUTH_CLIENT_ID`, `GOOGLE_OAUTH_CLIENT_SECRET` | dev-local values | dead vars; nothing in `ai-platform/api`, `ai-platform/services`, or `qap-ui/src` reads them. Only `.env.api.example` references these names. They look authoritative but are noise |
| `POSTGRES_HOST`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DATABASE`, `POSTGRES_PORT`, `POSTGRES_MAX_CONNECTIONS` | docker-compose values | dead vars; qbrick reads only `DATABASE_URI` for DB connection. Code search confirms zero `os.getenv("POSTGRES_*")` and no Pydantic field with `postgres_*` names |

A consequence: because `DATABASE_URI` never resolved, `alembic upgrade head` never ran against the real Aurora dev DB. The `users` table (and the rest of the qbrick schema) does not exist in the `mmbr` database.

The real master password lives in the RDS-managed secret `rds!cluster-ef7f688c-71de-45ad-bf80-032abc245070` (auto-created when the Aurora cluster was provisioned with secrets-manager-managed master credentials).

## Workaround / Fix status

Sequence applied during 2026-04-27 debugging session:

1. `mmbr-dev-qbrick.API_HOST` set to `0.0.0.0` so uvicorn accepts Service Connect traffic.
2. `mmbr-dev-qbrick.DATABASE_URI` replaced with `postgresql+asyncpg://postgres:<URL_ENCODED_MASTER_PASSWORD>@mmbr-dev-rds-proxy.proxy-cfq0o6q0ocfv.us-east-2.rds.amazonaws.com:5432/mmbr?ssl=require`. Master password sourced from the RDS-managed secret.
3. `aws ecs update-service --cluster ecs-dev --service qbrick-dev --force-new-deployment` to make the task pick up the new secret values (ECS reads secrets at container start, not on update).
4. Ran `alembic upgrade head` inside the qbrick container via `aws ecs execute-command`. All 17 migrations applied from scratch — the dev `mmbr` DB had no schema at all before this (alembic started at empty, `-> d8f418e0ecdd` Initial Version). Procedure documented at `.claude/knowledge/reference/setup/run-qbrick-alembic-migrations.md`.

Cleanup deferred but recommended: remove the dead vars (`GOOGLE_OAUTH_*`, `POSTGRES_*`) from `mmbr-dev-qbrick`, and clean the same lines out of `.env.api.example` so the template stops advertising vars the code does not consume.

## How to verify

```bash
export AWS_PROFILE=AdministratorAccess-455842406405

# 1. confirm secret values currently in dev
aws secretsmanager get-secret-value --secret-id mmbr-dev-qbrick \
  --query 'SecretString' --output text | jq '.API_HOST, .DATABASE_URI'

# 2. confirm task def has no overrides hiding the secret values
aws ecs describe-task-definition --task-definition dev-qbrick \
  --query 'taskDefinition.containerDefinitions[0].environment'
# should be [] (everything comes from secrets)

# 3. tail qbrick-dev logs while clicking "Continue with Qubika SSO" in incognito
aws logs tail qbrick-dev --follow --since 1m
```

## Related

- `mmbr-dev-backend-ui` had a `DB_PASSWORD` value that does not match the actual postgres role. qap-ui code does not read `DB_*` env vars, so nobody noticed. If any sidecar or external script consumes those, it would be silently broken. Worth auditing alongside this fix.
- `mmbr-dev-web-platform` shows similar template-defaults shape (`DATABASE_HOST=localhost`, `DATABASE_PORT=5433`, `DATABASE_PASSWORD=mmbr_password`, `DEV_BYPASS_AUTH=true`). Either web-platform task definition overrides these at runtime, or web-platform in dev runs in bypass-auth mode without a real DB. Verify before assuming web-platform is fully wired.
- Architecture context for the auth flow: `architecture/auth-flow.md`, `external-apis/qap-auth-layers.md`.
