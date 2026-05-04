# Auth Flow Architecture — MMBR Web Platform

> How authentication works across Browser, Next.js, Auth0, PostgreSQL, and QBricks.

---

## Overview

MMBR has **three systems** that care about identity:

| System | Role | Auth concern |
|--------|------|-------------|
| **Auth0** | Identity provider | Owns login, passwords, JWT tokens, sessions |
| **Next.js (web-platform)** | BFF / proxy | Validates sessions, injects user context into headers, proxies requests |
| **QBricks** | AI backend | Needs to know WHO is asking and for WHICH plant |

The question the backend team is solving: **How does QBricks trust that a request from Next.js is legitimate?**

---

## Current Flow (what we have today)

```
Browser                    Next.js Middleware           Auth0
  │                            │                          │
  │  Request /chat             │                          │
  │───────────────────────────▶│                          │
  │                            │  auth0.getSession()      │
  │                            │─────────────────────────▶│
  │                            │  ◀─ session { sub, name }│
  │                            │                          │
  │                            │  Set headers:            │
  │                            │    x-user-id: auth0|abc  │
  │                            │    x-user-role: operator  │
  │                            │    x-selected-plant-id   │
  │                            │                          │
  │                            │  Next.js API Route       │
  │                            │    ├── requireAuth()     │
  │                            │    │   reads headers     │
  │                            │    │                     │
  │                            │    ├── qbricksFetch()    │
  │                            │    │   POST /ask         │
  │                            │    │   { question,       │
  │                            │    │     plantId,        │
  │                            │    │     conversationId }│
  │                            │    │                     │
  │                            ▼    ▼                     │
                           QBricks (localhost:8000)
                           ❌ No auth — trusts blindly
```

### Problem

Today, `qbricksFetch()` sends requests to QBricks with **no authentication headers**. QBricks has no way to verify:
1. Is this request from a legitimate MMBR instance?
2. Which user is asking?
3. Does this user have access to this plant?

This works in dev (MSW mocks), but in production QBricks needs to trust the caller.

---

## Two Approaches to Solve This

### Approach A: Forward User JWT (User Token)

```
Browser → Auth0 → JWT (access_token)
  │
  ▼
Next.js Middleware
  │  Extracts access_token from session
  │  Passes to API route via header
  ▼
Next.js API Route
  │  qbricksFetch("/ask", {
  │    headers: { Authorization: `Bearer ${accessToken}` }
  │  })
  ▼
QBricks
  │  Validates JWT against Auth0 JWKS
  │  Extracts user identity from token claims
  │  Checks plant access from token claims or DB
```

**How it works:**
1. Auth0 issues an `access_token` when user logs in
2. Next.js middleware extracts the token from the Auth0 session
3. API routes forward the token to QBricks as `Authorization: Bearer <token>`
4. QBricks validates the JWT using Auth0's public keys (JWKS endpoint)
5. QBricks reads claims (user ID, role, plant) from the token itself

**Pros:**
- QBricks knows exactly who the user is
- Standard OAuth2 pattern
- Fine-grained per-user authorization possible on QBricks side

**Cons:**
- Token lifetime management — access tokens expire (15 min), need refresh handling
- QBricks needs to call Auth0's JWKS endpoint to validate
- More complex: every request carries user context, QBricks needs Auth0 config
- If token expires mid-session, user gets errors until refresh happens

---

### Approach B: Machine-to-Machine Token (Service Token)

> This is what the backend team proposed in the 2026-04-06 daily.

```
Next.js Backend (on startup or cached)
  │  POST https://auth0-tenant/oauth/token
  │  { grant_type: "client_credentials",
  │    client_id: MMBR_M2M_CLIENT_ID,
  │    client_secret: MMBR_M2M_CLIENT_SECRET,
  │    audience: "https://api.qbricks.ai" }
  │
  ▼
Auth0 → returns M2M access_token (long-lived, e.g. 24h)
  │
  ▼
Next.js API Route
  │  qbricksFetch("/ask", {
  │    headers: {
  │      Authorization: `Bearer ${m2mToken}`,
  │      "x-user-id": "auth0|abc",
  │      "x-plant-id": "00000000-..."
  │    }
  │  })
  ▼
QBricks
  │  Validates M2M token (trusts that MMBR verified the user)
  │  Reads x-user-id and x-plant-id headers for context
  │  Does NOT need to know about individual users
```

**How it works:**
1. Auth0 has a "Machine-to-Machine" application for MMBR → QBricks communication
2. Next.js backend obtains a service token using `client_credentials` grant
3. Token is cached (long-lived, e.g., 24h) — not per-user, per-service
4. API routes send this token + user context as custom headers
5. QBricks validates the M2M token (confirms the caller is MMBR), trusts the user headers

**Pros:**
- Simpler — one token for all requests, cached for hours
- No per-user token management on QBricks side
- QBricks only needs to validate one thing: "Is this MMBR calling me?"
- No user JWT expiry issues — M2M tokens are long-lived and auto-refreshed by the backend

**Cons:**
- QBricks trusts MMBR blindly for user identity (MMBR says "this is user X" and QBricks believes it)
- If MMBR is compromised, all user identities are spoofable to QBricks
- Less standard for user-specific APIs (common for service-to-service, less for user-facing)

---

## Comparison

| Aspect | User JWT (A) | M2M Token (B) |
|--------|-------------|---------------|
| **Who authenticates to QBricks** | The user (via forwarded JWT) | MMBR service (via M2M token) |
| **Token lifetime** | Short (15 min), needs refresh | Long (24h), cached server-side |
| **QBricks complexity** | High — validates user JWTs, reads claims | Low — validates one M2M token, reads headers |
| **User identity trust** | Strong — QBricks verifies directly with Auth0 | Delegated — QBricks trusts MMBR's headers |
| **Next.js complexity** | Medium — extract and forward access_token | Low — obtain M2M token once, cache it |
| **Security if MMBR compromised** | QBricks still protected (tokens are user-specific) | QBricks fully exposed (any user can be spoofed) |
| **Common pattern** | API Gateway / user-facing services | Microservice-to-microservice |

---

## Backend Team Recommendation: Approach B (M2M)

From the 2026-04-06 daily: the backend team proposed using **machine-to-machine** approach because:
- QBricks is an internal service, not user-facing
- MMBR already validates the user (Auth0 session in middleware)
- Simpler to implement — no per-user token forwarding complexity
- The QBricks framework may not have user JWT validation built-in

### What needs to happen

| Task | Owner | Status |
|------|-------|--------|
| Create M2M application in Auth0 for MMBR → QBricks | Backend | In progress (MMBR-133) |
| Implement `client_credentials` grant in Next.js backend | Backend | In progress |
| Cache M2M token server-side with auto-refresh | Backend | Pending |
| Update `qbricksFetch()` to include `Authorization` header + user context | Backend / Frontend | Pending |
| QBricks: validate M2M token on incoming requests | QBricks team | Pending |
| QBricks: read `x-user-id` / `x-plant-id` from headers | QBricks team | Pending |

### Impact on Frontend

Minimal. The changes are in `lib/api/qbricks.ts` — the `qbricksFetch()` function will add headers automatically. Frontend components and API routes don't need to change.

```typescript
// What qbricksFetch will look like after M2M integration
export async function qbricksFetch<T>(path: string, options: RequestInit = {}) {
  const m2mToken = await getM2MToken(); // cached, auto-refreshes

  const res = await fetch(`${QBRICKS_API_URL}${path}`, {
    ...options,
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${m2mToken}`,
      ...options.headers, // API routes can add x-user-id, x-plant-id
    },
  });
  // ...
}
```

---

## Dev Mode (unchanged)

In development, none of this applies:
- `DEV_BYPASS_AUTH` skips Auth0 entirely
- `ENABLE_MSW=true` mocks QBricks via MSW
- No real tokens are exchanged

The auth integration only matters when connecting to a real QBricks instance (Sprint 4).
