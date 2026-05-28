# Skills

Skills are progressive-disclosure capabilities auto-loaded by Claude when the user's request matches a skill's `description` frontmatter. Unlike slash commands, skills can span multiple files and branch into sub-docs loaded only when needed.

## Layout

Each skill lives in its own folder:

```
skills/<skill-name>/
├── SKILL.md          # required — frontmatter + core flow
└── <sub-doc>.md      # optional — loaded by SKILL.md when relevant
```

## Frontmatter

```markdown
---
name: skill-name
description: When to trigger this skill. The description is the auto-load signal — be specific about trigger phrases, URL patterns, or intent keywords.
---
```

## When to add a skill vs a command

- **Command** — single linear flow, invoked explicitly via `/name`. Example: `/commit`.
- **Skill** — branching logic, multiple files, auto-triggers on context. Example: `pr-review`.

Rule of thumb: if a capability has >3 clear edge cases that each need their own handling, it's a skill.

## Override in nested repos

`<repo>/.claude/skills/<same-name>/` takes precedence over the workspace skill of the same name when Claude is working inside that repo. The repo-local skill can reference workspace sub-docs or replace them entirely.

## Current skills

- [`pr-review/`](./pr-review/) — structured PR review against a GitHub PR. Writes a local markdown artifact under `.docs/reviews/pr/<self|others>/` (routed by PR authorship). Posting to GitHub is a separate, opt-in flow.
- [`grill-me/`](./grill-me/) — interview-style alignment. Walks the design tree one question at a time before any plan is committed.
- [`grill-with-docs/`](./grill-with-docs/) — same interview as `grill-me`, but sharpens terminology against `.claude/CONTEXT.md` and writes ADRs (`.claude/docs/adr/`) inline when a decision is hard to reverse, surprising without context, and a real trade-off.
- [`zoom-out/`](./zoom-out/) — invoked explicitly via `/zoom-out`. Asks the agent to step up a layer and map relevant modules/callers using domain vocabulary.
- [`diagnose/`](./diagnose/) — disciplined 6-phase bug/perf diagnosis: build feedback loop → reproduce → hypothesise → instrument → fix + regression test → cleanup.
- [`improve-codebase-architecture/`](./improve-codebase-architecture/) — finds **deepening opportunities** (shallow → deep modules). Reads `.claude/docs/architecture/` for domain vocabulary and `.claude/docs/adr/` for ADRs.
- [`tdd/`](./tdd/) — red-green-refactor with vertical-slice discipline. Anti-pattern guards against AI's tendency to write tests that validate the wrong behavior. Examples are in TypeScript but principles apply to Python/pytest in `ai-platform/`.

## Attribution

`grill-me`, `grill-with-docs`, `zoom-out`, `diagnose`, `improve-codebase-architecture`, and `tdd` were adapted from [Matt Pocock's `skills` repo](https://github.com/mattpocock/skills) (MIT, © 2026 Matt Pocock). Background: [Full Walkthrough: Workflow for AI Coding](https://www.youtube.com/results?search_query=matt+pocock+workflow+for+ai+coding). Paths were retargeted to `.claude/docs/` layout; otherwise the prose is his.
