#!/bin/sh
# Open an interactive shell inside the running web-platform task for the env.
# Usage: ecs-exec.sh <env> [container]
#   env:       dev | qa | prod
#   container: defaults to "web-platform" (the only one in this task def today)
#
# Pre-req: the task must have ECS Exec enabled and your role must allow
# ecs:ExecuteCommand. SSO session must be active for the env's profile.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/_env.sh"

resolve_env "$1" || exit $?
CONTAINER="${2:-$WEB_CONTAINER}"

resolve_task_id || exit $?

echo "==> $1 — exec into $WEB_SERVICE / $CONTAINER on task $TASK_ID"
echo

aws ecs execute-command \
  --cluster "$ECS_CLUSTER" \
  --task "$TASK_ID" \
  --container "$CONTAINER" \
  --interactive \
  --command "/bin/sh" \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION"
