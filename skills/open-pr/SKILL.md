---
name: open-pr
description: Commit, push, and open a GitHub Pull Request as one orchestrated workflow. Trigger when the user asks to "create a PR", "open a PR", "ship this", "let's PR this", "push and PR", "ready for review", or pastes branch context with PR intent. Each destructive step (commit / push / gh pr create) requires explicit user confirmation — the skill never acts unilaterally on shared state.
---

# Open PR — commit + push + PR workflow

Orchestrates the three steps that ship work: commit pending changes, push the branch, and open the GitHub PR with a description grounded in the full branch diff. Inspects state first to decide which steps actually need to run.

**Hard rules (never bypass):**
- Each destructive step (commit, push, `gh pr create` / `gh pr edit`) requires explicit user `y` before running.
- Never `git add -A` / `git add .` — stage files explicitly.
- Never `--no-verify`, never `--force` (unless the user asks for it by name).
- Never include secret values (tokens, keys, credentials) in any output.
- Never invent ticket context. If branch name / commits don't reference a ticket, skip the linkage.

---

## Pipeline

### Step 1 — Inspect state

Run in parallel:
- `git status` (no `-uall`)
- `git diff --staged` and `git diff` (unstaged)
- `git log -n 20 --pretty=format:'%h %s'` — learn the repo's commit style
- `git symbolic-ref refs/remotes/origin/HEAD` → base branch (fallback: `main`, then `master`, then `develop`)
- `git rev-list --count <base>..HEAD` — commits on this branch
- `git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null` — does the branch track a remote?
- `gh pr view --json number,state,url 2>/dev/null` — does a PR already exist?

Decide which phases need to run:
- **Commit** needed: there are unstaged / partially-staged changes the user wants in the PR.
- **Push** needed: branch has unpushed commits, or no upstream tracking.
- **PR creation** needed: no PR exists yet for this branch.
- **PR update** needed: PR exists and the user wants the description refreshed.

Print a one-line state summary and wait for `y`:
> *"Branch `feat/x`: 3 unstaged files, 2 unpushed commits, no PR yet. Will commit → push → open PR. Confirm? (y/N)"*

Skip phases that aren't needed (e.g., if working tree is clean and branch is pushed, jump straight to Step 4).

---

### Step 2 — Commit (if needed)

Follow the `commit` skill's pipeline (`.claude/skills/commit/SKILL.md`) — same rules apply: detect repo's commit style, no `git add -A`, draft message focused on the *why*, show and confirm, HEREDOC commit, never `--amend` / `--no-verify`. After commit succeeds, return here for Step 3.

---

### Step 3 — Push (if needed)

- No upstream → `git push -u origin <branch>`. Confirm first.
- Has upstream + unpushed commits → `git push`. Confirm first.
- On non-fast-forward rejection: surface and ask — don't auto-rebase or `--force`.

---

### Step 4 — PR title + body

#### If a PR already exists for this branch:

Ask:
> *"PR #N (`<state>`) already exists at `<url>`. Update its description, or skip? (update / skip)"*

If `update`: regenerate body using the rules below, show the draft, then `gh pr edit <N> --body "..."` after confirmation. Don't change title without asking.

#### If no PR exists:

1. Detect template (first found wins): `.github/PULL_REQUEST_TEMPLATE.md`, `.github/pull_request_template.md`, `docs/pull_request_template.md`.
2. Read template if present — match its structure exactly (section order, headings, checkboxes). Don't invent new sections.
3. If no template, default to:
   ```markdown
   ## Summary
   <1–3 bullets: what changed and why, focused on reviewer value>

   ## Changes
   <bullets grouped by concern — not a commit-by-commit replay>

   ## Test plan
   - [ ] <concrete verification step>
   - [ ] <concrete verification step>

   ## Notes for reviewer
   <optional: tricky areas, deliberate tradeoffs, follow-ups deferred>
   ```

**Title rules:**
- ≤70 chars.
- Match the repo's commit history style (Conventional Commits, ticket prefix, etc. — detect from `git log`).
- Describe the outcome, not the activity ("Add X validation", not "Work on validation").

**Body rules:**
- Summarize the **full branch**, not just the latest commit.
- Group related changes; don't list every file.
- Test plan must be concrete — specific commands, URLs, scenarios. "Tested manually" is not a test plan.
- Link tickets/issues if the branch name or commits reference one (e.g., `MMBR-180` from branch `feat/mmbr-180-x`).
- Flag anything a reviewer would miss from the diff alone: migrations, env var changes, feature flags, breaking changes.

Show the draft to the user. Wait for `y` before opening.

---

### Step 5 — Create the PR

```bash
gh pr create --title "..." --body "$(cat <<'EOF'
<body>
EOF
)"
```

If the user asked for a draft, append `--draft`. Otherwise default to ready-for-review.

After success: print the PR URL and a one-line recap (branch, base, # commits, # files).

---

## State-aware shortcuts

- **All three steps needed (uncommitted + unpushed + no PR):** full pipeline.
- **Working tree clean + unpushed commits + no PR:** Steps 3 → 4 → 5.
- **Working tree clean + branch fully pushed + no PR:** Steps 4 → 5.
- **Working tree clean + branch pushed + PR exists:** ask "update description?" — Step 4 (update mode) only.
- **Working tree has WIP-looking commits (`fixup!`, `wip`, `tmp`):** ask if user wants to squash/rebase before pushing. Don't auto-rebase.

## Privacy

- Never paste secret values into commit messages, PR title, or body.
- Never include `.docs/` paths in any committed/posted text (per workspace boundary rule: `.docs/` is personal).

## When to defer to the `commit` skill alone

If the user explicitly says "just commit" / "só comita" / "não abre PR", stop after the commit phase. Don't push, don't open PR. The `commit` skill is the canonical entry point for commit-only intent — if `open-pr` fired by mistake, hand off and stop.
