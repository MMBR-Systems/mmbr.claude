#!/bin/sh
# Merge a set of keys into an existing Secrets Manager secret.
# Reads additions as JSON from stdin, shows a key-level diff (no values printed),
# asks for confirmation, then writes a new version.
#
# Usage:
#   echo '{"AUTH0_BASE_URL":"https://mem-brain.com"}' | set-secret-keys.sh mmbr-prod-web-platform
#   set-secret-keys.sh mmbr-prod-web-platform < additions.json
#
# Behavior:
#   - Existing keys NOT in the input are preserved untouched.
#   - Existing keys present in the input are OVERWRITTEN (flagged in the diff).
#   - The diff prints key names only — values never go to stdout/stderr.
#
# Env (dev/qa/prod) is inferred from the secret name (mmbr-{env}-...).

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/_env.sh"

SECRET_NAME="$1"
if [ -z "$SECRET_NAME" ]; then
  echo "Usage: $0 <secret-name>   (reads additions JSON from stdin)" >&2
  exit 2
fi

ENV_FROM_NAME=$(echo "$SECRET_NAME" | awk -F'-' '{print $2}')
case "$ENV_FROM_NAME" in
  dev|qa|prod) ;;
  *)
    echo "Cannot infer env from secret name '$SECRET_NAME' (expected mmbr-{dev|qa|prod}-...)." >&2
    exit 2
    ;;
esac

resolve_env "$ENV_FROM_NAME" || exit $?

TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

# Capture additions from stdin
cat > "$TMP_DIR/additions.json"
if [ ! -s "$TMP_DIR/additions.json" ]; then
  echo "No input received on stdin." >&2
  exit 2
fi
python3 -c 'import json,sys;json.loads(open(sys.argv[1]).read())' "$TMP_DIR/additions.json" || {
  echo "Input is not valid JSON." >&2
  exit 2
}

# Read current secret
aws secretsmanager get-secret-value \
  --secret-id "$SECRET_NAME" \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --query SecretString --output text > "$TMP_DIR/current.json"

# Show diff (key names only) and produce merged file
python3 - "$TMP_DIR/current.json" "$TMP_DIR/additions.json" "$TMP_DIR/merged.json" <<'PY'
import json, sys
cur_path, add_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]
cur = json.loads(open(cur_path).read())
add = json.loads(open(add_path).read())
new_keys     = sorted(k for k in add if k not in cur)
overwritten  = sorted(k for k in add if k in cur and cur[k] != add[k])
unchanged    = sorted(k for k in add if k in cur and cur[k] == add[k])
print("Diff (keys only — values never printed):", file=sys.stderr)
print("  new keys      : " + (", ".join(new_keys)    or "(none)"), file=sys.stderr)
print("  overwriting   : " + (", ".join(overwritten) or "(none)"), file=sys.stderr)
print("  unchanged     : " + (", ".join(unchanged)   or "(none)"), file=sys.stderr)
cur.update(add)
open(out_path, "w").write(json.dumps(cur))
PY

echo >&2
if [ -n "$YES" ]; then
  echo "YES=1 set — skipping interactive confirmation." >&2
elif [ -e /dev/tty ]; then
  printf 'Apply these changes to %s? [y/N] ' "$SECRET_NAME" >&2
  read -r REPLY < /dev/tty
  case "$REPLY" in
    y|Y|yes|YES) ;;
    *) echo "Aborted." >&2; exit 1 ;;
  esac
else
  echo "No /dev/tty available and YES not set. Aborting." >&2
  exit 1
fi

VERSION_ID=$(aws secretsmanager put-secret-value \
  --secret-id "$SECRET_NAME" \
  --secret-string "file://$TMP_DIR/merged.json" \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION" \
  --query 'VersionId' --output text)

echo "Updated $SECRET_NAME (new version: $VERSION_ID)." >&2
