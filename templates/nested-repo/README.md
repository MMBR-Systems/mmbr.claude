# Nested-repo `.claude/` template

Copy this folder into a new repo as `<repo>/.claude/` to give it its own agent config that supplements the workspace-level one.

## Minimal setup

1. Copy `CLAUDE.md` into `<repo>/.claude/CLAUDE.md`.
2. Fill in the purpose line, stack, entry points, and any repo-specific rules.
3. Done — Claude auto-loads it whenever working inside this repo.

## Optional additions

Create these only when you actually need them — empty is fine, the workspace versions are available by default:

- `<repo>/.claude/commands/<name>.md` — shadows the workspace command of the same name inside this repo.
- `<repo>/.claude/skills/<name>/` — shadows or extends the workspace skill of the same name. Can reference workspace sub-docs or replace them entirely.
- `<repo>/.claude/settings.json` — merges on top of workspace settings (e.g. repo-specific bash allows).
- `<repo>/.claude/agents/<name>.md` — repo-scoped subagent.
- `<repo>/.claude/banned-patterns.md` — auto-CRITICAL rules the `pr-review` skill enforces inside this repo. Copy `banned-patterns.md` from this template as a starting point. Create only if the team has hard rules ("we got burned by X, never again") that should never require judgment.

## What not to copy

Do **not** copy workspace commands/skills wholesale. Empty is better than a stale duplicate — the workspace versions are available by default. Only add a local file when you're genuinely customizing.
