#!/bin/sh
# Run /app/db/seed.sql on the env's database via the running web-platform task.
# Usage: db-seed.sh <env>
#   env: dev | qa | prod
#
# seed.sql is expected to be idempotent (uses ON CONFLICT). Re-running it is
# safe and is the supported way to add/fix-up seed rows in a deployed env.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/_env.sh"

resolve_env "$1" || exit $?
resolve_task_id || exit $?

echo "==> $1 — running seed on $WEB_SERVICE (task $TASK_ID)"
echo

JS=$(cat <<'EOF'
const{Pool}=require('pg');
const fs=require('fs');
const s=JSON.parse(process.env.SECRETS||'{}');
const pool=new Pool({host:s.DB_HOST,port:parseInt(s.DB_PORT),database:s.DB_NAME,user:s.DB_USER,password:s.DB_PASSWORD,ssl:{rejectUnauthorized:false}});
(async()=>{
  const sql=fs.readFileSync('/app/db/seed.sql','utf8');
  console.log('Running seed...');
  await pool.query(sql);
  console.log('Seed done!');
  await pool.end();
})().catch(e=>{console.error(e);process.exit(1);});
EOF
)
JS_ONE_LINE=$(printf '%s' "$JS" | tr '\n' ' ')

aws ecs execute-command \
  --cluster "$ECS_CLUSTER" \
  --task "$TASK_ID" \
  --container "$WEB_CONTAINER" \
  --interactive \
  --command "node -e \"$JS_ONE_LINE\"" \
  --profile "$AWS_PROFILE" \
  --region "$AWS_REGION"
