# Deployed Services

Three ECS services run the MMBR stack in each environment (`dev`, `qa`, `prod`). The naming is inherited from upstream Qubika conventions and is not self-explanatory - read this before touching deploys, secrets, or onboarding someone new.

## Services and roles

| Service pattern | Role | URL (dev) | Source repo | Runtime |
|---|---|---|---|---|
| `web-platform-<env>` | MMBR product. Both the browser UI and its own server-side API routes (BFF pattern). | `dev.mem-brain.com` | `web-platform/` (MMBR-Systems) | Node.js, Next.js |
| `qbrick-<env>` | QAP backend. No UI. Reached internally only. | `qbrick:8000` (service discovery) | `ai-platform/` (MMBR-Systems) | Python, FastAPI |
| `backend-ui-<env>` | QAP admin UI. Separate Next.js app used to manage workflows and agents inside `qbrick`. Despite "backend" in the name, it IS a frontend. | `ui.dev.mem-brain.com` | upstream `qubika-agentic-platform/` (thisisqubika) | Node.js, Next.js + next-auth |

The three-service split means:

- `web-platform` is the only service users hit directly when using the product. All chat, documents, profile, etc. flows start there.
- `qbrick` is hit only by `web-platform` (for user-facing requests) and `backend-ui` (for admin requests). It is not exposed on a public domain.
- `backend-ui` is used by the team to configure workflows, not by end users. It authenticates against `qbrick` the same way `web-platform` does (shared HMAC).

## Secrets and how they're wired

Each service has its own AWS Secrets Manager secret. Naming pattern: `mmbr-<env>-<service-name>-<random>`. Examples from dev:

- `mmbr-dev-web-platform-343CvE`
- `mmbr-dev-qbrick-UK0Kan`
- `mmbr-dev-backend-ui-*`

Values are injected into the ECS task definition two ways:

1. **Individual env vars** via `secrets: [{name, valueFrom}]`, using the ARN JSON-key syntax: `arn:...:secret:<name>-XXXX:<KEY>::`. The container sees them as normal env vars.
2. **A bundled `SECRETS` env var** that holds the full JSON blob. `web-platform/lib/runtime-env.ts` parses it on first read. Any key inside the blob is reachable via `getRuntimeEnv(name)`.

Some legacy code paths (`web-platform/proxy.ts`, auth route handlers) read `process.env.AUTH0_*` directly and require the values as individual env vars, not only inside the JSON. When adding a new Auth0 or QAP variable, map it both as an individual env var AND keep it in the JSON blob to avoid missing either code path.

## Authentication between services

Two trust layers, both must be correctly provisioned for any QAP call to succeed. Details in [`external-apis/qap-auth-layers.md`](../external-apis/qap-auth-layers.md).

### Layer 1 - shared HMAC for JWT signing

Global per environment. All three services hold the same value under three different env var names (legacy aliases):

| Service | Env var name |
|---|---|
| `web-platform` | `QAP_JWT_SECRET` |
| `qbrick` | `NEXTAUTH_SECRET` (current) or `QAP_JWT_SECRET` (also accepted by the code) |
| `backend-ui` | `NEXTAUTH_SECRET` |

Mismatch here means every JWT verification fails with 401 before any business logic runs.

### Layer 2 - per-workflow API key / secret

Stored in `qbrick`'s Postgres (`workflow_description` + `ApiKey` tables). Generated via `POST /workflow_descriptions/{workflow_id}/generate_api_key`. The secret is shown once and the sha256 hash is stored.

Web-platform env vars: `QAP_AGENT_ID`, `QAP_API_KEY`, `QAP_API_SECRET`. These cannot be reused across environments - they are database-scoped to one specific `qbrick` instance.

## CI/CD

Managed by `.github/workflows/web-build-and-push.yaml` in `web-platform/`. Mechanics:

- Merging to `development` → deploys to dev (build image, push to ECR, register a new task definition revision with the new image, update the service).
- Merging to a `release-qa/*` branch → deploys to qa.
- Merging to a `release-prod/*` branch → deploys to prod.
- The task definition environment / secrets are preserved across deploys - only the image tag changes. Env var or secret changes must be made in Terraform (owned by infra team) so the next task definition revision picks them up.

Similar flows exist for `ai-platform/` and the upstream for `backend-ui`. Cross-repo deploys are independent - a web-platform deploy does not redeploy `qbrick` or `backend-ui`.

## Where to look when things break

| Symptom | First place to check |
|---|---|
| Login page loads but signing in does nothing | Auth0 dashboard has this env's callback URL and `AUTH0_BASE_URL` in the secret matches the hosted URL exactly. See `setup/auth0-dashboard.md`. |
| Chat request returns 502 or the server logs show `ECONNREFUSED 127.0.0.1:8000` | The QAP base URL is unset or wrong in the web-platform task def. The code reads `RAG_AGENT_URL` first, then `QBRICK_BASE_URL`. In a deployed env it should point to `http://qbrick:8000`. |
| Chat request returns 401 | Shared HMAC mismatch between `web-platform` and `qbrick`. Confirm both hold the same value under their respective env var names. |
| Chat request returns 401 "Unauthorized or workflow not available" | `QAP_AGENT_ID` does not exist in this env's `qbrick` Postgres, or the `QAP_API_KEY` / `QAP_API_SECRET` do not match the DB row. Regenerate via the QAP admin UI. |
| `ui.<env>.mem-brain.com/agents` renders a Server Components error page | `backend-ui` does not have `NEXTAUTH_SECRET` set. The next-auth library throws `[next-auth][error][NO_SECRET]` and the page can't render. Fix on the `backend-ui` task definition. |
