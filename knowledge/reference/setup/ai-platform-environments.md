# AI-Platform Environments — Status & Rollout Playbook

Snapshot of dev/QA deploy state for `ai-platform` (QAP) as of 2026-04-22.
Pair with `.claude/knowledge/reference/setup/aws-sso-setup.md` for SSO/CLI setup.

---

## 1. High-level state

| Environment | Account | ai-platform (qbrick) | web-platform | Gap |
|-------------|---------|----------------------|--------------|-----|
| **Local** | — | ✅ RAG working (Databricks) | ✅ pointing at local QAP | none |
| **Dev** | 455842406405 | ⚠️ **Stale** — commit `13bc3cd` (2026-04-16), pre MMBR-171 + MMBR-183 | ✅ Current — commit `dcfe7d4` (2026-04-22, MMBR-183 merge) | web ahead of ai |
| **QA** | 542035162757 | ❌ **Never deployed** — rollout FAILED 2026-04-14, ECR empty | ✅ Running (old version, task-def v3) | ai-platform never ran in QA |
| **Prod** | 819743217049 | (not checked) | (not checked) | — |

**Key problem:** web-platform-dev is running the MMBR-183 client that expects `output_state["rag_agent::citations"]` from QAP. ai-platform-dev is still on the pre-Databricks, pre-structured-citations commit. Any chat request in dev falls back to the legacy text-parsing path (no citation URLs) and will likely hit the H2 security issue from the MMBR-171 review.

---

## 2. Dev environment (account 455842406405)

### ECS services — `ecs-dev` cluster

| Service | Status | Task def | Last deploy | Image SHA |
|---------|--------|----------|-------------|-----------|
| `qbrick-dev` | 1/1 RUNNING | `dev-qbrick:12` | 2026-04-16 12:24 | `13bc3cd75ccd217a1e5d2c81532ae6afc69cbff5` |
| `backend-ui-dev` | 1/1 RUNNING | `dev-backend-ui:7` | 2026-04-16 12:21 | `13bc3cd` (same) |
| `web-platform-dev` | 1/1 RUNNING | `dev-web-platform:30` | 2026-04-22 13:27 | `dcfe7d4884cddac06361ea38da8c139e800d0941` |

### SSM image-tag parameters

| Name | Value | Modified |
|------|-------|----------|
| `qbrick-image-tag-dev` | `13bc3cd...` | 2026-04-16 |
| `backend-ui-image-tag-dev` | `13bc3cd...` | 2026-04-16 |
| `web-platform-image-tag-dev` | `dcfe7d4...` | 2026-04-22 |

### Secrets (dev)

- `mmbr-dev-web-platform` — AUTH0_*, DB_*, DEV_BYPASS_AUTH, QBRICK_BASE_URL (internal)
- `mmbr-dev-qbrick` — ai-platform env (DATABASE_URI, DATABRICKS_*, RAG_*, NEXTAUTH_SECRET, OPENAI_API_KEY, …)
- `mmbr-dev-backend-ui` — qap-ui env
- `mmbr-dev-valkey-auth-token`
- `rds!cluster-ef7f688c-71de-45ad-bf80-032abc245070` — RDS-managed

### URLs (confirmed by infra team, 2026-04-22)

| Service | Local | Dev | QA | Prod |
|---------|-------|-----|-----|------|
| Web-platform | `http://localhost:3001` | `https://dev.mem-brain.com` | `https://qa.mem-brain.com` | `https://mem-brain.com` |
| QAP UI (backend-ui / agents-builder) | `http://localhost:3000` | `https://ui.dev.mem-brain.com` | `https://ui.qa.mem-brain.com` | `https://ui.mem-brain.com` |
| QAP API (qbrick) | `http://localhost:8000` | internal `http://qbrick:8000` (Service Connect) | internal `http://qbrick:8000` | internal `http://qbrick:8000` |

**ALB (dev):** `ecs-dev-alb` (`ecs-dev-alb-279847286.us-east-2.elb.amazonaws.com`)
**TLS cert:** `dev.mem-brain.com` (covers `*.dev.mem-brain.com`)
**Routing:** host-based. Only web-platform and backend-ui are exposed via ALB. Qbrick API is private; reachable only from inside the ECS network.

### Repo → service mapping

| Repo path | ECS service | Deploy workflow |
|-----------|-------------|-----------------|
| `MMBR-Systems/web-platform` | `web-platform-{env}` | `.github/workflows/web-build-and-push.yaml` |
| `MMBR-Systems/ai-platform/api/` | `qbrick-{env}` | `.github/workflows/api-build-and-push.yaml` |
| `MMBR-Systems/ai-platform/qap-ui/` | `backend-ui-{env}` | `.github/workflows/ui-build-and-push.yaml` |

### Branch → environment mapping

| Branch pattern | Environment | ai-platform | web-platform |
|----------------|-------------|-------------|--------------|
| `main` | Dev | ✅ triggers deploy-dev | ❌ unused |
| `development` | Dev | ❌ unused | ✅ triggers deploy-dev |
| `release-qa/**` | QA | ✅ | ✅ |
| `release-prod/**` | Prod | ✅ | ✅ |

**Inconsistency:** web-platform uses `development` for dev deploys; ai-platform uses `main`. The infra team's official standard is `main → Dev`. Decision pending whether to align web-platform to the standard or document the divergence.

---

## 3. QA environment (account 542035162757)

### ECS services — `ecs-qa` cluster

| Service | Status | Last deploy | Rollout |
|---------|--------|-------------|---------|
| `qbrick-qa` | **0/1** (DESIRED=1) | 2026-04-14 14:23 | **FAILED** |
| `backend-ui-qa` | (not checked) | — | — |
| `web-platform-qa` | 1/1 RUNNING | 2026-04-21 16:29 | COMPLETED |

### Root cause (qbrick-qa failure)

Three cascading issues:

1. **ECR repo `mmbr-qbrick` in QA account is empty** — zero images. Task-def points at `mmbr-qbrick:qa` (literal tag, not a SHA).
2. **SSM parameter `qbrick-image-tag-qa` has placeholder value `"qa"`** — never updated by CI because no `release-qa/*` branch exists yet.
3. **Last task start failed** with `ResourceNotFoundException: Secrets Manager can't find specified secret value for staging label AWSCURRENT` — secret was provisioned empty initially and populated later; ECS did not retry.

### Secrets (QA) — keys present

**`mmbr-qa-qbrick` (78 keys present, same structure as dev)**

**`mmbr-qa-web-platform` — MISSING critical keys for MMBR-171/183:**
- `QAP_JWT_SECRET` ← required to sign JWT for QAP
- `QAP_API_KEY` ← required (fail-fast in MMBR-171)
- `QAP_API_SECRET` ← required (fail-fast in MMBR-171)
- `QAP_AGENT_ID` ← required (`ragAgentPath()` throws without it)
- `RAG_AGENT_URL` ← defaults to `localhost:8000` without it (wrong)

Also: QA secret uses `DB_*` naming, but `lib/runtime-env.ts` expects `DATABASE_*`. Either add aliases or change the schema consumer side.

---

## 4. Rollout playbook — get dev current, then QA

### Step 1. Merge ai-platform `development → main` (unblocks dev deploy)

```bash
cd ai-platform/  # from workspace root
git checkout main
git pull origin main
git merge origin/development
git push origin main
```

Triggers `deploy-dev` job in `.github/workflows/api-build-and-push.yaml`:
- Builds `api/Dockerfile.release`
- Pushes to ECR `mmbr-qbrick` in dev account
- Updates SSM `qbrick-image-tag-dev`
- Registers new task def revision
- `update-service` + waits for stability

Watch via `gh run watch -R MMBR-Systems/ai-platform` or ECS console.

### Step 2. Create workflow on dev QAP UI

After qbrick-dev rolls to the new image:

1. Open dev QAP UI (URL in section 2, placeholder for now) — `https://<dev-backend-ui-alb>/agents-builder/`
2. Create a new workflow, wire `rag_agent`, publish it
3. Copy the workflow UUID + generated `api_key` + `api_secret`
4. Update `mmbr-dev-web-platform` secret with:
   - `QAP_AGENT_ID=<new-workflow-uuid>`
   - `QAP_API_KEY=<generated>`
   - `QAP_API_SECRET=<generated>`
   - `QAP_JWT_SECRET=<must match NEXTAUTH_SECRET in mmbr-dev-qbrick>`
   - `RAG_AGENT_URL=http://qbrick:8000` (internal service discovery)
5. Force-redeploy web-platform-dev so it picks up new secret values

### Step 3. Smoke test on dev

From dev web-platform UI: send a chat message, verify citations with `document_url` + `page_number` appear.

### Step 4. QA rollout (once dev is green)

4.1. **Infrastructure prep (infra team):**
- Confirm `ecs-qa` cluster, `qbrick-qa` service, ECR `mmbr-qbrick` exist in account `542035162757` (they do)
- Populate missing keys in `mmbr-qa-web-platform`:
  - `QAP_JWT_SECRET`, `QAP_API_KEY`, `QAP_API_SECRET`, `QAP_AGENT_ID`, `RAG_AGENT_URL`
- Reconcile DB naming: either rename `DB_*` → `DATABASE_*` in the QA secret, or add aliases in `lib/runtime-env.ts` (prefer the former — QA should match dev shape)
- Confirm `mmbr-qa-qbrick` has a current version label (the 2026-04-14 deploy failed on `AWSCURRENT` missing — it's populated now but verify)

4.2. **Trigger first QA deploy:**
```bash
cd ai-platform/  # from workspace root
git checkout -b release-qa/initial-mmbr-183 main
git push -u origin release-qa/initial-mmbr-183
```

Triggers `deploy-qa` job → pushes image to QA ECR → updates SSM → forces qbrick-qa update.

4.3. **Create workflow in QA QAP UI** (same flow as dev step 2)

4.4. **Update `mmbr-qa-web-platform`** with QA workflow's UUID + api_key + api_secret

4.5. **Smoke test from QA web-platform URL**

---

## 5. Open questions / TODO

- [ ] **Dev QAP UI public URL** — confirm with infra team (or derive from Route53 in dev account 455842406405). Needed for manual workflow creation.
- [ ] **QA QAP UI public URL** — same for demo account (542035162757).
- [ ] **DB variable naming inconsistency** — QA secret uses `DB_*`, runtime expects `DATABASE_*`. Needs reconciliation before QA can work.
- [ ] **Decide whether to backfill `mmbr.conversations` for any legacy data** — tied to the H1a fallback in ai-platform (MMBR-183 review). Probably zero rows in dev, but confirm.
- [ ] **Workflow UUID management** — today each environment has its own workflow UUID stored in its own secret. Consider documenting expected pattern (one per env, same agent underneath).

---

## 6. Reference commands

```bash
# SSO login
aws sso login --profile AdministratorAccess-455842406405   # dev
aws sso login --profile AdministratorAccess-542035162757   # demo/QA

# Service status (any env)
aws ecs describe-services --cluster ecs-dev --services qbrick-dev \
  --profile AdministratorAccess-455842406405 --region us-east-2 \
  --query 'services[0].{desired:desiredCount,running:runningCount,rolloutState:deployments[0].rolloutState}'

# Current deployed image SHA
aws ssm get-parameter --name qbrick-image-tag-dev \
  --profile AdministratorAccess-455842406405 --region us-east-2 \
  --query 'Parameter.Value' --output text

# Secret keys (not values, safer for chat)
aws secretsmanager get-secret-value --secret-id mmbr-dev-qbrick \
  --profile AdministratorAccess-455842406405 --region us-east-2 \
  --query SecretString --output text | python3 -c "import sys,json; print('\n'.join(sorted(json.loads(sys.stdin.read()).keys())))"

# Trigger dev deploy — push to main
git push origin main

# Trigger QA deploy — push release-qa/* branch
git checkout -b release-qa/<description>
git push -u origin release-qa/<description>
```

---

_Snapshot produced 2026-04-22. Will go stale once deploys run — re-run queries in section 2/3 to refresh._
