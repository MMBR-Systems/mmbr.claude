---
name: commit
description: Stage and commit pending changes with a message that matches the repo's style. Trigger when the user asks to "commit", "comita isso", "salva mudanças", "commit changes", "commit and stop", or pastes context with commit-only intent (no push, no PR). Drafts the message, shows it, and waits for confirmation before committing. Never `git add -A`, never `--amend` without explicit ask, never `--no-verify`.
---

# Commit — focused commit workflow

Stages and commits pending changes. Use this when the user wants to commit and stop — not push, not open a PR. For the full ship-it flow (commit + push + PR), the `open-pr` skill takes precedence.

**Hard rules (never bypass):**
- Show the draft and wait for `y` before running `git commit`.
- Never `git add -A` / `git add .` — stage files explicitly.
- Never `--amend` unless the user asked by name.
- Never `--no-verify`. If a hook fails, fix the underlying issue and create a NEW commit.
- Never include secret values in the message (tokens, keys, credentials).

---

## Pipeline

### 1. Inspect state

Run in parallel:
- `git status` (no `-uall`)
- `git diff --staged` and `git diff` (unstaged)
- `git log -n 20 --pretty=format:'%s'` — learn the repo's commit style

### 2. Detect style

Look at the last 20 subjects:
- Conventional Commits (`feat:`, `fix:`, `chore(scope):`) → follow that exact convention, including scope usage.
- Imperative short subjects ("Add X", "Fix Y") → follow.
- Ticket-prefixed (`PROJ-123: ...`) → follow; extract ticket from branch name when possible.
- Mixed / no pattern → default to Conventional Commits.

### 3. Decide what's staged

- Nothing staged + unstaged changes exist → ask the user which files to include (or offer a sensible subset). Don't `git add -A` / `.`.
- Staged set mixes unrelated concerns → surface and suggest splitting into multiple commits. Don't split silently.
- Warn before staging files that look sensitive: `.env*`, `*credentials*`, `*.pem`, `id_rsa*`, `*.key`.

### 4. Draft the message

- Subject: ≤72 chars, imperative mood, no trailing period.
- Focus on the **why**, not a restatement of the diff.
- Body (optional, wrap at 72): only if there's non-obvious context — motivation, tradeoff, constraint.
- Reference ticket / issue if branch name or recent commits suggest one.

### 5. Show + confirm

Show the draft. Wait for the user's `y` unless they pre-authorized ("commit directly", "go").

### 6. Commit

Use HEREDOC to preserve formatting:

```bash
git commit -m "$(cat <<'EOF'
<subject>

<optional body>
EOF
)"
```

### 7. Hook failures

If a pre-commit / commit-msg hook fails:
1. Read the hook output.
2. Fix the underlying issue in the working tree.
3. Re-stage the affected files.
4. Create a **new** commit (never `--amend`; the failed commit didn't land).

### 8. Report

After success: `git status` and print the new commit hash + subject.

---

## Rules

- No marketing language ("massively improves", "blazing fast") — describe the change.
- Never commit files the user didn't ask to include.
- Never push as part of this skill — that's `open-pr`'s job.
- If there's literally nothing to commit, say so — don't create an empty commit.
- If the user's intent includes push or PR (e.g., "commit and PR this"), defer to `open-pr` instead of running this skill alone.
