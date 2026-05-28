#!/bin/sh
# Port-forward Aurora (via RDS Proxy) to localhost through the env's bastion.
# Usage: bastion-tunnel.sh <env> [local_port]
#   env:        dev | qa | prod
#   local_port: defaults to 5433 (local Postgres usually owns 5432)
#
# Once running, connect DBeaver/psql to localhost:<local_port> using DB_USER /
# DB_PASSWORD from the env's web-platform secret in Secrets Manager.
# Keep this terminal open while you use the tunnel — closing it ends the session.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/_env.sh"

resolve_env "$1" || exit $?
LOCAL_PORT="${2:-5433}"

echo "==> $1 — port-forward localhost:$LOCAL_PORT -> $RDS_HOST:$RDS_PORT"
echo "    bastion: $BASTION_ID  (profile: $AWS_PROFILE)"
echo

aws ssm start-session \
  --target "$BASTION_ID" \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "{\"host\":[\"$RDS_HOST\"],\"portNumber\":[\"$RDS_PORT\"],\"localPortNumber\":[\"$LOCAL_PORT\"]}" \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION"
