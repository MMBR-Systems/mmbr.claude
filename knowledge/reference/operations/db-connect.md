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

- Host: `127.0.0.1` (**not** `localhost` — see Gotcha 1 below)
- Port: `5433`
- Database, User, Password: from the secret
- **SSL: `require`, "Verify CA" / cert validation OFF** (see Gotcha 2 below)

### psql

```bash
PGPASSWORD='<password>' psql \
  "host=127.0.0.1 port=5433 dbname=<db> user=<user> sslmode=require" \
  -v ON_ERROR_STOP=1
```

### Node + `pg` (zero install if inside `web-platform/`)

```bash
node -e "
const { Client } = require('pg');
const c = new Client({
  host: '127.0.0.1', port: 5433,
  database: '<db>', user: '<user>', password: '<pass>',
  ssl: { rejectUnauthorized: false },
});
(async () => {
  await c.connect();
  const r = await c.query('SELECT 1 AS ok');
  console.log(r.rows);
  await c.end();
})().catch(e => { console.error(e); process.exit(1); });
"
```

## Gotcha 1 — use `127.0.0.1`, not `localhost`

If the workspace's `docker-compose.yml` binds a local Postgres to the same port as the tunnel (commonly `5433`, since `5432` is usually owned by the local Postgres for another service), you'll have **two listeners on port 5433**:

- Docker Postgres on `0.0.0.0:5433` and `[::]:5433` (wildcard, IPv4 + IPv6)
- SSM tunnel on `127.0.0.1:5433` (IPv4 loopback only)

When a client connects to `localhost`, macOS resolves it via `getaddrinfo` and may prefer `::1` (IPv6) — which routes to **Docker**, not the tunnel. Symptom: `password authentication failed for user "postgres"` (Docker Postgres has different creds than the dev env) and/or `The server does not support SSL connections` (the local container has no TLS).

**Fix:** always use the literal `127.0.0.1` in the host field. That forces IPv4 and routes to the SSM tunnel's specific binding (which beats the wildcard for `127.0.0.1` connections).

Verify with:

```bash
lsof -nP -iTCP:5433 -sTCP:LISTEN
# Expect both:
#   com.docke ... *:5433        (local Docker, wildcard)
#   session-manager ... 127.0.0.1:5433  (the tunnel)
```

If only one listener appears, no conflict — `localhost` is fine.

## Gotcha 2 — SSL through the tunnel: required, but with cert verification disabled

The dev RDS Proxy speaks TLS even through the SSM port-forward. You **need** SSL on the client side, but **certificate verification fails** because the cert is presented for the proxy's real DNS name (`mmbr-<env>-rds-proxy.proxy-...`), and the client is bound to `127.0.0.1`. Disable verification on the client side to bypass the hostname mismatch.

| Client | Setting |
|---|---|
| DBeaver / TablePlus | SSL = `require`, "Verify CA" = OFF |
| psql | `sslmode=require` (does not verify by default) |
| Node `pg` | `ssl: { rejectUnauthorized: false }` |

Symptoms when SSL is misconfigured:

- `ssl: false` (off) → `password authentication failed` — the proxy rejects non-SSL connections; pg interprets the close as auth failure
- `ssl: true` (verified) → SSL handshake fails: cert hostname mismatch
- `ssl: { rejectUnauthorized: false }` → ✅ works

Production code (inside ECS, hitting the real proxy DNS directly) uses the same `rejectUnauthorized: false` pattern — see `lib/runtime-env.ts` and `scripts/run-migrations.js`. The tunnel doesn't change SSL behavior; what changes is the client-side host name (which is why CA verification fails locally).

| Connection path | SSL setting |
|---|---|
| Local pg client → tunnel → RDS Proxy | `require` + verification OFF |
| ECS task → RDS Proxy (production) | `require` + verification OFF (same; cert is self-signed by AWS internal CA) |

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
