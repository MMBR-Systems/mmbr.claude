---
name: pr-review
description: Produce a structured review document for a GitHub pull request. Trigger when the user asks to review a PR, pastes a GitHub PR URL, says "code review", "check this PR", or similar. The skill writes a local markdown artifact under .docs/reviews/pr/<self|others>/ (routed by PR authorship) — it does NOT post to GitHub unless the user explicitly asks afterwards. For posting, see posting.md.
---

# PR Review (artifact-first)

Goal: produce a thorough, structured review of a GitHub PR as a **local markdown file**. The artifact is the deliverable. Posting to GitHub is a separate step the user asks for explicitly (see `posting.md`).

Stays stack-agnostic: no framework-specific rules, no hardcoded ticket system. If `<repo>/.claude/` or `<repo>/.claude/skills/pr-review/` exists, repo-local rules override these generic ones.

**Never changes `cwd`.** All `gh` calls use `--repo <owner>/<repo>` derived from the PR URL — the user's local state is untouched.

---

## When to use this skill

Trigger on:
- User pastes a GitHub PR URL with any review intent ("review this", "what do you think of this PR")
- User says "code review", "review pr", "check pr"
- User invokes the skill explicitly

Do **not** trigger for:
- Reviewing local uncommitted changes (that's `/security-review` or just asking directly)
- Approving/merging without review (not this skill's job)

---

## Inputs

```
<PR-URL> [TICKET-URL-OR-PASTE]
```

- **PR URL** — required, canonical. Parse `owner`, `repo`, `number` from it.
- **Ticket context** — strongly encouraged. See `ticket-context.md` for the resolution flow (MCP → paste → skip).

If the user provided only intent without a PR URL, ask for it:
> *"Paste the PR URL:"*

Reject bare PR numbers — they're ambiguous in multi-repo workspaces.

---

## Pipeline

### 1. Resolve + fetch

Parse the URL. Confirm: `Reviewing <owner>/<repo>#<number>`.

Run in parallel:
```bash
gh pr view <number> --repo <owner>/<repo> --json title,body,author,baseRefName,headRefName,labels,state,mergeable,isDraft,statusCheckRollup
gh pr diff <number> --repo <owner>/<repo>
gh pr view <number> --repo <owner>/<repo> --json files
gh pr checks <number> --repo <owner>/<repo>
```

Minimum viable: diff + title. If `gh` fails (auth, access), ask the user to paste the diff manually.

**If the diff is large** (rough heuristic: >500 changed lines or >20 files) → load `large-diffs.md` before analyzing.

#### Sync local base ref (when a local clone is available)

`gh pr diff` returns the diff as GitHub computes it against the current base ref on the server, so the diff content itself is always fresh. But review work also reads **adjacent context** off the local clone — to verify line numbers, check repo conventions, look up the existing function being modified, etc. If the user's local checkout of `<base-ref>` is stale, those reads are against an outdated tree and citations drift.

When a local clone of `<owner>/<repo>` is reachable in the workspace (search the workspace map / sibling directories for a matching folder), fetch the base ref before reading any adjacent context from disk:

```bash
git -C <clone-path> fetch <remote> <baseRefName>
```

This is non-destructive — `fetch` only updates remote-tracking refs; it never moves `HEAD`, switches branches, or touches the working tree. The user's local state is preserved.

When reading files for surrounding context, prefer:

```bash
git -C <clone-path> show <remote>/<baseRefName>:<path>
```

over `cat <path>` / `Read <abs-path>`. The working tree may sit on a stale base, especially for PRs against an active `main`. Findings that cite line numbers should match the PR's view (i.e. base ref as fetched), not the user's stale checkout. If you must cite a location, prefer a structural description ("the `asyncio.gather` block inside `_method_name`") over a line number when the line is in unchanged surrounding code — line numbers in pre-existing code shift whenever main moves.

If no local clone is reachable, all reads must go via `gh api repos/<owner>/<repo>/contents/<path>?ref=<baseRefName>` or `gh pr diff` — never assume disk content represents either the PR branch or current base.

### 2. Load context (ticket + workspace knowledge)

#### 2a. Ticket context

Load `ticket-context.md` and follow its resolution flow. Ticket context is used **only for analysis** — it never appears in the written review (privacy).

#### 2b. Decisions / ADRs (filtered by blast radius)

If `.claude/docs/adr/` exists in the workspace or the target repo:

1. List all `*.md` in `adr/` (or read its index).
2. Filter to ADRs whose content references files/paths/symbols in the diff (blast radius). Skim each candidate's body for path-like strings; load only the matches.
3. Include the loaded ADRs as analysis context. **Do not re-flag decisions documented in an ADR** — surface the ADR reference in the finding (or skip the finding) if a candidate concern is already addressed.

If too many ADRs match (>5), load titles only and ask the user which to expand.

#### 2c. Known issues / gotchas

If `.claude/docs/known-issues/` exists:

- Load all files (they're meant to be short — ≤150 lines each).
- Use as a "false-positive shield": when a candidate finding matches a documented known-issue, do not raise it. Reference the known-issue file in the artifact's "Notes" section instead.

#### 2d. Banned patterns (auto-CRITICAL rules)

If `<repo>/.claude/banned-patterns.md` exists:

- Parse the rules (each with pattern + severity + rationale).
- Run regex / literal checks against the diff for each rule's pattern (or detection hint if provided).
- **Every match → automatic CRITICAL/HIGH finding** in the analysis. No judgment exercised — these are team policy.
- Quote the rule's "Why" in the finding's reason; quote the "What to do instead" as the suggestion.

#### 2e. Iteration N+1 (if previous review exists)

If the user provided previous-review findings (or pointed at a previous artifact in `.docs/reviews/pr/<self|others>/`), load `iteration.md` and follow that protocol. The continuity table comes before new findings.

### 3. Analyze the diff

Read every changed hunk. Evaluate across these universal categories (skip ones that don't apply):

- **Requirements fit** (only if ticket context was provided) — does the diff implement the stated scope? missing acceptance criteria? scope creep beyond the ticket?
- **Security** — injection, authn/authz gaps, secrets committed, unsafe deserialization, XSS, SSRF, missing input validation at trust boundaries
- **Bugs / logic** — off-by-one, null/undefined paths, race conditions, inverted conditions, unhandled error branches, wrong loop bounds
- **Performance** — N+1 queries, unbounded loops, sync work on hot paths, unnecessary allocations in tight loops
- **Tests** — missing coverage for new branches, assertions that assert nothing, flaky patterns (time/random/network without control)
- **Code quality** — dead code, unclear naming, duplicated logic, magic values, inconsistent error handling
- **Architecture** — layering violations, circular deps, responsibilities leaking across modules, abstractions that pay no rent

Don't invent stack-specific rules the repo hasn't declared.

### 4. Classify each finding

One severity per finding:

- **Blocking** — must fix before merge. Security issue, data-loss risk, breaks existing behavior, violates a public contract, misses a stated acceptance criterion.
- **Major** — should fix before merge. Clear bug with bounded impact, missing tests for new logic, significant perf regression, architectural drift.
- **Minor** — nit / optional improvement. Naming, small duplication, cleanup opportunity.

When uncertain, pick the lower severity.

### 5. Write the artifact

**Pick the subfolder by authorship.** Compare the PR's `author.login` (from the `gh pr view` output) with the current GitHub user (`gh api user --jq .login`):

- **Same login** → `self/` (you're reviewing your own PR before pushing for review)
- **Different login** → `others/` (you're reviewing a teammate's PR)
- **Detection failed** (no `gh` auth, etc.) → default to `others/` and note this in the artifact's Summary.

Write to `.docs/reviews/pr/<self|others>/<YYYY-MM-DD>-<owner>-<repo>-<number>.md`. Create the directory if missing. If a file with the same date already exists, append `-v2`, `-v3`, etc.

Use this exact structure:

```markdown
# PR Review — <owner>/<repo>#<number>

<!--
Generated: <YYYY-MM-DD HH:MM>
PR: <url>
Author: <author>
Branches: <head> → <base>
State: <open|draft|merged|closed>
CI: <pass|fail|pending|n/a>
Ticket: <url or "not provided">
-->

## Summary
<2–3 sentences: scope, overall read, whether blocking issues exist, whether it matches the ticket if context was provided>

## Findings

### Blocking
<numbered findings; if none, write "None.">

### Major
<numbered findings; if none, write "None.">

### Minor
<numbered findings; if none, write "None.">

## Positive notes
<real observations of what was done well — omit the section if nothing genuine to say>

## Recommendation
<APPROVE | REQUEST_CHANGES | COMMENT> — <one-line why>

---

<!-- When the user asks to post this, see .claude/skills/pr-review/posting.md -->
```

Each finding inside a severity section:

```markdown
#### <N>. <one-line title> — `<category>`
- **File:** `path/to/file.ext:LINE`
- **Issue:** <what's wrong, specific to this code>
- **Suggestion:**
  ```<lang>
  <concrete fix>
  ```
```

Rules for findings:
- No generic advice. Name the variable, propose the rename.
- One finding per issue.
- Always cite file + line.
- Always suggest the fix, don't just point.

### 6. Report back

After writing, print:
- Path of the artifact
- Count by severity (`Blocking: N / Major: N / Minor: N`)
- Recommendation
- One-line offer: *"Want me to post this as a review, or as inline comments? (see posting.md)"*

Do **not** post. Do **not** run `gh pr review`. Writing the file is the end of this skill's job.

---

## Privacy rules

- Pasted ticket content is **never** written into the artifact. Only the ticket URL (if provided) goes into the header.
- Secret values found in the diff (tokens, keys, credentials) are **never** quoted verbatim. Cite the file/line, describe the issue, redact the value. Flag as Blocking.

---

## Sub-docs

- [`ticket-context.md`](./ticket-context.md) — load when resolving the ticket input (MCP fetch, paste fallback, skip handling).
- [`large-diffs.md`](./large-diffs.md) — load when the diff is large enough to risk context overflow.
- [`iteration.md`](./iteration.md) — load when this is the second (or later) review of the same PR, with previous findings to carry forward.
- [`posting.md`](./posting.md) — load only when the user explicitly asks to post the review to GitHub.
