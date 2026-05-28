# Mocking Strategy

> What we mock, what we don't, and how the dev/test boundaries work.

## What's real vs mocked in dev

| Layer | Dev mode | Production | Source of truth |
|-------|----------|------------|-----------------|
| **Auth0** | Bypassed (`DEV_BYPASS_AUTH=true`) | Real | `proxy.ts` + `lib/dev-bypass.ts` |
| **PostgreSQL** | Real (Docker container) | Real | `docker-compose.yml` + `db/seed.sql` |
| **QBricks (RAG Agent)** | Mocked via MSW | Real (QAP Python backend) | `tests/mocks/qbricks/*` |

**Why split this way:**

1. **Auth0 bypass**: no need to configure an Auth0 tenant to run locally. The bypass is dev-only (guarded by `NODE_ENV=development && DEV_BYPASS_AUTH=true`) and crashes at module load in production if anyone tries to enable it.
2. **Real PostgreSQL**: we own the schema, we want real migrations, real queries, real Drizzle type generation. Docker makes it trivial to spin up.
3. **MSW for QBricks**: QAP (the Python FastAPI backend that owns conversations, messages, citations) is a separate service, owned by a different team. We don't want a hard local dependency on it, and we want stable mock data for UI development.

## MSW — the canonical mock layer

MSW (Mock Service Worker) intercepts `fetch()` calls at the Node HTTP level. Our `qbricksFetch()` in `lib/api/qbricks.ts` calls native `fetch()` to `RAG_AGENT_URL`, and MSW intercepts before the request leaves the process.

**This gives us:**

- **Realistic code paths**: the API route calls `qbricksFetch` which calls `fetch` which MSW intercepts. Nothing is short-circuited. When we swap MSW for real QAP, the code paths are the same.
- **Shared handlers**: `tests/mocks/qbricks/handlers.ts` is used both in Jest unit tests AND in the dev server (via `instrumentation.ts`). One set of handlers, two runtimes.
- **Opt-in**: `ENABLE_MSW=true` in `.env.local` turns it on. Unset to hit real QAP.

### Handler file structure

```
tests/mocks/
├── server.ts          # setupServer(...handlers), cached on globalThis
└── qbricks/
    ├── handlers.ts    # MSW http handlers
    └── data.ts        # Mock data (conversations, messages, citations)
```

### Dev mode wiring

1. `instrumentation.ts` runs at server boot (Next.js instrumentation hook)
2. Checks `NODE_ENV === "development"` + `NEXT_RUNTIME === "nodejs"` + `ENABLE_MSW === "true"`
3. Imports the server (from globalThis cache if present) and calls `server.listen({ onUnhandledRequest: "bypass" })`
4. Sets `globalThis.__mswListening = true`

### Test mode wiring

Each test file (or `tests/setup.ts`) does:

```ts
import { server } from "@/tests/mocks/server";
beforeAll(() => server.listen({ onUnhandledRequest: "error" }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
```

Note the difference: tests use `"error"` (unhandled requests fail loudly), dev uses `"bypass"` (unhandled requests pass through to the real URL so you can mix real + mock endpoints).

## What we DON'T mock

- ❌ **PostgreSQL**: use a real Docker container and real seed data
- ❌ **Global `fetch`**: never `jest.mock` or `jest.fn()` the global fetch for QBricks calls — use MSW handlers instead
- ❌ **Server components in tests**: test client components in isolation; test route handlers via their exports (not by spinning up Next.js)
- ❌ **Auth0 in production code**: dev bypass is the only exception, and it's opt-in with two env-var gates

## When to use `jest.mock()` vs MSW

| Use `jest.mock()` for... | Use MSW for... |
|-------------------------|----------------|
| Internal modules (`@/lib/api/auth` to fake a logged-in user) | External HTTP calls (`fetch` to QBricks) |
| React Router (`next/navigation`) | QAP endpoints |
| Things outside the network boundary | Anything that goes over HTTP |

Example: `tests/unit/api/documents.test.ts` uses **both**:
- `jest.mock("@/lib/api/auth")` to stub `requireAuthWithDbRole` with a fake user
- `server.use(http.get(...))` to add a one-shot MSW handler for `/documents`

## The MSW + Turbopack HMR problem

Turbopack hot-reloads invalidate module realms, which can drop the MSW listener even though the server instance is still alive. After an HMR, API calls start failing with `ECONNREFUSED` because the intercept chain is broken.

### Fix (three layers of defense)

1. **`tests/mocks/server.ts`** — the MSW server is pinned on `globalThis` so a new module evaluation reuses the same instance.
2. **`instrumentation.ts`** — calls `server.listen()` at boot, guarded by `globalThis.__mswListening` to prevent double-listen.
3. **`lib/api/qbricks.ts`** — `ensureMswReady()` at the top of every `qbricksFetch` call checks `globalThis.__mswListening` and re-attaches the listener if it's missing. Idempotent and cheap.

The combination of those three layers makes MSW resilient to Turbopack HMR without any per-request performance cost beyond a `globalThis` lookup.

See `.claude/docs/known-issues/msw-turbopack-hmr.md` for the full incident history.

## Switching to real QAP (future)

When QAP is ready for integration, the cutover is a single env var flip:

```bash
# .env.local
ENABLE_MSW=false          # was: true
RAG_AGENT_URL=https://qap.qubika.internal  # was: http://localhost:8000
```

Then restart `pnpm dev`. No code changes needed.

For tests, we keep `ENABLE_MSW=true` forever — tests should never hit real services.

## Mock data locations (for quick reference)

| What | File |
|------|------|
| Conversations list | `tests/mocks/qbricks/data.ts` → `conversations` |
| Messages in a thread | `tests/mocks/qbricks/data.ts` → `messages` |
| `/ask` response | `tests/mocks/qbricks/data.ts` → `askResponse` |
| Citations (used in messages) | Inside `messages[].citations` — currently 7 citations on the assistant message |
| Dev users (operator, admin, superadmin) | `db/seed.sql` |
| Plants | `db/seed.sql` (Double Eagle, Clairton) |
| Feedback tags | `db/seed.sql` (4 positive + 5 negative) |
| Suggested topics | `db/seed.sql` (4 wastewater questions) |
