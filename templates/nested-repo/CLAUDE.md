# <Repo name>

<!-- One-sentence purpose. This line is what `/sync-index` picks up for the workspace Repo index. Keep under ~80 chars. -->

## Stack

- Language:
- Framework:
- Package manager:
- Runtime version:

## Entry points

- Main: `path/to/main`
- Dev server: `<command>`
- Tests: `<command>`
- Build: `<command>`
- Lint / format: `<command>`

## Local setup

<!-- Minimal steps to get a fresh clone running. If it takes more than ~5 steps, link to a runbook in .docs/setup/ instead. -->

1. 
2. 
3. 

## Environments

| Env | URL / host | Notes |
|-----|------------|-------|
| local | http://localhost:<port> | — |
| dev | — | — |
| prod | — | — |

## Repo-specific rules for Claude

<!-- Rules that only apply when working inside this repo. They override the workspace CLAUDE.md on conflict. Keep this section short — detailed patterns belong in .claude/knowledge/. -->

- <rule 1>
- <rule 2>

## Pre-review oracle commands

<!-- Deterministic checks the team runs before/during code review. The pr-review skill and any closed-loop pattern uses these as the verification gate. List them in cheap-to-expensive order. -->

- Lint:        `<command>`     (e.g. `pnpm lint`, `ruff check .`)
- Format:      `<command>`     (e.g. `pnpm format:check`, `ruff format --check .`)
- Type check:  `<command>`     (e.g. `pnpm typecheck`, `tsc --noEmit`, `mypy .`)
- Unit tests:  `<command>`     (e.g. `pnpm test`, `pytest tests/`)
- E2E tests:   `<command>`     (e.g. `pnpm e2e`, `playwright test`) — optional
- Build:       `<command>`     (e.g. `pnpm build`)

Cascade for fastest-to-slowest:

```bash
<lint-cmd> && <typecheck-cmd> && <unit-test-cmd>
```

## Overrides

This repo may override workspace-level skills/commands. List them here so humans aren't surprised.

- Commands overridden: <list or "none">
- Skills overridden: <list or "none">

## Pointers

- Runbooks: `.docs/setup/`
- ADRs: `.claude/knowledge/decisions/` — the `pr-review` skill auto-loads relevant ADRs for blast-radius filtering.
- Known issues: `.claude/knowledge/known-issues/` — auto-loaded as false-positive shield by `pr-review`.
- External API contracts: `.claude/knowledge/reference/external-apis/`
- Banned patterns: `<repo>/.claude/banned-patterns.md` — auto-CRITICAL rules enforced by `pr-review`. Optional file; create only if the team has hard rules to enforce.
