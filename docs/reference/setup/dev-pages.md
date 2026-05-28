# MMBR Web — Available Pages (Local Dev)

> Quick reference for all routes available at `http://localhost:3000` in dev mode.

## Auth Pages (public)

| Page | URL | Note |
|------|-----|------|
| Root | `/` | Redirects to `/login` or `/chat` |
| Login | `/login` | Email → password flow |
| Register | `/register?email=johndoe%40mmbr.com` | Requires `?email=` (from login flow) |
| Forgot password | `/forgot-password?email=johndoe%40mmbr.com` | Requires `?email=` (from login flow) |
| Reset password | `/reset-password?token=mock-reset-token` | Requires `?token=` (from Auth0 email) |

## Protected Pages (DEV_BYPASS_AUTH)

| Page | URL | Note |
|------|-----|------|
| Welcome screen | `/chat` | New conversation, suggested topics |
| Chat thread | `/chat/a0000000-0000-0000-0000-000000000001` | Existing conversation (mock messages + citations) |
| Documents | `/documents` | Read-only document table |
| Profile | `/profile` | Edit name, change password |
| Plant selector | — | Dropdown in sidebar, visible on all protected pages |

## Notes

- Auth pages bypass Auth0 in dev but still render the full UI (forms, validation, strength indicators)
- Protected pages use `DEV_BYPASS_AUTH` — no login required
- QBricks data (conversations, messages) is mocked via MSW when `ENABLE_MSW=true`
- PostgreSQL data (plants, feedback tags, suggested topics) is real from `db/seed.sql`
