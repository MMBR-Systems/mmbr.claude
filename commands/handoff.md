---
description: Generate a session handoff document for the next conversation
---

Before `/clear`, capture this session's state so the next agent (or future-you) can continue **without asking a single question**. That's the bar.

## Steps

1. Use current timestamp **plus a short kebab-case context slug** for the filename: `.docs/handoffs/<YYYY-MM-DD>-<HHMM>-<slug>.md` (24h local).
   - The slug is 3 to 6 words, kebab-case, summarizing the session's main thread so files are scannable without opening them.
   - Examples: `2026-05-01-0742-gap-dashboard-pr-37.md`, `2026-04-22-2319-qbricks-runtime-env-fix.md`, `2026-04-15-0930-figma-mcp-onboarding.md`.
   - The subfolder already indicates this is a handoff — no `handoff-` prefix in the filename.
2. Write the file using the sections below in order. Skip sections that truly don't apply (mark `N/A`, don't omit the heading — missing sections are a red flag for the next reader).
3. After writing, print the path and a 1-paragraph summary.

## Required sections (use these exact headings)

### Goal / context
One paragraph: what the user was working on and why. Tie it to business context if applicable (ticket, sprint goal, external deadline).

### Environment / setup
The physical state of the workspace right now. Someone sitting at a cold terminal needs this to avoid running things in the wrong place.

```
- Repos touched: <list with paths>
- Current branches: <repo → branch>
- Environment(s) targeted: <local | dev | qa | prod>
- Services running: <what's up locally, ports>
- Relevant versions: <Node, Python, pnpm, Docker Compose file used>
- AWS profile(s) active: <profile names>
- Docker state: <containers up / down, volumes touched>
```

### Work done
Bullet list. **Force format:** `- [TYPE] description (path or URL)`. Types: `[REVIEW]`, `[PR]`, `[LOCAL]`, `[AWS]`, `[DB]`, `[DOC]`, `[ENV]`, `[DEPLOY]`, `[CONFIG]`, `[RESEARCH]`.

Example:
```
- [REVIEW] Posted inline comments on ai-platform PR #14 (review 4155395263)
- [ENV] Updated ai-platform/.env.api with new external API config
- [LOCAL] Recreated docker compose containers (`docker compose up -d --force-recreate`)
- [DB] Confirmed workflow 4c8e3d81-... is PUBLISHED in qbrick postgres
```

No narrative paragraphs. No "I did X because Y" — save the *why* for "Decisions made".

### Decisions made
Non-obvious choices that shaped the work. Each entry:
```
- Decision: <what was decided>
  Why: <the reason, briefly>
  Affects: <what downstream work depends on this>
```

Skip trivial decisions. Include only ones a reviewer might question later.

### State — done / in progress / blocked
Three sub-lists, each bullet one line:

**Done** — shipped / merged / deployed / verified. Past tense.
**In progress** — started but not finished. Format: `- <task> — last step: <X>; next step: <Y>`
**Blocked** — waiting on external. Format: `- <task> — blocked on: <who/what>; unblock criteria: <what changes>`

### Next steps (ordered, first-action-ready)
Numbered list. Each step uses this structure:

```
N. Action: <verb phrase>
   Command: <exact command, or N/A if manual>
   Expected result: <what success looks like — state change, file created, output match>
   If it fails: <first debug move>
```

Don't write "test API" — write "send POST to /workflows/{id}/invoke with X, expect 200 with `message_id` in response".

### Known issues / bugs
Active defects discovered or still pending. Each entry:
```
- Issue: <one-line description>
  Impact: <what breaks, who sees it>
  Where: <file:line or service>
  Probable cause: <best current theory>
  Workaround: <if any>
```

Distinguish from "TODOs" (deferred work) — issues = things actively wrong right now.

### Files modified this session
Group by repo. Path + one-line description each.
```
### web-platform
- `.env.local` — updated QAP_* with new workflow credentials

### ai-platform
- `.env.api` — rewrote with Databricks RAG config
```

### Commands run (optional but encouraged)
Key commands that changed state, for reproduction/rollback. Omit trivial reads.
```bash
docker compose up -d --force-recreate
git push origin main
aws ecs update-service --cluster ecs-dev --service web-platform-dev --force-new-deployment
```

### IDs, URLs, credentials to remember
**Never paste secret values.** Names/keys/UUIDs only.
- Workflow UUIDs, API key names (not values), secret names
- ALB DNS, Auth0 tenant, Databricks workspace URL
- Account IDs, regions, cluster/service names
- RDS endpoints, ElastiCache endpoints

### Gaps / TODOs pending
Items explicitly deferred. Format: `- <task> — owner: <user|infra|backend|sre|…>; priority: <blocker|soon|later>`

Distinguish from "Known issues" (active defects) and "Next steps" (things to do right now).

### Open questions
Actual unresolved questions. Frame as questions, not recommendations.
- Decision-pending items the team hasn't resolved
- Technical unknowns that need investigation

### Context for next agent
Operational notes that don't fit elsewhere. This section is what turns "good handoff" into "seamless continuity". Cover at least:

- **User behavior patterns** — prefers fast vs robust? terse vs detailed? language preference?
- **Hard rules** — things never to do in this project (e.g. "never commit to `.docs/`", "never change `main` without review")
- **Recent course corrections** — things the user pushed back on this session
- **Permission limits** — hooks that blocked actions, AWS accounts user can't access
- **Active external threads** — ongoing Slack conversations, PRs under review, pending asks
- **Stale context to ignore** — old memories/notes that no longer apply

## Style

- Terse, factual, scannable. No marketing language, no hedging.
- Tables when comparing state across environments / services / branches.
- Code fences for commands, paths, SQL, JSON.
- **Never include secret values** (keys, passwords, JWT secrets, API secrets, tokens). Names/keys only.
- Write in the same language the user used this session (PT-BR, EN, etc).
- Self-contained: don't reference "as discussed earlier" — the next agent has no earlier.

## The test

Before saving, re-read it and ask: *can the next agent execute step 1 of "Next steps" without asking me anything?* If no, fix the gap.
