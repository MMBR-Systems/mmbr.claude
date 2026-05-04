# `.claude/` — workspace agent config

This folder configures Claude Code for the MMBR workspace: behavioral rules, slash commands, skills, and permissions. Nested repos (`web-platform/`, `ai-platform/`) may have their own `.claude/` that overrides these inside their scope.

## Layout

```
.claude/
├── CLAUDE.md                 # workspace map + behavioral guidelines (always loaded)
├── CLAUDE.local.md           # per-developer overrides (gitignored, auto-loaded)
├── README.md                 # this file
├── settings.json             # permissions, hooks, env (tracked)
├── settings.local.json       # per-user overrides (gitignored)
├── .gitignore
├── memory/                   # auto-memory store (project + user + feedback)
├── knowledge/                # curated team-shareable docs (architecture/, decisions/, known-issues/, reference/)
├── local/                    # gitignored — handoffs/, reviews/, audit.log
├── commands/                 # slash commands — invoked explicitly via /<name>
│   ├── handoff.md
│   ├── preserve.md
│   └── sync-index.md
├── skills/                   # auto-loaded capabilities — matched by description
│   ├── README.md
│   ├── commit/               # stage + commit pending changes
│   ├── open-pr/              # commit + push + open GitHub PR
│   ├── pr-review/            # structured GitHub PR review (artifact-first)
│   └── mmbr-aws-ops/         # MMBR-specific AWS ops handoff
├── hooks/                    # executable scripts referenced from settings.json
│   ├── README.md
│   ├── bash-gatekeeper.sh         # PreToolUse gatekeeper for Bash
│   └── handoff-reminder.sh # Stop nudge to run /handoff (multi-repo aware)
├── agents/                   # custom subagent definitions (stubbed)
│   └── README.md
└── templates/                # copyable starting points
    └── nested-repo/          # template for a repo-local .claude/
        ├── README.md
        ├── CLAUDE.md
        └── banned-patterns.md
```

## Personal storage convention

After the 2026-05-02 migration, knowledge layers are split as follows:

- **`.claude/knowledge/`** — curated, team-shareable docs (architecture, ADRs, known-issues, reference). Tracked in the `.claude/` repo. Written via `/preserve`.
- **`.claude/local/`** — gitignored personal artifacts under `.claude/`: `handoffs/`, `reviews/`, `audit.log`. Filesystem-only, no git history.
- **`.docs/`** — separate private git repo at the workspace root. Strictly personal: worklogs, meetings, plans, archive, artifacts, feedback.
- **`CLAUDE.local.md`** — gitignored personal overrides auto-loaded each turn (cloned-repo snapshot, personal task workflow).

## Convention cheatsheet

Quick reference for where each artifact lives and how its filename is formatted:

| Artifact | Path | Filename format |
|---|---|---|
| Handoff | `.claude/local/handoffs/` | `<YYYY-MM-DD>-<short-summary>.md` |
| Plan | `.claude/local/plans/` | `<YYYY-MM-DD>-<short-summary>.md` |
| PR review | `.claude/local/reviews/pr/<self\|others>/` | `<owner>-<repo>-<number>-<summary>.md` |
| ADR | `.claude/knowledge/decisions/` | `why-<short-name>.md` |
| Known issue | `.claude/knowledge/known-issues/` | `<short-name>.md` |
| Architecture | `.claude/knowledge/architecture/` | `<module>/overview.md`, `<module>/<service>.md` |

## How things get loaded

| File | When loaded |
|------|-------------|
| `CLAUDE.md` | Always, on every turn. Keep it short. |
| `CLAUDE.local.md` | Always, on every turn (if present). Personal overrides — gitignored. |
| `commands/*.md` | On explicit `/<name>` invocation. |
| `skills/*/SKILL.md` | Auto-loaded when the user's request matches the skill's `description` frontmatter. Sub-docs inside each skill are loaded progressively by the skill itself. |
| `agents/*.md` | When an agent with matching `name` is invoked via the Agent tool. |
| `settings.json` | At session start. |
| `settings.local.json` | At session start (if present). Overrides `settings.json`. |

## Overrides in nested repos

When Claude works inside `web-platform/` or `ai-platform/`:

1. Repo-local `<repo>/.claude/CLAUDE.md` supplements the workspace one (repo rules win on conflict).
2. Repo-local `<repo>/.claude/commands/<name>.md` shadows the workspace command of the same name.
3. Repo-local `<repo>/.claude/skills/<name>/` can extend or replace a workspace skill.
4. Repo-local `<repo>/.claude/settings.json` merges on top of the workspace one.

## House rules

- Keep `CLAUDE.md` under ~200 lines — it loads every turn. Detailed/situational knowledge lives in `.claude/knowledge/` and is pulled on demand.
- Personal scratch: meetings/plans/worklogs in `.docs/`; handoffs/reviews in `.claude/local/`.
- Anything personal that the agent should still see goes in `CLAUDE.local.md` (gitignored, auto-loaded).
- Never commit secrets to any file in this folder.
- Review `settings.json` permissions before broadening — auto-approvals apply to every session.
