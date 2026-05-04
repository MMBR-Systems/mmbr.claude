# Decision — Use MSW for QBricks, not direct jest.mock / inline stubs

**Date:** 2026-04-06
**Status:** Accepted
**Context:** `chore/dev-environment-setup` PR

## Decision

QBricks (the external RAG Agent API) is mocked via **MSW (Mock Service Worker)** in both dev and test runtimes. We do **not** use `jest.mock` / `jest.spyOn` on the global `fetch` for QBricks calls, and we do **not** short-circuit `qbricksFetch` with hardcoded return values.

## Context

When the web platform started needing test coverage for API routes that proxy to QBricks, three options were on the table:

1. **Mock the global `fetch`** (`global.fetch = jest.fn(...)`)
2. **Mock `qbricksFetch` directly** (`jest.mock("@/lib/api/qbricks")`)
3. **Mock at the network level with MSW**

We chose MSW.

## Alternatives considered

### Option 1: Mock `global.fetch`

**Pros**: Simple, no new dependency.
**Cons**:
- Pollutes global state, needs careful cleanup per test
- Doesn't play well with multiple parallel fetches
- Very easy to accidentally let a test fetch escape to the real network
- Can't share mock definitions between the dev server and tests

### Option 2: Mock `qbricksFetch`

**Pros**: Scoped, easy to stub.
**Cons**:
- Tests skip the network layer entirely, so they don't cover the real code path (error handling, headers, query encoding, timeouts)
- Can't share mock definitions with dev server
- If we refactor `qbricksFetch` internally, tests keep passing even if the behaviour changes

### Option 3: MSW (chosen)

**Pros**:
- Intercepts at the Node HTTP level, so the whole code path runs: `qbricksFetch` → `fetch` → MSW handler → response. Realistic.
- **Same handlers can be shared between Jest tests and the dev server.** When we add a new mock endpoint, both runtimes benefit.
- Clean cleanup via `server.resetHandlers()`.
- Per-test overrides via `server.use(...)` without mutating the base handlers.
- Works with parallel fetches and concurrent test runs.
**Cons**:
- One extra dependency (already in our test toolkit).
- HMR quirks with Turbopack — see `.claude/knowledge/known-issues/msw-turbopack-hmr.md` (fixed with a globalThis-backed singleton).

## Implementation

### Handler file

`tests/mocks/qbricks/handlers.ts`:

```ts
import { http, HttpResponse } from "msw";
import * as data from "./data";

const BASE_URL = "http://localhost:8000";

export const handlers = [
  http.get(`${BASE_URL}/conversations`, ({ request }) => { ... }),
  http.get(`${BASE_URL}/conversations/:threadId/messages`, () => { ... }),
  http.post(`${BASE_URL}/ask`, () => { ... }),
];
```

### Server singleton

`tests/mocks/server.ts`:

```ts
import { setupServer, type SetupServerApi } from "msw/node";
import { handlers } from "./qbricks/handlers";

// Persist across HMR reloads
const globalForMsw = globalThis as unknown as { __mswServer?: SetupServerApi };
export const server: SetupServerApi =
  globalForMsw.__mswServer ?? setupServer(...handlers);
if (!globalForMsw.__mswServer) {
  globalForMsw.__mswServer = server;
}
```

### Dev runtime wiring

`instrumentation.ts` attaches the listener at boot, gated by `NODE_ENV=development` + `ENABLE_MSW=true`.

### Test runtime wiring

Each test suite (or global `tests/setup.ts`):

```ts
beforeAll(() => server.listen({ onUnhandledRequest: "error" }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
```

Note `"error"` in tests (unhandled requests fail loudly) vs `"bypass"` in dev (unhandled requests pass through).

### Per-test overrides

```ts
server.use(
  http.get(`${QBRICKS_URL}/documents`, () =>
    HttpResponse.json({ documents: [...], total: 1, page: 1, totalPages: 1 }),
  ),
);
```

This is the pattern used in `tests/unit/api/documents.test.ts` to add a one-shot handler for the superadmin happy-path test.

## When jest.mock IS still appropriate

MSW is only for **outgoing HTTP**. Internal modules should still be mocked with `jest.mock()`:

- `jest.mock("@/lib/api/auth")` to fake a logged-in user
- `jest.mock("next/navigation")` for `useRouter`, `usePathname`
- `jest.mock("@/lib/db")` if you need to fake Drizzle queries (rare — usually test with a real DB)

Example from `tests/unit/api/documents.test.ts`:

```ts
// jest.mock for internal auth boundary
jest.mock("@/lib/api/auth", () => ({
  requireAuthWithDbRole: (req) => mockRequireAuthWithDbRole(req),
}));

// MSW for the outgoing QBricks HTTP call
server.use(http.get(`${QBRICKS_URL}/documents`, () => ...));
```

Both mocks coexist cleanly. `jest.mock` fakes the "logged in user"; MSW fakes the "QBricks response."

## Consequences

- We must maintain MSW handlers as the QBricks API contract evolves.
- When we switch to real QAP, we just set `ENABLE_MSW=false` and the same `qbricksFetch` code path hits the real backend.
- Tests are more realistic (the full network layer runs) at the cost of slightly more complex setup.

## References

- Commit `1789613` — initial MSW setup in `chore/dev-environment-setup`
- `tests/mocks/qbricks/handlers.ts` — canonical handler file
- `.claude/knowledge/architecture/mocking-strategy.md` — overview of what we mock and why
