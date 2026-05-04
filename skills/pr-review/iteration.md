# Iteration N+1 — review handoff between rounds

Load this doc when reviewing a PR that has **already been reviewed at least once** by an agent (typically a fresh-context one) and the author then submitted fixes. The pattern is review → fix → re-review.

Without iteration handoff, a fresh-context reviewer:

- **Re-discovers the same findings** the previous round already raised → noise, wasted tokens.
- **Doesn't validate** that the previous fixes actually resolved what was flagged.
- **May regress on accepted tradeoffs** (flag a finding the team explicitly chose to accept).

This protocol fixes those.

---

## Inputs for iteration N+1

In addition to the standard inputs (PR URL, ticket context, ADRs, known-issues, banned-patterns), the user provides the **previous review's findings with status**:

```yaml
previous_review:
  artifact_path: .claude/local/reviews/pr/others/2026-04-26-myorg-api-42.md
  iteration: 1
  findings:
    - id: B1
      severity: blocking
      title: "Auth header parsed without validation"
      file: src/auth/parser.ts:42
      status: fixed                       # fixed | partially-fixed | accepted-as-is
      fix_commit: abc1234                 # optional — the commit that fixed it
      note: "..."                         # optional — explanation if partial/accepted
    - id: B2
      severity: blocking
      title: "Migration mutates 0042 file"
      file: db/migrations/0042-users.sql
      status: accepted-as-is
      note: "Team agreed in standup; rationale in ADR-024"
    - id: M1
      severity: major
      title: "N+1 in user lookup"
      file: src/api/users.ts:88
      status: partially-fixed
      note: "Reduced from N+1 to 2 queries; full fix needs join refactor — deferred to PROJ-457"
    - id: m1
      severity: minor
      title: "Naming: usrCnt"
      status: fixed
```

The user (or a wrapper) extracts this from the previous artifact and passes it as a prompt block.

---

## Pipeline (reviewer side)

Insert these steps into the standard `pr-review` flow, between Step 2 (load context) and Step 3 (analyze):

### Step 2.5 — Process previous findings

For each finding in `previous_review.findings`:

| Status | What this round does |
|---|---|
| `fixed` | Verify the fix landed: read the indicated file/line in the **current** diff. If the fix is still there and addresses the issue → no new finding. If the fix is missing/regressed → raise as **blocking regression**. |
| `partially-fixed` | Verify the partial fix landed. Note the deferred portion in this round's artifact under "Carry-forward findings" (don't re-raise as blocking unless the deferral is no longer acceptable). |
| `accepted-as-is` | Skip silently. Do not re-raise. The team already decided. |

Output a short **continuity table** at the top of the new artifact:

```markdown
## Continuity from iteration <N>

| ID | Title | Prev. status | This round |
|----|-------|--------------|------------|
| B1 | Auth header parsed without validation | fixed | ✓ verified fixed |
| B2 | Migration mutates 0042 file | accepted-as-is | (skipped per team decision) |
| M1 | N+1 in user lookup | partially-fixed | ✓ partial fix verified; full fix tracked in PROJ-457 |
| m1 | Naming: usrCnt | fixed | ✓ verified fixed |
```

### Step 3 — Analyze the diff (delta-focused)

Now analyze the diff with awareness of what was previously raised:

- **Focus on the delta**: changes since the previous review's commit (`gh pr diff <num> --since <prev-commit>` or compute from the artifact's recorded commit SHA).
- **Look for regressions** introduced by the fixes (a fix for B1 might break something near it).
- **Look for new issues** the previous round didn't surface (different reviewer, different blind spots).
- **Don't blindly re-raise** anything from the previous list; the continuity table covers those.

### Step 5 — Write artifact (with iteration context)

The new artifact filename includes `-v<N+1>`:

```
.claude/local/reviews/pr/others/2026-04-26-myorg-api-42-v2.md
```

Header includes:

```markdown
<!--
Iteration: 2 (previous: .claude/local/reviews/pr/others/2026-04-26-myorg-api-42.md)
Reviewer base commit: <SHA at start of this review>
Previous findings: 4 (3 fixed/partial, 1 accepted-as-is)
-->
```

Then: continuity table → new findings → recommendation.

---

## Rules for iteration N+1

- **Never re-raise an `accepted-as-is` finding.** The team's decision is durable; the reviewer doesn't re-litigate.
- **Always verify a `fixed` finding actually fixed.** If the fix was a no-op or only renamed the symptom, raise as a **regression** (not a duplicate).
- **`partially-fixed` is OK if there's a follow-up reference.** No follow-up linked = treat as still-open and consider re-raising at lower severity.
- **The continuity table is mandatory** in iteration N+1+ artifacts. Auditors need to see what carried over.
- **Cap iteration count** at 3 by default. Hard ceiling 5. After max, escalate to human review — automated re-review beyond that loses signal.

---

## Anti-patterns to avoid

- ❌ **Re-raising same findings without checking status.** Wastes the previous round's work.
- ❌ **Ignoring previous findings entirely** ("fresh context = fresh start"). Loses the audit trail and lets fixes go unverified.
- ❌ **Demoting `blocking` to `major` to look generous.** If something blocked merge in iter N and wasn't fixed, it still blocks in iter N+1. The team should explicitly accept-as-is or fix.
- ❌ **No commit SHA recorded.** Without the base commit, the reviewer can't compute the delta and ends up reviewing the whole PR again.
