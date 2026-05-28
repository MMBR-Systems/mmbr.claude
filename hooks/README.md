# Hooks

Claude Code hooks live here as executable scripts. Their **configuration** (which event triggers what, with which matcher) is in `.claude/settings.json` under the `hooks` key. Scripts here are referenced from there.

## How hooks work

Claude Code fires a hook when a registered event occurs. Each hook is a command that:

- Reads JSON from **stdin** with the event payload (shape varies per event).
- Writes optional output to **stdout** (informational) or **stderr** (visible to the agent).
- Exits with a status code:
  - `0` — allow / continue normally.
  - `2` — block the operation; the stderr message is sent back to Claude.
  - other non-zero — error (logged but doesn't block).

Hooks must be **fast and non-interactive**. They cannot prompt the user; the equivalent of a "warn-and-confirm" is `exit 2` with a clear stderr message — Claude then relays it and the user decides whether to retry.

## Available environment variables

- `$CLAUDE_PROJECT_DIR` — absolute path to the project root.
- Standard shell environment from the user's session.

## Stdin payload examples

**`PreToolUse` / `PostToolUse`:**
```json
{
  "tool_name": "Bash",
  "tool_input": { "command": "ls -la" }
}
```

For other events (`Stop`, `UserPromptSubmit`, etc.), payload schema varies. Check `https://docs.claude.com/en/docs/claude-code/hooks` for current shapes.

## Shipped hooks

### `bash-gatekeeper.sh` — `PreToolUse` on `Bash`

Three-tier gatekeeper plus wrapper detection:

| Tier | Action | Examples |
|------|--------|----------|
| 🔴 HIGH | Block (`exit 2`) | `rm -rf /`, `rm -rf ~`, `--no-preserve-root`, `DROP DATABASE`, `mkfs`, `chmod 777 /`, `dd of=/dev/sd*` |
| 🔴 HIGH-WRAPPER | Block | Denied patterns wrapped in `bash -c "..."`, `sh -c "..."`, `eval "..."` (catches what `deny` can't see) |
| 🟡 MEDIUM | Block with message | `rm -rf <anything>`, `TRUNCATE`, `docker system prune -a`, `docker volume rm`, `kubectl delete ns` |
| 🟢 LOW | Log to `.docs/audit.log`, allow | `rm`, `git reset`, `git push`, `sudo`, `chmod NNN` |

Tier MEDIUM blocks the first attempt; the user can confirm and Claude reissues. Tier LOW just leaves a paper trail.

**No overlap with `deny`.** Patterns already in `settings.json` `deny` (e.g. `git clean -fd`) are not re-checked here for direct calls — `deny` runs first and faster. The hook's wrapper detection covers the case where the same patterns are smuggled inside `bash -c` / `eval`, which `deny` cannot see.

**Extension points (commented out in the script).** Three common additions teams add later, gated behind comments at the bottom of `bash-gatekeeper.sh`:
1. **Branch-aware push protection** — escalate `git push` to `main`/`master`/`release/*` to HIGH.
2. **Production env detection** — escalate any destructive op when `$AWS_PROFILE` / `$KUBECONFIG` / `$NODE_ENV` suggests prod.
3. **Secret-leak in command line** — block hardcoded AWS/GitHub/OpenAI/Slack token patterns.

Uncomment per team/stack policy.

### `handoff-reminder.sh` — `Stop`

If the working tree has ≥5 changed/untracked files when Claude finishes a turn, suggests running `/handoff` before `/clear`. Throttled to once per 4 hours per workspace (state in `.claude/.handoff-reminded`, gitignored).

## Dependencies

- **`jq`** — used to parse stdin JSON in `bash-gatekeeper.sh`. Most dev environments have it. If missing, the hook prints a warning and exits 0 (fail open).
- **`git`** — required for `handoff-reminder.sh`. No-op if the workspace isn't a git repo.
- POSIX **`find -mmin`** — used for throttling.

## Adding a new hook

1. Drop the executable script in this folder.
2. `chmod +x` it.
3. Register the trigger in `.claude/settings.json`:

   ```json
   "hooks": {
     "<EventName>": [
       {
         "matcher": "<ToolName regex, optional>",
         "hooks": [
           {
             "type": "command",
             "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/<your-script>.sh"
           }
         ]
       }
     ]
   }
   ```

4. Restart Claude Code so the config reloads.

## Override in nested repos

`<repo>/.claude/hooks/<same-name>.sh` overrides the workspace one inside that repo, *if* `<repo>/.claude/settings.json` registers the path. Useful for repo-specific stricter rules (e.g., a terraform repo blocking `terraform destroy` against `prod` state files).

## Defense layers

The gatekeeper hook is **one** layer in a defense-in-depth strategy:

1. **`settings.json` `deny`** — first line. Blocks at permission-check time, before the hook fires. Fast, dumb, non-bypassable.
2. **`hooks/bash-gatekeeper.sh`** — second line. Smart regex/contextual checks the deny list can't express.
3. **`.docs/audit.log`** — observation layer. Records what got through for after-the-fact review.
