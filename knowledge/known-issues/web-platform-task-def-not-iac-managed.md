---
created: 2026-05-07
updated: 2026-05-07
owner: workspace owner
---

# `web-platform` ECS task definition is not in IaC — CI propagates manual edits forever

## Symptom

A deploy to `<env>-web-platform` succeeds but the running container is missing env vars it used to have. Common downstream errors:

- Migration runner: `Missing DB config: host (set DATABASE_HOST or include in SECRETS env)`
- App startup: `getaddrinfo ENOTFOUND localhost` / `ECONNREFUSED 127.0.0.1:5432` (when DATABASE_HOST not injected, app falls through to Postgres default `localhost`).
- Pydantic validation in qbrick: `Input should be 'grpc' or 'http' [input_value='']` (RAG_AGENT_URL missing).

The Secrets Manager secret has the keys correctly populated. The task definition's `secrets` array is what's missing them — i.e. the task isn't reading them, even though they exist.

## Where

- **AWS:** `ecs-{env}` cluster, `web-platform-{env}` service, task definition family `{env}-web-platform`. Multiple revisions exist (`{env}-web-platform:60`, `:61`, `:62`, ...).
- **CI source:** `web-platform/.github/workflows/web-build-and-push.yaml` — see the "Register new task definition revision" step (currently around lines 119-178 for dev, repeated for qa/prod).
- **NOT in `infraestructure-iac`** — that repo only manages `qbrick` and `api_gateway` task defs. `web-platform` task def has no terraform resource anywhere.

## Cause

The CI workflow registers each new revision by **cloning the current AWS state** and only swapping the image tag:

```bash
aws ecs describe-task-definition --task-definition "${CURRENT_TASK_DEFINITION}" \
  --output json > task-definition.json
# ... swap image tag ...
aws ecs register-task-definition --cli-input-json file://task-definition-updated.json
```

Whatever the task definition looks like in AWS at the moment of deploy becomes the input for the next revision. There is no versioned template in any repo to compare against.

Concrete failure observed on 2026-05-07:

| Revision | When | Author | DATABASE_* present? |
|---|---|---|---|
| `:60` | 2026-05-06 15:53 | CI (`gha-web-platform-dev`) | yes |
| `:61` | 2026-05-07 09:58 | manual SSO edit (`Henrique.Peluzio`) | **no** (someone removed during incident triage) |
| `:62` | 2026-05-07 14:30 | CI (push to development) | **no** (cloned from `:61`) — migration step exited 1 |

The CI itself didn't introduce the bug — it propagated a manual edit from earlier the same day. `:62` would have continued spawning broken descendants on every subsequent deploy until someone restored a working revision by hand.

## Workaround

When you suspect a task definition has drifted (deploy succeeds but the app is missing env vars), restore from a known-good prior revision and let the next CI cycle pick up from there.

```bash
# 1) Compare the broken revision against the most recent working one
diff \
  <(aws ecs describe-task-definition --task-definition {env}-web-platform:<working> \
      --query 'taskDefinition.containerDefinitions[0].secrets[].name' --output text | tr '\t' '\n' | sort) \
  <(aws ecs describe-task-definition --task-definition {env}-web-platform:<broken> \
      --query 'taskDefinition.containerDefinitions[0].secrets[].name' --output text | tr '\t' '\n' | sort)

# 2) Clone the working revision, swap in the latest image tag, register a new revision
CURRENT_IMAGE=$(aws ecs describe-task-definition --task-definition {env}-web-platform:<broken> \
  --query 'taskDefinition.containerDefinitions[0].image' --output text)

aws ecs describe-task-definition --task-definition {env}-web-platform:<working> \
  --query 'taskDefinition' \
  | jq 'del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities, .registeredAt, .registeredBy)' \
  | jq --arg img "$CURRENT_IMAGE" '.containerDefinitions[0].image = $img' \
  > /tmp/td-restore.json

aws ecs register-task-definition --cli-input-json file:///tmp/td-restore.json

# 3) Point the service at the new (restored) revision
aws ecs update-service --cluster ecs-{env} --service web-platform-{env} \
  --task-definition {env}-web-platform:<new>

# 4) Re-run the failed CI workflow — subsequent CI runs will clone from the restored
# revision, so the fix propagates forward (until the next manual edit).
```

To find the most recent **working** revision, look at `registeredBy` — `arn:.../gha-web-platform-{env}` is the CI role; manual SSO edits show `arn:.../AWSReservedSSO_AdministratorAccess_*`. Look for a revision authored by CI **before** any manual SSO edits and verify its `secrets` array includes the expected keys.

## Fix (if planned)

Deferred — needs alignment with infra/devops. Two paths, increasing soundness:

1. **Versioned template in `web-platform` repo** (low effort, high return):
   - Commit `web-platform/infra/task-definition.tpl.json` with the canonical task definition shape.
   - Change the CI step from `describe-task-definition → swap image → register` to `read template → substitute image tag → register`.
   - Manual edits in the AWS console are still possible but get **overwritten on the next deploy** instead of propagating. The repo becomes the source of truth.

2. **Move into `infraestructure-iac`** (higher effort, full IaC):
   - Add `aws_secretsmanager_secret.web_platform`, `aws_ecs_task_definition.web_platform`, and `aws_ecs_service.web_platform` to the existing `globals/` modules — same shape as the existing `qbrick` and `api_gateway` blocks.
   - CI shifts to `terraform apply -var "web_platform_image=<sha>"` and stops touching task definitions directly.
   - Drift is detectable via `terraform plan`. PR review covers infra changes.

Tracking: open an issue in `infraestructure-iac` (or whichever repo the team agrees) before next sprint cleanup. Until then, the workaround above is the recovery path.

## Related

- `known-issues/web-platform-secrets-injected-as-json.md` — about the *secret* shape, not the task definition. Different layer.
- `architecture/ci-cd-deploy-flow.md` — overall deploy pipeline; flag this drift caveat there if not yet noted.
