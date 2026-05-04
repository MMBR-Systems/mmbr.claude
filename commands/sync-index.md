---
description: Scan sibling repos and regenerate the Repo index table in CLAUDE.md
---

Refresh the "Repo index" table in the workspace `CLAUDE.md` by scanning sibling directories. Only replaces the region between the sentinels — manual edits outside the sentinels are preserved.

## Sentinels

In `CLAUDE.md`, the Repo index table lives between:

```markdown
<!-- repo-index:start -->
...table...
<!-- repo-index:end -->
```

If the sentinels are missing, abort. Offer to add them and show the diff first; do not insert them silently.

## Steps

1. **Resolve workspace root** — the parent of `.claude/`. That's where sibling repos live.

2. **List candidate directories** — direct children of workspace root. Exclude: `.claude`, `.docs`, `.git`, any dotfile/dotfolder, non-directories, and any path matching `*/fork/*`.

   > **Note:** `*/fork/*` is excluded because it holds personal Fork & Pull workflow clones (each developer's own GitHub fork of an upstream repo). They are user-specific and don't belong in a shared repo index. See `CLAUDE.local.md` for personal fork setup.

3. **For each candidate, extract:**
   - **Repo name** — the folder name.
   - **Purpose** — first non-empty line after the first `# Heading` in one of these (first found wins): `<repo>/.claude/CLAUDE.md`, `<repo>/README.md`, `<repo>/CLAUDE.md`. Truncate to ~80 chars with `…` if longer.
   - **Stack** — heuristic detection by file presence:
     - `package.json` → Node (check `engines.node` or framework in deps if obvious)
     - `pyproject.toml` / `requirements.txt` / `Pipfile` → Python
     - `go.mod` → Go
     - `Cargo.toml` → Rust
     - `Gemfile` → Ruby
     - `pom.xml` / `build.gradle*` → JVM
     - `composer.json` → PHP
     - `deno.json` / `deno.jsonc` → Deno
     - `mix.exs` → Elixir
     - Multiple detected → list the most prominent; nothing detected → `—`.
   - **Nested agent config** — if `<repo>/.claude/CLAUDE.md` exists, link it as `[<repo>/.claude/CLAUDE.md](../<repo>/.claude/CLAUDE.md)`. Otherwise `—`.

4. **Build the new table:**

   ```markdown
   | Repo | Purpose | Stack | Nested agent config |
   |------|---------|-------|---------------------|
   | `repo-a` | <purpose line> | Node | [`repo-a/.claude/CLAUDE.md`](../repo-a/.claude/CLAUDE.md) |
   | `repo-b` | — | Go | — |
   ```

   Sort rows alphabetically by repo name. Empty cells use `—` (em dash).

5. **Show the diff** to the user — compare the old table (between sentinels) to the new one. Report added / removed / changed rows. Prompt:
   > *"Apply changes to CLAUDE.md? (y/N)"*

6. **On `y`:** replace only the content between `<!-- repo-index:start -->` and `<!-- repo-index:end -->`. Keep the sentinels themselves intact. Do not touch anything else in the file.

7. **On `N`:** print the proposed table so the user can copy it manually.

## Edge cases

- **No sibling repos** → report "No repos found under `<workspace-root>`. Table left as a placeholder."
- **Sibling has no CLAUDE.md and no README.md** → still include with `—` for Purpose.
- **Sentinels missing** → abort with guidance; never guess placement.
- **User has hand-edited the table** → still overwrite (the table is auto-managed). Their changes belong in the nested `<repo>/.claude/CLAUDE.md` heading where they propagate on next sync.

## Rules

- Only modifies `CLAUDE.md`. Never touches nested repos, never writes to `.docs/`.
- Never deletes content outside the sentinels.
- Never runs the replacement without the user confirming the diff.
- Alphabetical order is canonical — don't preserve custom ordering.
