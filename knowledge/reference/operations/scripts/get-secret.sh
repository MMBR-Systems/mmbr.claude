#!/bin/sh
# Retrieve a Secrets Manager secret (full JSON or single key).
# Usage:
#   get-secret.sh <secret-name> [key]
#
# Examples:
#   get-secret.sh mmbr-qa-web-platform              # pretty-print full JSON
#   get-secret.sh mmbr-qa-web-platform DB_HOST      # print one value
#   get-secret.sh mmbr-prod-backend-ui NEXTAUTH_SECRET
#
# Env (dev/qa/prod) is inferred from the secret name (mmbr-{env}-...) so the
# right AWS profile is selected automatically.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/_env.sh"

SECRET_NAME="$1"
KEY="$2"

if [ -z "$SECRET_NAME" ]; then
  echo "Usage: $0 <secret-name> [key]" >&2
  exit 2
fi

# Extract env from secret name pattern: mmbr-{env}-...
ENV_FROM_NAME=$(echo "$SECRET_NAME" | awk -F'-' '{print $2}')
case "$ENV_FROM_NAME" in
  dev|qa|prod) ;;
  *)
    echo "Cannot infer env from secret name '$SECRET_NAME' (expected mmbr-{dev|qa|prod}-...)." >&2
    exit 2
    ;;
esac

resolve_env "$ENV_FROM_NAME" || exit $?

JSON=$(aws secretsmanager get-secret-value \
  --secret-id "$SECRET_NAME" \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --query SecretString --output text)

if [ -z "$KEY" ]; then
  echo "$JSON" | python3 -m json.tool
else
  echo "$JSON" | K="$KEY" python3 -c "import json,sys,os;k=os.environ['K'];d=json.loads(sys.stdin.read());print(d.get(k,''))"
fi
