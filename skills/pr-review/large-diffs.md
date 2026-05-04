# Handling large diffs

Load this doc from `SKILL.md` step 1 when the diff is large enough to risk context overflow or shallow analysis.

Rough triggers:
- >500 changed lines, OR
- >20 changed files, OR
- diff raw size clearly approaches context budget

---

## Strategy

Don't try to review everything at the same depth. Prioritize, sample, and be explicit about what was skimmed.

### 1. Categorize files first

Group changed files into three buckets:

- **Core logic** — business logic, new features, non-trivial changes. Review at full depth.
- **Boilerplate / generated** — lockfiles, snapshots, generated clients, migration auto-output, `package.json` version bumps, formatting-only diffs. Skim; only flag if something is obviously off (unexpected dep added, wrong version pinned, etc.).
- **Ambiguous** — tests, config, infra, docs. Default to skim; promote to full depth if they touch critical paths.

Print the bucketing to the user before deep analysis:

```
Categorized 47 files:
  Core logic (18):  <list>
  Boilerplate (23): <summary, e.g. "22 lockfile, 1 snapshot">
  Ambiguous (6):    <list>

Review all core logic at depth, skim the rest. Want to promote any Ambiguous/Boilerplate to deep review?
```

Wait for a short confirmation or overrides, then proceed.

### 2. Deep analysis on Core logic

Apply the full category list from `SKILL.md` step 3 to each core file. No shortcuts here — this is what the user actually cares about.

### 3. Skim pass on the rest

For skimmed files:
- Scan for red flags: new dependencies, version downgrades, secrets, unexpected files (`*.env`, credentials, large binaries), dropped tests.
- Don't produce per-line findings unless something is genuinely wrong.
- One aggregate note is fine: *"Lockfile updates consistent with the 3 new dependencies added in core. No suspicious version changes."*

### 4. Declare the coverage in the artifact

Add a `## Coverage` section to the artifact, right after `## Summary`:

```markdown
## Coverage
- Deeply reviewed: <list of core files>
- Skimmed: <list or aggregate description>
- Not reviewed: <any files excluded, with reason>
```

This is non-negotiable. A review that doesn't say what it skipped is dishonest.

---

## When even core logic is too big

If core logic alone exceeds budget:

1. Ask the user to prioritize:
   > *"Core logic touches 34 files (~4000 lines). I can do deep review on ~10 at a time. Which should I prioritize? Options: (a) you list files, (b) I pick highest-risk by heuristics, (c) split into multiple artifacts."*

2. If (b) — pick by heuristics:
   - Files touching auth, payments, data access, migrations first.
   - Files with the most line changes next.
   - Skip generated/boilerplate.

3. If (c) — write `<owner>-<repo>-<number>-<date>-part1.md`, `-part2.md`, etc. Each part declares its coverage clearly.

---

## Red-flag heuristics for fast scanning

When skimming, auto-flag these regardless of bucket:

- Newly committed `.env*`, `*.pem`, `*credentials*`, `id_rsa*`, `*secret*` files → **Blocking** (Security).
- `git diff` shows base64 blobs or long hex strings in code → investigate; may be a committed secret.
- New dependency from an unfamiliar publisher → **Major** (Security), ask user to confirm.
- Deleted tests without replacement → **Major** (Tests).
- Migration + no rollback script (if repo has rollback convention) → **Major** (Architecture).
- `// TODO`, `FIXME`, or `XXX` introduced in this PR → **Minor** (Code quality); note but don't block.

These are fast wins that don't require deep understanding.
