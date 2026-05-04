# Known Issue — MSW intercepts lost after Turbopack HMR

## Symptoms

In dev mode with `ENABLE_MSW=true`, QBricks-bound API routes start returning `502 Bad Gateway` / `ECONNREFUSED` after a few hot-reloads. The first request or two after `pnpm dev` starts works fine, then intercepts stop firing.

Typical error:

```
QBricks API fetch error for /conversations?plantId=...: TypeError: fetch failed
    at async qbricksFetch (lib/api/qbricks.ts:37:17)
    at async GET (app/api/chat/threads/route.ts:30:20)
  [cause]: AggregateError:
    code: 'ECONNREFUSED',
```

## Root cause

Turbopack's hot-reloading invalidates module realms. When a route handler is hot-reloaded:

1. Its imports are re-evaluated in a new module realm
2. The MSW server instance may be a fresh one (without handlers attached), or the old one may still exist but the `fetch` reference in the new realm isn't patched
3. Requests start escaping to the real `RAG_AGENT_URL` (which has nothing listening), hence `ECONNREFUSED`

MSW's Node adapter patches Node's HTTP layer at `server.listen()` time. In theory this should be process-wide and survive HMR. In practice, Turbopack's aggressive module realm churn breaks the patch chain for route handlers that are hot-reloaded.

## Fix (three layers of defense)

All three layers are in place simultaneously to make the system resilient.

### Layer 1: Singleton server on globalThis

`tests/mocks/server.ts`:

```ts
const globalForMsw = globalThis as unknown as { __mswServer?: SetupServerApi };

export const server: SetupServerApi =
  globalForMsw.__mswServer ?? setupServer(...handlers);

if (!globalForMsw.__mswServer) {
  globalForMsw.__mswServer = server;
}
```

**Why:** ensures every re-evaluation of `tests/mocks/server.ts` returns the SAME server instance, not a fresh one with no handlers.

### Layer 2: Idempotent listen in instrumentation

`instrumentation.ts`:

```ts
export async function register() {
  if (process.env.NODE_ENV !== "development") return;
  if (process.env.NEXT_RUNTIME !== "nodejs") return;
  if (process.env.ENABLE_MSW !== "true") return;

  const { server } = await import("@/tests/mocks/server");

  if (!globalThis.__mswListening) {
    server.listen({ onUnhandledRequest: "bypass" });
    globalThis.__mswListening = true;
    console.log("🔶 MSW: QBricks mock server enabled (dev mode)");
  }
}
```

**Why:** attaches the listener at boot. The `globalThis.__mswListening` flag prevents double-listen if `register()` is called multiple times.

### Layer 3: Lazy re-attach in qbricksFetch

`lib/api/qbricks.ts`:

```ts
async function ensureMswReady(): Promise<void> {
  if (process.env.NODE_ENV !== "development") return;
  if (process.env.ENABLE_MSW !== "true") return;
  if (process.env.NEXT_RUNTIME !== "nodejs") return;

  const g = globalThis as unknown as { __mswListening?: boolean };
  if (g.__mswListening) return;

  const { server } = await import("@/tests/mocks/server");
  server.listen({ onUnhandledRequest: "bypass" });
  g.__mswListening = true;
}

export async function qbricksFetch<T>(...) {
  await ensureMswReady();
  // ... existing fetch logic
}
```

**Why:** if somehow the `globalThis.__mswListening` flag is cleared (e.g., Turbopack resets globalThis, which is rare but can happen), the next `qbricksFetch` call re-attaches the listener. Idempotent and cheap — just a `globalThis` lookup per call.

## Why all three

Each layer alone is insufficient:

- **Layer 1 alone**: the server instance is stable but nobody calls `listen()` in new realms
- **Layer 2 alone**: `listen()` only runs at boot; if HMR invalidates the boot-time listener, we're stuck
- **Layer 3 alone**: works but has a slightly higher per-request cost; the other layers reduce the rate of re-attach calls

Together, they guarantee the intercept chain is always up before any real HTTP call goes out.

## Verification

1. Start `pnpm dev`
2. Navigate to `/chat` — should see mock conversations (intercept is active)
3. Edit any file to trigger HMR (e.g., add a space to `components/layout/Sidebar.tsx`)
4. Navigate to a different thread — should still see mock messages
5. Edit again and navigate — should keep working indefinitely

If you see `ECONNREFUSED`:
1. Check `grep ENABLE_MSW .env.local` — must be `true`
2. Check terminal for the `🔶 MSW: QBricks mock server enabled` log line on boot
3. Restart `pnpm dev` completely (Ctrl+C then `pnpm dev`)
4. If still broken after restart, check that `lib/api/qbricks.ts` still has the `ensureMswReady()` call and `tests/mocks/server.ts` still uses the globalThis singleton

## Why not disable Turbopack?

We could run `next dev --webpack` (or whatever the flag is) to use the old Webpack-based dev server which is more stable with MSW. But Turbopack is noticeably faster for HMR and the cost of adding the three layers above is small. The trade-off favors keeping Turbopack.

## References

- Commit `113348f` — initial HMR resilience fix
- Commit `f04aadc` — cleanup and consolidation
- `lib/api/qbricks.ts`
- `tests/mocks/server.ts`
- `instrumentation.ts`
