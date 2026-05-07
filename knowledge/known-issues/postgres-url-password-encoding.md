---
created: 2026-05-07
updated: 2026-05-07
owner: workspace owner
---

# Postgres connection URL passwords must be URL-encoded

## Symptom

App fails to connect to Postgres with one of several confusing errors, depending on which character in the password broke the URL parser:

- `TypeError: Invalid URL` / `code: 'ERR_INVALID_URL'` — Node `pg` rejecting the connection string outright.
- `error: The password that was provided for the role postgres is wrong` — parser truncated the password at a special character, sent the truncated value to Postgres, auth fails.
- Pool returns connection but queries fail with `password authentication failed for user "postgres"`.
- `error: This RDS Proxy requires TLS connections` if the parser ate `?sslmode=require` from the end (it was tucked behind a `?` inside the password).

The error never says "your password isn't URL-encoded" — the symptom looks like wrong password, wrong host, malformed URL, missing TLS, or invalid syntax depending on which char broke things.

## Where

Anywhere a Postgres connection URL is hand-built or stored as-is in Secrets Manager:

- `mmbr-<env>-web-platform.DATABASE_URL` — consumed by Node `pg` via `lib/runtime-env.ts:getDatabaseUrl()` and `lib/db.ts`.
- `mmbr-<env>-qbrick.DATABASE_URI` — consumed by Python `asyncpg` via `services/db_manager/settings.py`.
- `mmbr-<env>-backend-ui.DATABASE_URL` / `DATABASE_URI` — same.
- Anywhere `scripts/run-migrations.js` reads from (`SECRETS.DATABASE_URL` or fallback decomposed).

The risk is highest after **password rotation** — RDS-managed master credentials regenerate to random strings that frequently include reserved URL characters.

## Cause

URLs reserve a specific set of characters for structural meaning. Inside the user-info segment (`user:password@host`), these reserved chars **must** be percent-encoded or the parser misinterprets them:

| Char | Encoded | Why it breaks |
|---|---|---|
| `:` | `%3A` | Splits user from password (and host from port). A raw `:` inside the password makes the parser think it's the user/pass separator. |
| `?` | `%3F` | Marks start of query string. A raw `?` in the password truncates the password and treats the rest as `?key=value` query params (and may eat `?sslmode=require` from the actual end of the URL). |
| `@` | `%40` | Separates user-info from host. A raw `@` in the password makes the parser think the host starts mid-password. |
| `/` | `%2F` | Path separator. Less catastrophic but still breaks parsing in some clients. |
| `#` | `%23` | Fragment marker. Truncates the URL at that point. |
| `(` `)` `[` `]` | `%28` `%29` `%5B` `%5D` | Reserved per RFC 3986. Some clients tolerate, others (Node `pg`) don't. |
| `*` `+` `<` `>` `~` `!` `$` `&` `'` `,` `;` `=` `space` | various | Reserved or unsafe in URL. |

Unreserved chars (ALWAYS safe raw): `A-Z`, `a-z`, `0-9`, `-`, `.`, `_`, `~`.

Backend-ui's `DATABASE_URI` is the canonical reference in this workspace — its password is correctly URL-encoded (`%29YVF5QqJq9%3AzJGVm...`) and it's worked across rotations. Match that pattern.

## Workaround

When writing or rotating a Postgres URL by hand, **always URL-encode the password**. Don't trust copy-paste from password generators or RDS console.

In Python:

```python
import urllib.parse
encoded_pw = urllib.parse.quote(raw_password, safe='')
url = f'postgresql://{user}:{encoded_pw}@{host}:{port}/{db}?sslmode=require'
```

In Node:

```js
const encoded = encodeURIComponent(rawPassword);
const url = `postgresql://${user}:${encoded}@${host}:${port}/${db}?sslmode=require`;
```

In bash (one-off):

```bash
ENCODED=$(python3 -c "import urllib.parse, sys; print(urllib.parse.quote(sys.argv[1], safe=''))" "$RAW_PASSWORD")
```

When updating a Secrets Manager entry, do this in a script (not by typing into the console), so the encoding is consistent and the password never appears as a literal in your shell history.

To validate after the fact (without exposing the password):

```python
from urllib.parse import urlparse
u = urlparse(DATABASE_URL)
assert u.username == 'postgres'
assert u.password == raw_password  # urlparse decodes — round-trip should match raw
```

If `u.password != raw_password`, the URL was malformed (parser interpreted something other than the password as the password segment).

## Fix (if planned)

No code fix planned — this is RFC behavior, not a bug in any client. Mitigations to consider:

- Wrapper script under `reference/operations/scripts/` that takes `(host, port, db, user, password)` and outputs a correctly-encoded URL, used by anyone updating a Postgres secret.
- Pre-deploy validation that round-trips `urlparse` on `DATABASE_URL` and fails the rollout if `parsed.password != expected`. Catches accidentally-edited URLs.
- Convention: prefer the **decomposed** keys (`DATABASE_HOST`, `DATABASE_USER`, etc.) and let `getDatabaseUrl()` build the URL. The helper handles encoding correctly. Only use `DATABASE_URL` when the consumer can't compose its own.

Until any of those land, anyone editing a Postgres URL by hand should consult this doc and run the round-trip check.
