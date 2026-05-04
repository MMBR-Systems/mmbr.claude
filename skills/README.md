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

- [`pr-review/`](./pr-review/) — structured PR review against a GitHub PR. Writes a local markdown artifact under `.claude/local/reviews/pr/<self|others>/` (routed by PR authorship). Posting to GitHub is a separate, opt-in flow.
