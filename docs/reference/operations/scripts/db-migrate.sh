#!/bin/sh
# Run all SQL files under /app/db/migrations on the env's database, in order.
# Usage: db-migrate.sh <env>
#   env: dev | qa | prod
#
# Executes inside the running web-platform task via ECS Exec, so DB credentials
# are read from the task's SECRETS env var (Secrets Manager). Nothing is read
# or written locally.
#
# Migrations are NOT wrapped in a transaction here — each file runs as-is.
# For staged migrations with explicit BEGIN/COMMIT or dry-run/rollback, write
# a one-off command rather than reusing this script.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/_env.sh"

resolve_env "$1" || exit $?
resolve_task_id || exit $?

echo "==> $1 — running migrations on $WEB_SERVICE (task $TASK_ID)"
echo

# Single-quoted heredoc keeps the JS literal; aws ecs execute-command accepts
# the command as a single argument, so we collapse the JS to one line via tr.
JS=$(cat <<'EOF'
const{Pool}=require('pg');
const fs=require('fs');
const s=JSON.parse(process.env.SECRETS||'{}');
const pool=new Pool({host:s.DB_HOST,port:parseInt(s.DB_PORT),database:s.DB_NAME,user:s.DB_USER,password:s.DB_PASSWORD,ssl:{rejectUnauthorized:false}});
(async()=>{
  const files=fs.readdirSync('/app/db/migrations').filter(f=>f.endsWith('.sql')).sort();
  for(const f of files){console.log('Running '+f+'...');await pool.query(fs.readFileSync('/app/db/migrations/'+f,'utf8'));console.log('OK');}
  console.log('Done!');
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
