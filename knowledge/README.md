# `.claude/knowledge/` — curated, team-shareable docs

Authoritative reference content for the MMBR workspace. Tracked in the `.claude/` repo; intended to be **shared with the team** and stay accurate.

Personal scratch (handoffs, review drafts, transient notes) lives in `.claude/local/` (gitignored). Anything else strictly personal goes in `.docs/`.

## Layout

```
knowledge/
├── architecture/         # How the code works today
├── decisions/            # Why it's that way (ADRs)
├── known-issues/         # Bugs + workarounds (false-positive shield for pr-review)
└── reference/
    ├── concepts/         # Terminology + conceptual overviews
    ├── external-apis/    # Contracts for services we don't own
    ├── operations/       # Operational runbooks
    ├── patterns/         # How to add things (recipes)
    ├── prompts/          # Reusable AI prompts
    └── setup/            # How to set up dev tools
```

## How knowledge flows (3 layers)

| Layer | Where | Lifetime | Shape |
|-------|-------|----------|-------|
| **Auto-memory** | `~/.claude/projects/.../memory/*.md` | Permanent | Small discrete facts loaded every session (user profile, behavioral rules, project pointers) |
| **Knowledge** (this folder) | `.claude/knowledge/<category>/` | Long-term | Documented knowledge with structure — architecture, ADRs, runbooks, patterns |
| **Handoffs** | `.claude/local/handoffs/<YYYY-MM-DD-HHMM-slug>.md` | Transient (hours/days) | Session state — what's done, blocked, next step. Gitignored. |

Mental test when capturing something:
- **One-line rule?** → auto-memory
- **Explanation or structure?** → `knowledge/` (use `/preserve` to save)
- **Where I stopped today?** → `.claude/local/handoffs/` (use `/handoff` to save before `/clear`)

## Folder guide

### `architecture/` — How things work

Snapshots of the current mental model. Read these when onboarding a new concept.

| File | What it covers |
|------|---------------|
| `auth-flow.md` | Auth0 session → middleware → layout → API chain |
| `rbac.md` | 3 roles, DB as source of truth, defense in depth on Documents Panel |
| `state-management.md` | Why no Redux, useSelectedPlant pattern, useSyncExternalStore |
| `mocking-strategy.md` | MSW for QBricks, real Postgres, DEV_BYPASS_AUTH |
| `qap-message-persistence.md` | How conversation messages round-trip through QAP |
| `qap-user-sync.md` | Why MMBR mirrors users into QAP at two sites |
| `deployed-services.md` | The 3 ECS services (`web-platform`, `qbrick`, `backend-ui`), wiring, CI/CD |
| `ci-cd-deploy-flow.md` | CI/CD pipeline + deploy flow |
| `gap-dashboard-design-specs.md` | Gap dashboard design specs |

### `decisions/` — Why it's that way

ADR-style notes. Read when asking "why did we do it this way?" and the diff doesn't explain.

| File | Decision |
|------|---------|
| `why-db-role-not-jwt-claim.md` | Role reads from DB at request time, not the Auth0 claim |
| `why-dev-bypass-two-signals.md` | DEV_BYPASS_AUTH requires two env vars + production throw |
| `why-msw-not-direct-mocks.md` | MSW at network level, not jest.mock on fetch |

### `known-issues/` — Bugs + workarounds

Active problems with documented workarounds. Auto-loaded by the `pr-review` skill as a false-positive shield.

| File | Issue |
|------|-------|
| `msw-turbopack-hmr.md` | MSW intercepts lost after Turbopack hot-reload |
| `qap-user-id-silent-null.md` | `conversations.user_id` silently NULL — JWT sub vs internal UUID mismatch |
| `qbrick-dev-secret-template-defaults.md` | qbrick dev deployed with unmodified `.env.api.example` defaults |
| `rds-proxy-requires-tls.md` | MMBR RDS Proxy enforces TLS — `?sslmode=require` (Node) vs `?ssl=require` (Python) |
| `web-platform-secrets-injected-as-json.md` | Whole `mmbr-{env}-web-platform` JSON injected as one `SECRETS` env var; use `getRuntimeEnv` / `requireEnv` helpers |

### `reference/patterns/` — How to add things

Step-by-step recipes that follow our conventions.

| File | Pattern |
|------|--------|
| `adding-a-guarded-route.md` | New role-gated route (UI + layout + API + tests) |
| `adding-a-new-role.md` | New user role (types + migration + seed + dev switcher + matrix) |

### `reference/external-apis/` — External service references

| File | Service |
|------|---------|
| `qap-endpoints.md` | QAP (Python FastAPI backend) — the real QBricks |
| `qap-auth-layers.md` | The 2 trust layers between web-platform and qbrick |

### `reference/setup/` — Dev tool setup

| File | Tool |
|------|------|
| `gh-cli-installation.md` | GitHub CLI install + auth |
| `jira-mcp-setup.md` | Jira MCP server for Claude Code |
| `FIGMA_MCP_WORKFLOW.md` | Figma MCP workflow for design-to-code |
| `dev-pages.md` | Quick list of all web-platform pages + URLs |
| `auth0-dashboard.md` | Adding a new environment URL to the shared Auth0 tenant |
| `run-qbrick-alembic-migrations.md` | Apply qbrick alembic migrations on a deployed environment |
| `aws-sso-setup.md` | AWS SSO setup |
| `ai-platform-environments.md` | ai-platform environments overview |

### `reference/operations/` — Runbooks

| File | Operation |
|------|-----------|
| `aws-mmbr.md` | MMBR AWS operational notes |
| `whitelist-add-user.md` | Add a user to `mmbr.whitelist` (operator/superadmin) and assign plants for operators |
| `db-connect.md` | Connect to a deployed env's Postgres via the bastion (DBeaver / psql / Node + pg). Includes the SSL-OFF-through-tunnel gotcha and common verification queries |

### `reference/concepts/`

| File | Topic |
|------|-------|
| `harness-engineering.md` | Harness engineering notes |

### `reference/prompts/` — Reusable prompts

The default code-review path is the workspace `pr-review` skill — these prompts are non-code review aides.

| File | Purpose |
|------|---------|
| `documentation-review-prompt.md` | Prompt for reviewing project documentation |
| `TESTING_GUIDELINES.md` | Testing guidelines |
| `behavioral guidelines.md` | Behavioral guidelines reference |

## How to use this folder

- **When onboarding a new concept** → `architecture/`
- **When asking "why did we do it this way?"** → `decisions/`
- **When adding a new feature that follows an established pattern** → `reference/patterns/`
- **When hitting a known bug** → `known-issues/`
- **When setting up a dev tool** → `reference/setup/`
- **When integrating with an external service** → `reference/external-apis/`

## What belongs here

- Stable knowledge that survives across branches
- Things a new dev (or future you, 6 months later) needs to understand the codebase
- Decisions that have context beyond "the diff shows what changed"

## What does NOT belong here

- Review artifacts → `.claude/local/reviews/`
- Handoffs → `.claude/local/handoffs/`
- Personal scratch (meetings, plans, feedback, archive) → `.docs/`
- Anything that references specific commit hashes as load-bearing — it'll rot
