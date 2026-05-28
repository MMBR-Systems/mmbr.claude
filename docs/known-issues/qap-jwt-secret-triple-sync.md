---
created: 2026-05-07
updated: 2026-05-07
owner: workspace owner
---

# QAP JWT secret must be identical across three Secrets Manager keys (with three different names)

## Symptom

Per-environment, web-platform calls to qbrick start failing with `401 Unauthorized` from `POST /workflows/<id>/invoke` (or any other authenticated qbrick endpoint). web-platform surfaces this to the browser as `502 Bad Gateway` / `{"code": "SERVICE_UNAVAILABLE", "message": "AI assistant is temporarily unavailable. Please try again."}`.

If the misconfigured side is qbrick (it can't validate the token), the qbrick log shows token validation errors. If the misconfigured side is web-platform (it's signing tokens with the wrong secret), the qbrick log shows signature mismatch errors. Both look identical from the browser.

## Where

Three secrets, three different key names, **same value required**. Per env (`dev`, `qa`, `prod`):

| Secret | Key name | Role |
|---|---|---|
| `mmbr-<env>-web-platform` | `QAP_JWT_SECRET` | Canonical name. web-platform signs JWTs with this. |
| `mmbr-<env>-qbrick` | `NEXTAUTH_SECRET` | Legacy alias from Qubika upstream. qbrick validates JWTs with this. |
| `mmbr-<env>-backend-ui` | `NEXTAUTH_SECRET` | Same legacy alias. backend-ui (admin) signs with this when calling qbrick. |

The naming inconsistency is documented in `architecture/auth-flow.md` and `architecture/deployed-services.md`, but the failure mode hasn't been captured as a known-issue until now.

## Cause

The HMAC used to sign and validate the JWT lives under three different env-var names because `qbrick` and `backend-ui` were forked from `qubika-agentic-platform`, which uses NextAuth v4 conventions (`NEXTAUTH_SECRET`). MMBR's `web-platform` was built fresh and named the same value `QAP_JWT_SECRET` for clarity. The three names refer to the same shared HMAC; if any of the three drifts from the others, signature validation fails on whichever side reads the diverged secret.

Primary trigger paths observed:

1. **Devops/IaC rotation** — terraform run or manual rotation that updates one of the three but not the others. Happened on 2026-05-07 in qa, where `mmbr-qa-qbrick.NEXTAUTH_SECRET` was emptied while web-platform and backend-ui kept the right value.
2. **Manual edit in console** by someone unaware of the dependency.
3. **Cross-env secret copy** that overwrites the value with another env's HMAC.

## Workaround

Before any rotation, validate all three are aligned (run per env). The script computes a hash so values never appear in the transcript:

```bash
PROFILE=AdministratorAccess-<env-account-id>

python3 -c "
import json, subprocess, hashlib
def get(s, k):
    out = subprocess.run(['aws','secretsmanager','get-secret-value','--profile','$PROFILE','--region','us-east-2','--secret-id',s,'--query','SecretString','--output','text'], capture_output=True, text=True)
    v = json.loads(out.stdout).get(k, '') if out.returncode == 0 else ''
    return f'len={len(v)} sha[:8]={hashlib.sha256(v.encode()).hexdigest()[:8]}' if v else '(EMPTY)'

env = '<env>'
print(f'web-platform.QAP_JWT_SECRET : {get(f\"mmbr-{env}-web-platform\", \"QAP_JWT_SECRET\")}')
print(f'qbrick.NEXTAUTH_SECRET      : {get(f\"mmbr-{env}-qbrick\", \"NEXTAUTH_SECRET\")}')
print(f'backend-ui.NEXTAUTH_SECRET  : {get(f\"mmbr-{env}-backend-ui\", \"NEXTAUTH_SECRET\")}')
"
```

All three `sha[:8]` should match. If one differs (or is `(EMPTY)`), copy the canonical value into the diverged secret with `put-secret-value`, then `force-new-deployment` on the affected ECS service(s).

## Fix (if planned)

No code fix planned. The alignment is a configuration invariant the IaC and any rotation tooling has to respect. Mitigations to consider:

- IaC convention: have terraform set all three from the same input variable so it's structurally impossible to rotate one without the others.
- Pre-deploy validation step in the deploy pipeline that runs the three-way hash check above and fails the rollout if they diverge.
- Renaming pass: rename `qbrick.NEXTAUTH_SECRET` and `backend-ui.NEXTAUTH_SECRET` to `QAP_JWT_SECRET` to remove the alias confusion, with a transition period reading both.

Until any of those land, anyone touching these secrets should consult this doc and run the alignment check.
