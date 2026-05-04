---
created: 2026-05-04
updated: 2026-05-04
owner: workspace owner
---

# Connect to a deployed env's Postgres (dev / qa / prod)

The MMBR Aurora cluster sits behind `mmbr-<env>-rds-proxy.proxy-...`. It's private — reachable only via the bastion EC2 over an SSM Session Manager port-forward. This is the canonical path for ad-hoc reads: verifying migrations, debugging data, running one-off SELECTs.

## Prerequisites

- AWS SSO authenticated: `aws sso login --profile <env-profile>`
- `bastion-tunnel.sh` script (`reference/operations/scripts/bastion-tunnel.sh`)
- A Postgres client. Options:
  - **DBeaver** / **TablePlus** (GUI)
  - `psql` (`brew install libpq` ships it)
  - **Node + `pg`** (no install if you're already in `web-platform/`)

## Step 1 — Open the tunnel

```bash
.claude/knowledge/reference/operations/scripts/bastion-tunnel.sh dev
# or: qa, prod
```

Default local port: `5433` → forwards to the env's RDS Proxy on `5432`. Keep the terminal open while you're connected; closing it ends the tunnel.

## Step 2 — Get the credentials

From Secrets Manager (the secret name follows `mmbr-<env>-web-platform`):

```bash
aws secretsmanager get-secret-value \
  --secret-id mmbr-<env>-web-platform \
  --query SecretString --output text \
  | jq -r '. | "host: \(.DATABASE_HOST // .DB_HOST)\nuser: \(.DATABASE_USER // .DB_USER)\ndb:   \(.DATABASE_NAME // .DB_NAME)"'
```

The secret may use either prefix style:

| Style | Keys |
|---|---|
| Compact | `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD` |
| Long | `DATABASE_HOST`, `DATABASE_PORT`, `DATABASE_NAME`, `DATABASE_USER`, `DATABASE_PASSWORD` |
| Single | `DATABASE_URL` (full connection string) |

`lib/runtime-env.ts` resolves either form, DB_* taking precedence. In practice across MMBR envs you'll most often see `DATABASE_*`.

## Step 3 — Connect

### DBeaver / TablePlus

- Host: `localhost`
- Port: `5433`
- Database, User, Password: from the secret
- **SSL: OFF / disabled** (see SSL section below — this is a tunnel artifact)

### psql

```bash
PGPASSWORD='<password>' psql \
  -h localhost -p 5433 \
  -U '<user>' -d '<dbname>' \
  -v ON_ERROR_STOP=1
```

### Node + `pg` (zero install if inside `web-platform/`)

```bash
node -e "
const { Client } = require('pg');
const c = new Client({
  host: 'localhost', port: 5433,
  database: '<db>', user: '<user>', password: '<pass>',
  ssl: false,
});
(async () => {
  await c.connect();
  const r = await c.query('SELECT 1 AS ok');
  console.log(r.rows);
  await c.end();
})().catch(e => { console.error(e); process.exit(1); });
"
```

## SSL: counter-intuitive but important

⚠️ Through the SSM port-forward, **disable SSL on the client side** — even though the RDS Proxy itself enforces TLS in production.

The tunnel terminates locally at `localhost:5433`, where the client's TLS handshake is bound. The proxy expects a TLS client at its own hostname, not at localhost. Either side rejects the cert. Symptoms: `The server does not support SSL connections` (from `pg`) or generic `SSL handshake failed` (from psql).

This is a **tunnel-only** artifact. Production code paths (inside ECS, talking to the real proxy DNS) DO use SSL — see `lib/runtime-env.ts` and `scripts/run-migrations.js`, both of which set `ssl: { rejectUnauthorized: false }` by default.

So:

| Connection path | SSL |
|---|---|
| Local pg client → tunnel → RDS Proxy | **OFF** |
| ECS task → RDS Proxy (production) | **ON** |

## Common verification queries

### Migration state (after migrations-automation rolled out)

```sql
SELECT id,
       LEFT(hash, 12) AS hash_short,
       to_timestamp(created_at / 1000)::timestamptz AS at
FROM drizzle.__drizzle_migrations
ORDER BY id;
```

### Whitelist + plant assignments

```sql
SELECT w.email, w.role, COALESCE(p.name, '—') AS plant
FROM mmbr.whitelist w
LEFT JOIN mmbr.whitelist_plants wp ON wp.whitelist_id = w.id
LEFT JOIN mmbr.plants p             ON p.id = wp.plant_id
ORDER BY w.role, w.email, p.name;
```

### Schema introspection (use this, not `\d`)

`\d` is a psql meta-command. Doesn't work in DBeaver / TablePlus / Node — use `information_schema` and `pg_indexes` instead:

```sql
-- Columns of a table
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'mmbr' AND table_name = '<table>'
ORDER BY ordinal_position;

-- Indexes of a table
SELECT indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'mmbr' AND tablename = '<table>';

-- Foreign keys of a table
SELECT conname, pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conrelid = 'mmbr.<table>'::regclass AND contype = 'f';
```

## Quick liveness checks

```bash
# TCP socket open?
nc -z localhost 5433 && echo "tunnel open" || echo "tunnel closed"

# DB reachable + auth working?
PGPASSWORD='<pass>' psql -h localhost -p 5433 -U '<user>' -d '<db>' \
  -c "SELECT current_database(), current_user, version();"
```

## Tear down

```bash
# Ctrl-C in the bastion-tunnel.sh terminal closes the SSM session
# (no separate cleanup needed)
```

## When NOT to use this

- Running migrations against deployed envs — that's now automated by the deploy pipeline (see `migrations-runbook.md`). Don't run migrations from a tunneled session unless the pipeline is broken.
- Anything that needs to scale or be repeatable — write a script under `reference/operations/scripts/` instead.
- Bulk DML (INSERTs / UPDATEs / DELETEs) on prod — pair with a teammate, document the change, and prefer migrations or seed updates whenever possible.
