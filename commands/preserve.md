---
description: Save a durable fact or decision into .claude/knowledge/ (cross-session, team-shareable)
---

Capture a piece of knowledge that should survive future `/clear` operations and inform work weeks from now. This is different from `/handoff` (session-local operational state) and from auto-memory (small discrete facts loaded every session).

## When to use `/preserve`

Use this when the user discovers or decides something that answers *"how does this system work?"* rather than *"where did I stop?"*:

- An architectural decision ("we chose X over Y because Z")
- A recurring pattern used across the codebase
- An integration contract with an external service
- A known issue / gotcha with a diagnosed cause
- A runbook for an operation (deploy, seed, provision)
- A glossary clarification

**Don't `/preserve`:**
- Session-specific state → that's `/handoff`
- Small behavioral rule ("user prefers X") → that's auto-memory (`memory/feedback_*.md`)
- Task-specific notes → that's the task's own plan
- Transient observations that may change next week
- Strictly personal content → write directly into `.docs/` (private repo)

## Steps

1. **Classify the fact.** Pick the target subfolder in `.claude/knowledge/`. Files captured here are team-shareable (tracked in git). If the fact is genuinely personal/throwaway, don't use `/preserve` — write it to `.docs/` directly.

   | If the fact is… | Save under |
   |------------------|-----------|
   | A decision with trade-offs and a reason | `decisions/why-<short-name>.md` |
   | A system design or data-flow explanation | `architecture/<topic>.md` (or `architecture/<module>/...`) |
   | A gotcha / bug / surprising behavior | `known-issues/<short-name>.md` |
   | A recurring recipe, glossary, external API contract, workspace convention | `reference/<topic>.md` |
   | A behavioral rule for agents | **stop — use auto-memory instead** |

2. **Check for an existing file.** Glob the target folder. If a matching file exists, append/edit rather than duplicate. Prefer updating over creating.

3. **Write the file** with YAML frontmatter at the top:
   ```yaml
   ---
   created: YYYY-MM-DD
   updated: YYYY-MM-DD
   owner: <user>
   ---
   ```
   - On first creation, set both `created` and `updated` to today's date.
   - When editing an existing file: update only `updated`. Never touch `created` — it's an immutable record of when the doc was first captured.
   - Filename stays topic-named (e.g., `why-db-role-not-jwt-claim.md`); the date lives in frontmatter so cross-references stay stable.

   Content structure depends on category — use the shape typical for that folder (check sibling files first).

4. **Print:**
   - Path of the file created/updated
   - Whether it's new or updated
   - A one-line description of what was preserved

## Shapes by category

### `decisions/why-<name>.md`
ADR-style, but lightweight.
```markdown
---
created: YYYY-MM-DD
updated: YYYY-MM-DD
owner: <user>
---

# Why <decision>

## Context
What problem are we solving, what constraints?

## Decision
What did we choose?

## Alternatives considered
What did we reject, and why?

## Consequences
What does choosing this lock us into? What's the cost?
```

### `known-issues/<name>.md`
```markdown
---
created: YYYY-MM-DD
updated: YYYY-MM-DD
owner: <user>
---

# <Issue>

## Symptom
What does the user / developer see?

## Where
File / service / environment.

## Cause
Root cause, or best theory.

## Workaround
Current mitigation.

## Fix (if planned)
Link to ticket / PR, or "deferred".
```

### `architecture/<topic>.md`
Free-form. Mermaid diagrams, queue/event flows, service cards. Check sibling files in the folder for the shape.

### `reference/<topic>.md`
Catalog-style. Glossaries, repo bookmarks, external API contracts, workspace conventions. Match the shape of existing siblings.

## Rules

- **No narrative.** Not "yesterday we did X"; that's handoff territory.
- **Short files.** If >150 lines, split.
- **Keep it truthful.** If you don't know the root cause, say so — don't invent one.
- **No secret values.** Keys, tokens, passwords never appear.
- **Update, don't duplicate.** If a topic exists, extend it.
- **If unsure whether it belongs in knowledge or memory**, ask: *does it need explanation/structure?* If yes → knowledge. If it's a one-liner rule → memory.

## Anti-goal

`.claude/knowledge/` is not a dump of everything learned. It's curated and shared with the team. Better to skip a preserve than to add noise. The test: *will someone on the team read this 6 weeks from now and find it useful?* If no, skip — or write to `.docs/` instead if it's personal.

