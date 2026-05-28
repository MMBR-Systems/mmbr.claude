# Banned patterns

Patterns this repo has explicitly banned. The `pr-review` skill (and any reviewer agent following the pattern) reads this file when working inside the repo and treats matches as **auto-CRITICAL** findings — no judgment exercised by the reviewer, since the team already decided.

## Why this file exists

LLM reviewers exercise judgment on style and design — useful, but variable. For things the team has already decided ("we got burned by X, never again"), judgment is wrong; rule enforcement is right.

This file makes those rules **machine-checkable in spirit** (the LLM regex-grep + flags) without needing a separate lint config per rule.

## Format

Each banned pattern uses this shape:

```markdown
### <rule-name>
- **Pattern:** <regex or concrete example>
- **Severity:** CRITICAL | HIGH (default CRITICAL — this file is for hard rules)
- **Why:** <one-line: incident, decision, compliance, contract>
- **What to do instead:** <concrete alternative>
- **Detection hint** (optional): <grep pattern, file glob, or context that helps the reviewer find violations>
```

Keep each rule under 6 lines. If it needs more, it probably belongs in `.claude/docs/adr/` as an ADR — link from here, don't duplicate.

## Examples (replace with your team's actual rules)

### direct-process-env-for-secrets-config
- **Pattern:** `process\.env\.[A-Z_]+` for config that should be secrets-backed
- **Severity:** CRITICAL
- **Why:** Production reads from a secrets manager, not direct env vars. Direct access bypasses the abstraction and breaks deployment.
- **What to do instead:** Use the runtime env helpers (`getRuntimeEnv()` / `requireEnv()` or whatever the repo's pattern is).
- **Detection hint:** Grep `process\.env\.` outside of the runtime env helper file itself.

### unsafe-role-cast
- **Pattern:** `as <RoleType>` casts at the auth boundary (parsing untrusted input)
- **Severity:** CRITICAL
- **Why:** Untrusted role input must go through a validating parser. Casts skip validation and admit invalid roles silently.
- **What to do instead:** Use the validating parser (`parseUserRole()` or the repo's equivalent).
- **Detection hint:** Grep for ` as ` in files matching auth/middleware paths.

### migration-mutation
- **Pattern:** Edit to existing file in `db/migrations/` or `migrations/`
- **Severity:** CRITICAL
- **Why:** Migrations are an append-only contract. Mutating one breaks reproducibility for envs already on that migration.
- **What to do instead:** Add a new migration file; never edit a previous one.
- **Detection hint:** Check `git diff` for changes to migration files older than HEAD.

## Rules for this file

- Keep rules **truly** non-negotiable. If you'd accept a fix on a case-by-case basis, it's not a banned pattern — it's a regular finding.
- Each rule has a **detected incident or explicit policy** behind it. Don't add rules just because you find them aesthetic.
- Detection hints help the reviewer agent grep efficiently — without them, the reviewer falls back to "read everything and look", which is slower and noisier.
- Update when the rule no longer applies (with the rationale of why it was lifted).
