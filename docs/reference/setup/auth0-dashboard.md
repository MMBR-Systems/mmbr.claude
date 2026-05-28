# Auth0 Dashboard - Adding an Environment

The MMBR stack uses a single Auth0 tenant across `dev`, `qa`, and `prod`. Each environment's URL must be appended (not replaced) on the Application configuration, otherwise Auth0 rejects the OAuth redirect and login silently fails.

## Tenant and application

- **Tenant:** `dev-oasbmd2tfc8nw8de.us.auth0.com` (shared across all environments)
- **Application client id:** `qRh8dAtq6XMt8hsjDnkPPVPXyCFWfKCj`
- **Dashboard access:** Auth0 tenant admin. If you do not have it, the current owners are on the Qubika side.

## Fields to update

For every new environment URL, append the value to all four fields (comma-separated). Never replace - other environments rely on their entries.

| Field | Value to append |
|---|---|
| Allowed Callback URLs | `https://<env>.mem-brain.com/auth/callback` |
| Allowed Logout URLs | `https://<env>.mem-brain.com` |
| Allowed Web Origins | `https://<env>.mem-brain.com` |
| Allowed Origins (CORS) | `https://<env>.mem-brain.com` |

For local development, keep `http://localhost:3001/*` entries in all four fields too.

## Sanity checks after saving

```bash
# Should 302 to dev-oasbmd2tfc8nw8de.us.auth0.com/authorize
curl -sI https://<env>.mem-brain.com/auth/login

# Should 200 and serve the custom MMBR login form
curl -sI https://<env>.mem-brain.com/login
```

If `/auth/login` returns 404 or the redirect target is wrong, the most likely causes are:

1. `AUTH0_BASE_URL` in the environment's secret does not match the URL you hit. It must be exact.
2. The Auth0 dashboard is missing the callback URL for this environment. Auth0 returns a generic error HTML page that the web-platform can't process, and the proxy's silent catch in `web-platform/proxy.ts` turns the result into a 404 for `/auth/*` routes.
3. The `HEAD` method returns 404 on `/auth/login` but `GET` returns 302. This is normal behavior for the Auth0 Next.js SDK v4. Use `GET` to verify.

## Two login surfaces on web-platform

MMBR web-platform exposes two login entry points, both valid:

| Route | Form | Auth0 flow used |
|---|---|---|
| `/login` | Custom MemBrain-branded form | Resource Owner Password Grant (`POST /api/auth/login` backs it) |
| `/auth/login` | Auth0 Universal Login (no MemBrain branding) | Authorization Code. Used internally by the social login buttons (Google/Microsoft) on the `/login` form, which redirect to `/auth/login?connection=...`. |

Users reaching `/auth/login` directly (no `connection` param) land on the Auth0-branded page. This is expected behavior, not a bug.
