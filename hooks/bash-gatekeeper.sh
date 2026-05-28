#!/usr/bin/env bash
# bash-gatekeeper.sh — PreToolUse gatekeeper for Bash
#
# Tiers:
#   HIGH    → block (catastrophic, never legit) — always on
#   MEDIUM  → block destructive-but-sometimes-legit patterns — opt-in (see extension #4)
#   LOW     → log to .docs/audit.log, allow
#
# Routine destructive patterns (rm -rf foo/, docker volume rm, etc.) are NOT blocked here
# by default. They are handled upstream by the permission system (`Bash(rm *)` ask rule and
# friends). Enable extension #4 if you want a hard block from this layer too.
#
# Reads JSON from stdin via jq. Fails open (exit 0) if jq is missing.

set -u

if ! command -v jq >/dev/null 2>&1; then
  echo "bash-gatekeeper.sh: jq not found; install jq for hook protection. Allowing command." >&2
  exit 0
fi

INPUT=$(cat)
COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
[ -z "$COMMAND" ] && exit 0

LOG="${CLAUDE_PROJECT_DIR:-.}/.docs/audit.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true

log_entry() {
  local tier="$1"
  local cmd="$2"
  printf '%s | %s | %s\n' "$(date -u +%FT%TZ)" "$tier" "$cmd" >> "$LOG" 2>/dev/null || true
}

# 🔴 HIGH — catastrophic, never legitimate
if [[ "$COMMAND" =~ rm[[:space:]]+-rf?[[:space:]]+/([[:space:]]|$) ]] \
|| [[ "$COMMAND" =~ rm[[:space:]]+-rf?[[:space:]]+~([[:space:]]|$) ]] \
|| [[ "$COMMAND" =~ --no-preserve-root ]] \
|| [[ "$COMMAND" =~ DROP[[:space:]]+DATABASE ]] \
|| [[ "$COMMAND" =~ (^|[[:space:]])mkfs ]] \
|| [[ "$COMMAND" =~ chmod[[:space:]]+(-R[[:space:]]+)?777[[:space:]]+/ ]] \
|| [[ "$COMMAND" =~ dd[[:space:]]+.*of=/dev/(sd|nvme|hd) ]]; then
  log_entry "HIGH-BLOCKED" "$COMMAND"
  echo "BLOCKED (catastrophic pattern): $COMMAND" >&2
  echo "This pattern can cause irreversible data loss. Refusing to execute." >&2
  exit 2
fi

# 🔴 HIGH — denied patterns inside shell wrappers (bypass attempt)
# Catches cases the settings.json `deny` cannot see, e.g.:
#   bash -c "git push --force ..."
#   eval "git reset --hard ..."
if [[ "$COMMAND" =~ (bash|sh|zsh)[[:space:]]+-c ]] || [[ "$COMMAND" =~ (^|[[:space:]])eval[[:space:]] ]]; then
  # --force matched with trailing space/EOL so --force-with-lease (safer) is allowed
  if [[ "$COMMAND" =~ git[[:space:]]+push[[:space:]]+(-f|--force)([[:space:]]|$) ]] \
  || [[ "$COMMAND" =~ git[[:space:]]+reset[[:space:]]+--hard ]] \
  || [[ "$COMMAND" =~ git[[:space:]]+clean[[:space:]]+-fd ]]; then
    log_entry "HIGH-WRAPPER-BLOCKED" "$COMMAND"
    echo "BLOCKED: a denied pattern was detected inside a shell wrapper (bash -c / sh -c / eval)." >&2
    echo "Refusing to bypass deny rules. If intentional, run the command directly without the wrapper." >&2
    exit 2
  fi
fi

# 🟢 LOW — log noteworthy patterns, allow
if [[ "$COMMAND" =~ (^|[[:space:]])rm([[:space:]]|$) ]] \
|| [[ "$COMMAND" =~ git[[:space:]]+reset ]] \
|| [[ "$COMMAND" =~ git[[:space:]]+push ]] \
|| [[ "$COMMAND" =~ (^|[[:space:]])sudo([[:space:]]|$) ]] \
|| [[ "$COMMAND" =~ chmod[[:space:]]+(-R[[:space:]]+)?[0-7]{3,4} ]]; then
  log_entry "LOW" "$COMMAND"
fi

# ─── Extension points ──────────────────────────────────────────────────────
# Uncomment per team/stack policy. None of these are agnostic enough to ship
# enabled by default, but they're common patterns teams add over time.

# # 1) Branch-aware push protection — escalate pushes to protected branches
# if [[ "$COMMAND" =~ git[[:space:]]+push.*[[:space:]](origin[[:space:]]+)?(main|master|release/.*|production)([[:space:]]|$) ]]; then
#   log_entry "HIGH-PROTECTED-BRANCH" "$COMMAND"
#   echo "BLOCKED: push to a protected branch. Confirm with the user before retrying." >&2
#   exit 2
# fi

# # 2) Production env detection — escalate destructive ops when env vars suggest prod
# if [[ "${AWS_PROFILE:-}" =~ prod ]] || [[ "${KUBECONFIG:-}" =~ prod ]] || [[ "${NODE_ENV:-}" == "production" ]]; then
#   if [[ "$COMMAND" =~ (rm|delete|destroy|drop|truncate|prune) ]]; then
#     log_entry "HIGH-PROD-ENV" "$COMMAND"
#     echo "BLOCKED: destructive command in a prod-flagged environment." >&2
#     exit 2
#   fi
# fi

# # 3) Secret-leak in command line — block hardcoded secret patterns
# if [[ "$COMMAND" =~ (AKIA[0-9A-Z]{16}|ghp_[a-zA-Z0-9]{36}|sk-[a-zA-Z0-9]{48}|xoxb-[0-9]+-[0-9]+-[a-zA-Z0-9]+) ]]; then
#   log_entry "HIGH-SECRET-LEAK" "<redacted>"
#   echo "BLOCKED: command appears to contain a hardcoded secret. Use env vars or a secret manager." >&2
#   exit 2
# fi

# # 4) MEDIUM tier — destructive-but-sometimes-legit patterns
# # Currently disabled in this workspace (we rely on permission prompts instead).
# # Uncomment to add a hard block from this hook on top of the permission system.
# if [[ "$COMMAND" =~ rm[[:space:]]+-rf? ]] \
# || [[ "$COMMAND" =~ (^|[[:space:]])TRUNCATE([[:space:]]|$) ]] \
# || [[ "$COMMAND" =~ docker[[:space:]]+system[[:space:]]+prune[[:space:]]+-a ]] \
# || [[ "$COMMAND" =~ docker[[:space:]]+volume[[:space:]]+rm ]] \
# || [[ "$COMMAND" =~ kubectl[[:space:]]+delete[[:space:]]+(ns|namespace) ]]; then
#   log_entry "MEDIUM-BLOCKED" "$COMMAND"
#   echo "Destructive pattern detected: $COMMAND" >&2
#   echo "Confirm with the user before retrying. If intentional, the user can re-issue the request." >&2
#   exit 2
# fi

exit 0
