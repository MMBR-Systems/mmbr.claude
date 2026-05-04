# Posting a review to GitHub

Load this doc only when the user **explicitly asks** to post a review artifact to the PR. `SKILL.md` never posts on its own.

Trigger phrases: *"post this review"*, *"send as inline comments"*, *"approve"*, *"request changes on this PR"*, etc.

---

## Inputs

- The **artifact path** (e.g. `.claude/local/reviews/pr/<self|others>/<YYYY-MM-DD>-<owner>-<repo>-<number>.md`). If multiple artifacts exist for the same PR, ask which one.
- The **posting mode**:
  - **Single review body** — one comment containing the whole markdown.
  - **Inline comments** — one GitHub comment per finding, anchored to file + line.
  - **Hybrid** — Summary + Recommendation as the review body; findings as inline comments.

Ask the user which mode if they didn't specify.

---

## Pre-flight checks (run before any `gh` call)

Do these in parallel to catch errors early instead of mid-post:

1. **Auth** — `gh auth status`. If not authenticated for the target org, abort with instructions.
2. **Self-review** — fetch the PR author (`gh pr view <num> --repo <o>/<r> --json author`). Compare to `gh api user --jq .login`.
   - If author == current user → GitHub blocks `--approve`. Offer: *"This is your own PR. You can't approve it. Post as a comment-only review instead? (y/N)"*
3. **Existing review by you** — `gh api "repos/<o>/<r>/pulls/<num>/reviews" --jq '[.[] | select(.user.login == "<me>")] | length'`.
   - If >0 → ask: *"You've already posted N reviews on this PR. Post another, or cancel? (another/cancel)"* Do not attempt to edit/update existing reviews — `gh` doesn't support that cleanly. A new review is the safe path.
4. **PR state** — if state is `MERGED` or `CLOSED`, ask: *"This PR is `<state>`. Still post? (y/N)"* Most reviews on closed PRs are unintentional.
5. **Draft PR** — if `isDraft`, mention it: *"PR is a draft. Posting anyway (common for early feedback) — confirm? (y/N)"*

Only proceed when all pre-flights pass or the user explicitly accepts.

---

## Selection step

Parse the artifact. List every finding as:

```
[1] [Blocking] <title>       — file:line
[2] [Blocking] <title>       — file:line
[3] [Major]    <title>       — file:line
[4] [Minor]    <title>       — file:line
...
```

Prompt:
```
Which findings to include?
  [a] all
  [b] blocking + major only
  [c] specific numbers (e.g. 1,3,5)
  [d] exclude (e.g. -4)
  [x] cancel
```

Re-list with the filter applied. Repeat until confirmed.

---

## Recommendation gate

Based on the **selected** findings:

| Selected severity mix | Default recommendation |
|------------------------|------------------------|
| Any Blocking           | `REQUEST_CHANGES` |
| Only Major             | `REQUEST_CHANGES` (user may switch to `COMMENT`) |
| Only Minor             | `APPROVE` or `COMMENT` |
| None                   | `APPROVE` |

Show the recommendation. Let the user override — except: **if any Blocking is still selected and the user tries to `APPROVE`, surface the conflict and refuse silently. Ask them to either drop the Blocking or switch to `REQUEST_CHANGES` / `COMMENT`.**

---

## Posting

### Single review body

```bash
gh pr review <num> --repo <o>/<r> <flag> --body "$(cat <<'EOF'
<review markdown — summary, findings, recommendation>
EOF
)"
```

Flags: `--approve`, `--request-changes`, `--comment`. Exactly one.

### Inline comments

For each selected finding:

```bash
gh api -X POST "repos/<o>/<r>/pulls/<num>/comments" \
  -f path="<file>" \
  -F line=<line> \
  -f side="RIGHT" \
  -f commit_id="<HEAD-SHA-of-PR>" \
  -f body="$(cat <<'EOF'
**[<severity>] [<category>]** <title>

<issue>

**Suggestion:**
```<lang>
<fix>
```
EOF
)"
```

Get the HEAD SHA from the initial `gh pr view` fetch. Verify the file still exists at that SHA before posting each comment; otherwise the API rejects.

Don't batch silently — print each comment's status (`posted`, `failed`) as you go.

### Hybrid

1. Post inline comments for each finding (as above, but without the recommendation).
2. Post a short review body with Summary + Recommendation only:

```bash
gh pr review <num> --repo <o>/<r> <flag> --body "$(cat <<'EOF'
## Summary
<from artifact>

## Recommendation
<APPROVE | REQUEST_CHANGES | COMMENT>

See inline comments for details.
EOF
)"
```

---

## After posting

- Print the review URL (`gh pr view <num> --repo <o>/<r> --json reviewDecision,reviewRequests`).
- Print a count: `Posted: <N> findings inline, 1 review body` (or whichever applies).
- Mark the artifact: append a trailer to the file:
  ```markdown
  ---
  <!-- Posted: <YYYY-MM-DD HH:MM> — mode: <body|inline|hybrid>, recommendation: <APPROVE|REQUEST_CHANGES|COMMENT> -->
  ```
  So it's clear the artifact has already been used.

---

## Rules

- Never post without explicit user confirmation at the selection + recommendation steps.
- Never approve a PR that still has a Blocking finding selected.
- Never include secret values (tokens, keys, credentials) in any posted comment — even if the author committed them. Cite file/line, describe the issue, redact the value.
- Never edit or delete existing reviews/comments from other users.
- Never push commits or modify the PR branch.
