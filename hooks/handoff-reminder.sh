#!/usr/bin/env bash
# handoff-reminder.sh — Stop hook (MMBR variant)
#
# When Claude finishes a turn, sums uncommitted changes across all git repos
# at depth ≤2 from the workspace root (web-platform, ai-platform, .claude,
# .docs, etc. — MMBR root itself is NOT a git repo). If the total is ≥5 files,
# suggests running /handoff before /clear. Throttled to once per 4 hours per
# workspace via .claude/.handoff-reminded (gitignored).

set -u

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
cd "$PROJECT_DIR" 2>/dev/null || exit 0

THRESHOLD=5
TOTAL=0

# Find .git dirs at depth 1 (root) and 2 (immediate children).
# -prune avoids descending into matched .git dirs themselves.
while IFS= read -r gitdir; do
  repo_dir=$(dirname "$gitdir")
  count=$(git -C "$repo_dir" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  TOTAL=$((TOTAL + ${count:-0}))
done < <(find . -maxdepth 2 -type d -name .git -prune 2>/dev/null)

[ "$TOTAL" -lt "$THRESHOLD" ] && exit 0

NUDGE_FILE="$PROJECT_DIR/.claude/.handoff-reminded"

# Throttle: skip if nudge file was touched within the last 240 minutes (4h)
if [ -f "$NUDGE_FILE" ] && [ -n "$(find "$NUDGE_FILE" -mmin -240 2>/dev/null)" ]; then
  exit 0
fi

mkdir -p "$(dirname "$NUDGE_FILE")" 2>/dev/null || true
touch "$NUDGE_FILE"

cat >&2 <<EOF
Heads up — $TOTAL changed/untracked file(s) across nested git repos. If you're
about to /clear or end the session, consider running /handoff first to capture
the session state for the next conversation. (Suppressed for the next 4 hours.)
EOF

exit 0
