#!/usr/bin/env bash
# Bootstrap the AUTH0_* and QAP_* keys in mmbr-{env}-web-platform.
#
# Usage:
#   populate-auth0-qap-keys.sh <env>      # env: dev | qa | prod
#
# Sources of truth:
#   - AUTH0_CLIENT_ID / AUTH0_CLIENT_SECRET → copied from mmbr-qa-web-platform.
#     The Auth0 tenant is shared across dev/qa/prod (decision: reuse dev tenant
#     for now; see .claude/docs/adr/ if/when prod gets its own tenant).
#   - QAP_JWT_SECRET → mirror of NEXTAUTH_SECRET in mmbr-{env}-backend-ui.
#     This is the shared HMAC across web-platform / qbrick / backend-ui.
#   - AUTH0_SECRET → freshly generated per env (cookie encryption, must be
#     unique per env, never copied across envs).
#   - The remaining keys (BASE_URL, ISSUER, DOMAIN, AUDIENCE, JWT_ISSUER,
#     JWT_AUDIENCE, TIMEOUT_MS) are constants per env and hardcoded here.
#
# This script does NOT set QAP_AGENT_ID / QAP_API_KEY / QAP_API_SECRET — those
# come from creating an agent in the env's backend-ui (e.g. ui.mem-brain.com)
# and must be added in a separate run.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/_env.sh"

ENV_NAME="${1:-}"
if [[ -z "$ENV_NAME" ]]; then
  echo "Usage: $0 <env>   (env: dev|qa|prod)" >&2
  exit 2
fi

# Validate env + warm SSO check
resolve_env "$ENV_NAME" >/dev/null

# Pick the per-env URL. The tenant URLs stay the same because we share the
# dev tenant across envs.
case "$ENV_NAME" in
  dev)  BASE_URL="https://dev.mem-brain.com" ;;
  qa)   BASE_URL="https://qa.mem-brain.com" ;;
  prod) BASE_URL="https://mem-brain.com" ;;
esac

TENANT_DOMAIN="dev-oasbmd2tfc8nw8de.us.auth0.com"
TENANT_ISSUER="https://${TENANT_DOMAIN}"
TENANT_AUDIENCE="${TENANT_ISSUER}/api/v2/"

echo "==> Resolving inputs..." >&2

CLIENT_ID=$("$SCRIPT_DIR/get-secret.sh" mmbr-qa-web-platform AUTH0_CLIENT_ID)
[[ -n "$CLIENT_ID" ]] || { echo "Missing AUTH0_CLIENT_ID in mmbr-qa-web-platform." >&2; exit 1; }

CLIENT_SECRET=$("$SCRIPT_DIR/get-secret.sh" mmbr-qa-web-platform AUTH0_CLIENT_SECRET)
[[ -n "$CLIENT_SECRET" ]] || { echo "Missing AUTH0_CLIENT_SECRET in mmbr-qa-web-platform." >&2; exit 1; }

JWT_SECRET=$("$SCRIPT_DIR/get-secret.sh" "mmbr-${ENV_NAME}-backend-ui" NEXTAUTH_SECRET)
[[ -n "$JWT_SECRET" ]] || { echo "Missing NEXTAUTH_SECRET in mmbr-${ENV_NAME}-backend-ui (qbrick HMAC)." >&2; exit 1; }

AUTH0_SECRET=$(openssl rand -hex 32)
[[ ${#AUTH0_SECRET} -eq 64 ]] || { echo "Failed to generate AUTH0_SECRET (openssl)." >&2; exit 1; }

echo "    ✓ AUTH0_CLIENT_ID/SECRET  ← mmbr-qa-web-platform" >&2
echo "    ✓ QAP_JWT_SECRET          ← mmbr-${ENV_NAME}-backend-ui (NEXTAUTH_SECRET)" >&2
echo "    ✓ AUTH0_SECRET            ← generated locally (64 hex chars)" >&2
echo >&2

# Build the JSON via python so secret values are passed via env vars and
# never go through shell quoting / command-line listings.
JSON=$(
  CLIENT_ID="$CLIENT_ID" \
  CLIENT_SECRET="$CLIENT_SECRET" \
  JWT_SECRET="$JWT_SECRET" \
  AUTH0_SECRET="$AUTH0_SECRET" \
  BASE_URL="$BASE_URL" \
  TENANT_DOMAIN="$TENANT_DOMAIN" \
  TENANT_ISSUER="$TENANT_ISSUER" \
  TENANT_AUDIENCE="$TENANT_AUDIENCE" \
  python3 - <<'PY'
import json, os
out = {
    "AUTH0_BASE_URL":         os.environ["BASE_URL"],
    "AUTH0_ISSUER_BASE_URL":  os.environ["TENANT_ISSUER"],
    "AUTH0_DOMAIN":           os.environ["TENANT_DOMAIN"],
    "AUTH0_CLIENT_ID":        os.environ["CLIENT_ID"],
    "AUTH0_CLIENT_SECRET":    os.environ["CLIENT_SECRET"],
    "AUTH0_AUDIENCE":         os.environ["TENANT_AUDIENCE"],
    "AUTH0_SECRET":           os.environ["AUTH0_SECRET"],
    "QAP_JWT_SECRET":         os.environ["JWT_SECRET"],
    "QAP_JWT_ISSUER":         "qubika-agentic-platform",
    "QAP_JWT_AUDIENCE":       "qubika-api",
    "QAP_TIMEOUT_MS":         "30000",
}
print(json.dumps(out))
PY
)

echo "==> Submitting merge to mmbr-${ENV_NAME}-web-platform..." >&2
echo "    (set-secret-keys.sh will show the diff and ask for confirmation)" >&2
echo >&2

echo "$JSON" | "$SCRIPT_DIR/set-secret-keys.sh" "mmbr-${ENV_NAME}-web-platform"
