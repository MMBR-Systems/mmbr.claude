# Use MSW for QBricks, not direct jest.mock / inline stubs

QBricks (the external RAG Agent API) is mocked with **MSW (Mock Service Worker)** at the network level in both dev and test runtimes — not via `jest.mock`/`jest.spyOn` on global `fetch`, and not by short-circuiting `qbricksFetch` with hardcoded returns. MSW lets the whole code path run (`qbricksFetch → fetch → handler`), shares one set of handlers between Jest and the dev server, and cleans up via `server.resetHandlers()`; the rejected alternatives either skipped the real network layer or couldn't share handlers. Switching to real QAP is just `ENABLE_MSW=false` on the same code path.

## Consequences

MSW handlers must be maintained as the QBricks contract evolves. MSW is only for outgoing HTTP — internal boundaries (`@/lib/api/auth`, `next/navigation`, `@/lib/db`) still use `jest.mock`. See [../architecture/mocking-strategy.md](../architecture/mocking-strategy.md) and the Turbopack HMR gotcha in [../known-issues/msw-turbopack-hmr.md](../known-issues/msw-turbopack-hmr.md).
