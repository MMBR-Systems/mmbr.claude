# MMBR Workspace

> This is the workspace root, NOT a git repo. It contains multiple repos and personal developer docs.

## Workspace Map

| Path | Type | Description |
|------|------|-------------|
| `web-platform/` | **Git repo** | Next.js frontend — has its own `.claude/CLAUDE.md` with full project docs |
| `ai-platform/` | **Git repo (source of truth for QAP)** | MMBR's QAP backend at `MMBR-Systems/ai-platform`. Python FastAPI service that owns conversations, messages, citations, documents (the real QBricks). Seeded as a code drop from `thisisqubika/qubika-agentic-platform` and maintained independently since — histories diverge, and this is the repo that MMBR prod actually runs. Tickets that change QAP behavior land here |
| `qubika-agentic-platform/` | **Git repo (read-only, upstream reference)** | Upstream QAP at `thisisqubika/qubika-agentic-platform`. Useful only for comparing against `ai-platform/` when suspecting drift or missing framework features. For anything MMBR-specific, read `ai-platform/` instead |
| `.docs/` | **Personal docs (git repo, private)** | Worklogs, meetings, plans, archive, audit log — strictly personal. Handoffs/reviews/reference were migrated into `.claude/` on 2026-05-02. Never cite in PRs or repo files |
| `.claude/` | **Claude config (git repo, private)** | Workspace agent config + curated knowledge (`knowledge/`) + gitignored personal artifacts (`local/`: handoffs, review drafts) |

## Deployed Services

Three ECS services run the stack in each environment (`dev`, `qa`, `prod`). The naming is inherited from upstream Qubika conventions and is not self-explanatory — read this before touching deploys or secrets.

| Service | Role | URL (dev) | Source repo |
|---|---|---|---|
| `web-platform-*` | MMBR product. Next.js app with both the browser UI and server-side API routes (BFF pattern). | `dev.mem-brain.com` | `web-platform/` |
| `qbrick-*` | QAP backend. Python FastAPI. No UI. Reached internally via service discovery. | internal `qbrick:8000` | `ai-platform/` |
| `backend-ui-*` | QAP admin UI. Separate Next.js app for managing workflows and agents in `qbrick`. Despite the name, it IS a frontend. | `ui.dev.mem-brain.com` | upstream `qubika-agentic-platform/` |

Inter-service auth recap (dev):

- Shared HMAC for JWT signing lives under three different env var names for legacy reasons: `NEXTAUTH_SECRET` on `backend-ui` and `qbrick` (legacy alias), `QAP_JWT_SECRET` on `web-platform` (canonical). All three must hold the same value.
- `QAP_API_KEY` / `QAP_API_SECRET` / `QAP_AGENT_ID` form a per-workflow bundle stored in `qbrick`'s Postgres (in `workflow_description` + `ApiKey` tables), generated via `POST /workflow_descriptions/{id}/generate_api_key`. They cannot be reused across environments.

## Boundary Rules

- **Repos are the only folders that receive commits.** Code changes go into `web-platform/` or `ai-platform/` depending on the ticket scope.
- **`.docs/` and `.claude/` are personal workspaces.** Content from either must NEVER be copied into repository files (`web-platform/`, `ai-platform/`), referenced in PRs, or committed to those repos.
- **Both are readable.** Use them for context and reasoning, but the output goes into the relevant code repo, not back into the workspace dirs.
- **Each repo is self-contained.** `web-platform/.claude/` has all project docs an agent needs. Do not create cross-references from repo files to `.docs/` or `.claude/knowledge/`.
- **`ai-platform/` is source of truth for QAP.** It owns FastAPI routes, Pydantic schemas, auth, and the contracts `web-platform` consumes. Reference: `.claude/knowledge/reference/external-apis/qap-endpoints.md`. Tickets that change QAP behavior land here.
- **`qubika-agentic-platform/` is upstream reference only.** Read only when diffing against `ai-platform/` to spot drift or framework changes. Never use as source of truth for MMBR-facing behavior.

## Key Personal Docs

Read these when relevant — they provide context but are not project source of truth.

| Document | When to read |
|----------|-------------|
| `.claude/knowledge/README.md` | **First time touching `.claude/knowledge/`** — index of architecture/decisions/patterns/known-issues/prompts/setup/external-apis |
| `.claude/knowledge/architecture/` | When onboarding a new concept (RBAC, state, auth flow, mocking) |
| `web-platform/docs/AI-PLATFORM-INTEGRATION.md` | When touching anything that talks to QAP (chat routes, qbricks.ts, env vars). Conceptual reference — agents vs workflows, ID spaces, auth, conversation persistence, plant scoping trade-offs. Lives inside `web-platform/` now (moved out of `.docs/` on 2026-04-17). |
| `.claude/knowledge/decisions/` | When asking "why is it done this way?" |
| `.claude/knowledge/reference/patterns/` | When adding a feature that matches an established pattern |
| `.claude/knowledge/known-issues/` | When hitting a weird bug (check if it's a known one first) |
| `.claude/knowledge/reference/prompts/documentation-review-prompt.md` | When asked to review documentation |
| `.claude/knowledge/reference/setup/FIGMA_MCP_WORKFLOW.md` | When working with Figma MCP |
| `.claude/local/reviews/` | When checking previous review findings |

## How to Work in This Workspace

1. **Starting a task:** `cd` into `web-platform/` or `ai-platform/` and follow its `.claude/CLAUDE.md`.
2. **Writing code:** Frontend / BFF tickets land in `web-platform/`. QAP backend tickets land in `ai-platform/`. Follow each repo's conventions.
3. **Writing reviews/PR docs:** Output goes to `.claude/local/reviews/` (gitignored, personal).
4. **Committing:** Commit inside the relevant repo (`web-platform/` or `ai-platform/`). Never commit from workspace root.

## Shared Agent Config

Workspace-level Claude Code config (in `.claude/`) provides skills, slash commands, and hooks reusable across all repos. Per-repo `<repo>/.claude/` overrides the workspace one inside that repo's tree.

**Skills** (auto-loaded by intent — no slash needed):
- `commit` — stage + commit pending changes with the repo's commit style. Trigger: "commit isso", "salva mudanças", commit-only intent (no push, no PR).
- `open-pr` — full ship-it flow: commit + push + open GitHub PR with description grounded in the full branch diff. Trigger: "create PR", "open PR", "ship this", "ready for review", "push and PR". Inspects state and runs only the steps actually needed; each destructive step (commit / push / `gh pr create`) requires explicit `y`. Hands off to `commit` skill if user says "just commit".
- `pr-review` — structured GitHub PR review; writes artifact to `.claude/local/reviews/pr/<self|others>/` (routed by PR authorship vs current `gh` user). Reads `<repo>/.claude/banned-patterns.md` as auto-CRITICAL rules. Inside `web-platform/`, the repo-local claude-code-templates skill takes precedence (with JIRA integration).

**Slash commands** (explicit `/<name>` invocation, deliberate user actions):
- `/handoff` — capture session state before `/clear` (writes to `.claude/local/handoffs/<YYYY-MM-DD>-<HHMM>-<slug>.md`)
- `/preserve` — save a durable fact/decision into `.claude/knowledge/<category>/<topic>.md` with `created:`/`updated:` YAML frontmatter
- `/sync-index` — rescan sibling repos and refresh the workspace map (no-op until repo-index sentinels exist)

**Hooks** (auto-fire from `settings.json`):
- `bash-gatekeeper.sh` — PreToolUse gatekeeper on Bash. Blocks catastrophic patterns (`rm -rf /`, `DROP DATABASE`, etc.), warns on destructive ones (each call individually — no session memory; use `! <cmd>` in the prompt to bypass for a one-off you've already authorized), logs noteworthy ones to `.claude/local/audit.log`.
- `handoff-reminder.sh` — when a turn ends with ≥5 changed/untracked files across all nested git repos, suggests `/handoff`. Throttled to once per 4h.

**Banned patterns** (per repo): `<repo>/.claude/banned-patterns.md` — hard-rule violations the `pr-review` skill flags as auto-CRITICAL/HIGH without judgment.

## Commit Conventions

- **No `Co-Authored-By: Claude ...` trailer in commit messages.** When writing `git commit -m` HEREDOCs, end with the actual message content — no trailer line. Applies to all commits in this workspace, including amends and squashes.

## Behavioral Guidelines

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

> **Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

### 1. Think Before Coding

Don't assume. Don't hide confusion. Surface tradeoffs.

Before implementing:

- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them — don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

### 2. Simplicity First

Minimum code that solves the problem. Nothing speculative.

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

### 3. Surgical Changes

Touch only what you must. Clean up only your own mess.

When editing existing code:

- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it — don't delete it.

When your changes create orphans:

- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

**The test:** Every changed line should trace directly to the user's request.

### 4. Goal-Driven Execution

Define success criteria. Loop until verified.

Transform tasks into verifiable goals:

- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:

```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

### 5. Consult `.claude/knowledge/` Before Acting

`knowledge/` is **not auto-loaded** — read it deliberately. Before:

- **Non-trivial implementation or design** → check `knowledge/architecture/` for the relevant module/service overview, and `knowledge/decisions/` for ADRs that touch the affected area.
- **Reviewing code (PR or ad-hoc)** → check `knowledge/decisions/` (avoid flagging deliberate choices) and `knowledge/known-issues/` (false-positive shield). The `pr-review` skill does this automatically.
- **Confused about a convention, pattern, or workspace layout** → check `knowledge/reference/`.

When relevant content is found, cite it (e.g. `see knowledge/decisions/why-<name>.md`) so reviewers can follow the chain.

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.

## Preserve radar

Proactively detect moments worth preserving into `.claude/knowledge/`. When you see one of the signals below, surface it **immediately** and offer to draft. Always ask first — never auto-write. Accepting hands off to `/preserve`, which is the single write-path.

| Signal in conversation | Category | Suggestion |
|---|---|---|
| Architectural decision with explicit trade-off ("vamos por X porque Y; alternativa Z foi rejeitada porque W") | `decisions/` | "Parece ADR. Rascunho em `decisions/why-<short>.md`?" |
| Existing decision being revisited or invalidated ("antes era X, agora Y porque Z") | `decisions/` (update) | "Isso atualiza ADR existente. Editar ou supersede `decisions/why-<name>.md`?" |
| Bug investigated to root cause that changes mental model of the system, OR recurring bug worth a shield | `known-issues/` | "False-positive shield útil pro `pr-review`. Rascunho em `known-issues/<short>.md`?" |
| Non-obvious external service behavior discovered (auth, payload shape, rate limit, retry semantics) | `reference/external-apis/` | "Contrato externo. Rascunho em `reference/external-apis/<service>.md`?" |
| Same procedure executed for the 2nd+ time with non-trivial steps | `reference/patterns/` | "2ª vez nessa sequência. Pattern em `reference/patterns/<name>.md`?" |
| Operational gotcha (AWS, deploy, env, infra) whose steps aren't in any runbook | `reference/operations/` | "Runbook-worthy. Rascunho em `reference/operations/<topic>.md`?" |
| New architectural model or flow not yet documented | `architecture/` | "Insight arquitetural. Rascunho em `architecture/<topic>.md`?" |

**Skip — these don't go to knowledge:**
- Behavioral preferences ("prefiro X") → auto-memory `feedback_*.md`, not `knowledge/`.
- Session-state ("voltei depois do almoço", "amanhã continuo daqui") → handoff territory.
- Trivial fixes without learning (typos, obvious null checks).
- Anything tied to a specific commit hash as load-bearing — it'll rot.

**Cadence:**
- Max **3 suggestions per session**. Hit 3 and stay quiet — sinal that we're producing too much or ignoring too much.
- One suggestion per moment — don't repeat the same nudge.
- Always ask before writing. User accepts → run `/preserve` directly with category and path already chosen.

## Package Manager

pnpm (canonical for all repos in this workspace).
