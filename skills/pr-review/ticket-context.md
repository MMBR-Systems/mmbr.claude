# Ticket context resolution

Load this doc from `SKILL.md` step 2. It defines how to obtain the ticket the PR is supposed to implement, so the review can judge **requirements fit** — not just code quality.

Ticket context is **strongly encouraged**. Without it, the review can't tell whether the PR solves the right problem.

---

## Resolution order

Given the optional second argument to the skill:

### Case 1 — Arg is a ticket URL, and an MCP exists for that system

Detect the system from the URL:

| URL pattern | System |
|-------------|--------|
| `*.atlassian.net/browse/*` | Jira |
| `linear.app/*/issue/*` | Linear |
| `github.com/*/issues/*` | GitHub Issues |
| `*.notion.site/*` or `notion.so/*` | Notion |
| other | try a generic/available MCP; if none matches, go to Case 2 |

Try to fetch via the matching MCP. If fetch succeeds:
- Use the ticket's **title, description, acceptance criteria** as analysis context.
- Store the URL to include in the artifact header.

### Case 2 — Arg is a URL but no MCP / fetch failed

Prompt:
> *"Couldn't fetch `<url>` automatically (no MCP configured for this ticket system, or fetch failed). Paste the ticket content below — title, description, acceptance criteria. Press enter on an empty message to skip."*

Use the pasted text as context. Still put the URL in the artifact header.

### Case 3 — Arg is plain text (not a URL)

Treat it as already-pasted ticket content. No URL to link in the header.

### Case 4 — No arg provided

Prompt:
> *"Ticket context (Jira/Linear/GitHub Issue/Notion/etc.)? Paste a URL, paste the ticket content directly, or press enter to skip:"*

Route the response:
- Looks like a URL → Case 1 or 2.
- Multi-line text → Case 3.
- Empty → Case 5.

### Case 5 — User explicitly skipped

Warn:
> *"Proceeding without ticket context. The review will assess code quality only — it won't be able to judge whether the PR meets requirements. Continue? (y/N)"*

- `N` → return to Case 4.
- `y` → proceed. In the artifact, write `Ticket: not provided` and skip the "Requirements fit" analysis category.

---

## Privacy

Pasted ticket content is used **only during analysis**. It is never:

- Written into the review artifact body.
- Quoted in any finding.
- Echoed back to the user.

The artifact header may contain the ticket **URL** (if one was provided). Nothing more.

---

## What ticket context actually changes in the review

When provided, the skill evaluates the diff against the ticket's acceptance criteria:

- Does the diff touch the things the ticket asked for?
- Are there AC items the diff doesn't address?
- Is there code that goes beyond the ticket's scope (scope creep)?

Missing AC → usually a **Blocking** finding under *Requirements fit*.
Scope creep → usually **Major** (unless the extra code looks harmful, then Blocking).
