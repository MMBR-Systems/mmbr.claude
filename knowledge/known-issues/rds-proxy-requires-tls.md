<!--
Last updated: 2026-04-27
Owner: hpeluzio
-->

# MMBR RDS Proxy requires TLS, and Node `pg` vs Python `asyncpg` use different connection-string syntax

## Symptom

A deployed service connects to `mmbr-<env>-rds-proxy.proxy-cfq0o6q0ocfv.us-east-2.rds.amazonaws.com:5432` using a plain `postgresql://...` connection string with no SSL parameter. Queries fail at the first DB call. The wrapper in the app reports something like `"Failed query: <SQL>"` (Drizzle's wrapper) or `OperationalError`. The underlying driver error is "no pg_hba.conf entry" or "SSL required" depending on the client.

The connection works fine to a local Docker `postgres` container without SSL, masking the issue until first deployment.

## Where

The MMBR Aurora cluster sits behind `mmbr-<env>-rds-proxy` (RDS Proxy). The proxy enforces TLS on the wire. Two services connect through it from ECS:

- `web-platform` (Node, `pg` + Drizzle) → reads `DATABASE_URL` (and falls back to `DB_HOST/PORT/USER/PASSWORD` per `web-platform/lib/runtime-env.ts:55-81`)
- `qbrick` (Python, `asyncpg` + SQLAlchemy) → reads `DATABASE_URI` (per `ai-platform/services/db_manager/settings.py:14-21`)

## Cause

RDS Proxy rejects connections that do not negotiate TLS. The `pg` Node client and `asyncpg` Python client BOTH default to no-SSL unless told otherwise — and they use different parameter names in the connection string.

| Client | URL parameter | Example |
|---|---|---|
| `pg` (Node) | `?sslmode=require` | `postgresql://user:pass@host:5432/mmbr?sslmode=require` |
| `asyncpg` (Python, used via SQLAlchemy `postgresql+asyncpg://...`) | `?ssl=require` | `postgresql+asyncpg://user:pass@host:5432/mmbr?ssl=require` |

Mixing them up looks innocent in code review and breaks at runtime.

In `web-platform/lib/runtime-env.ts:55-81`, the helper `getDatabaseUrl()` returns the `DATABASE_URL` env var verbatim if set. It only adds `?sslmode=require` automatically when it has to construct the URL from `DB_HOST`/`DB_PORT`/etc AND `DB_SSL=true` is set. So a `DATABASE_URL` provided directly without `?sslmode=require` slips through.

## Workaround

For each environment that uses the RDS Proxy, the connection string in AWS Secrets Manager must include the right SSL param:

- `mmbr-<env>-web-platform.DATABASE_URL` ends with `?sslmode=require`
- `mmbr-<env>-qbrick.DATABASE_URI` ends with `?ssl=require`

After updating either secret, force a new ECS deployment so the running task picks up the new value (ECS reads secrets only at task start). See `setup/run-qbrick-alembic-migrations.md` for the redeploy command pattern; same flow for `web-platform-<env>`.

## Fix (if planned)

Two long-term improvements worth considering:

1. **Defensive defaulting on the Node side.** Have `getDatabaseUrl()` parse the URL and inject `?sslmode=require` when the host matches `*.rds.amazonaws.com` and the param is missing. Avoids relying on humans to remember the right syntax.
2. **One env var, one shape, across both services.** Today `DATABASE_URI` (qbrick) and `DATABASE_URL` (web-platform) are independently named and shaped. Aligning on `DATABASE_URL` (the more standard name) and enforcing SSL via a separate `DATABASE_REQUIRE_SSL=true` flag would remove the syntax-mismatch trap entirely.

Neither is currently scheduled. Tracked informally in this doc.

## How to verify

From inside the ECS task (via `aws ecs execute-command`) or local with the bastion port-forward open:

```bash
# Node side
node -e "const {Pool} = require('pg'); const p = new Pool({ connectionString: process.env.DATABASE_URL }); p.query('SELECT 1').then(r => console.log('OK', r.rows)).catch(e => console.error('FAIL', e.message)).finally(() => p.end())"

# Python side
python3 -c "import asyncio, asyncpg; asyncio.run(asyncpg.connect('${DATABASE_URI}'))"
```

If the URL is missing the right SSL param, both will fail with TLS-related errors.
