# CI/CD & Deploy Flow

## Overview

GitHub Actions builds a Docker image and deploys to AWS ECS on push to specific branches.

## Branch-to-Environment Mapping

| Branch | Environment | AWS Account | ECS Cluster | ECS Service |
|--------|------------|-------------|-------------|-------------|
| main | dev | 455842406405 | ecs-dev | web-platform-dev |
| release-qa/* | qa | 542035162757 | ecs-qa | web-platform-qa |
| release-prod/* | prod | 819743217049 | ecs-prod | web-platform-prod |

## Deploy Flow

```
git push to branch
  1. GitHub Actions triggers workflow
  2. OIDC authenticates with AWS (no long-lived credentials)
  3. Docker build (multi-stage: pnpm install -> pnpm build -> standalone)
  4. Push image to ECR (tagged with commit SHA)
  5. Update SSM parameter with image tag
  6. Fetch current ECS task definition
  7. Patch container image in task definition
  8. Register new task definition revision
  9. Update ECS service with new task definition
 10. Wait for service stability (ALB health check)
 11. Publish deploy summary
```

## PR Validation (no deploy)

On PRs to development, release-qa/*, release-prod/*:
- **quality-checks** job: pnpm lint, tsc --noEmit, pnpm test
- **build-validation** job: Docker build without push (validates Dockerfile)

## Health Check

**Endpoint:** `GET /health-check`
**Response:** `{ "status": "ok" }`
**Auth:** None (bypassed in proxy.ts)
**Caching:** `force-dynamic` (never cached)

Used by:
- ALB target group health checks (determines if container is healthy)
- ECS service stability (new deploys must pass health check before old container stops)

**Files:**
- `app/health-check/route.ts` - the endpoint
- `proxy.ts` - auth bypass for this path

## Docker Image

**Base:** node:22-alpine
**Package manager:** pnpm via corepack
**Output:** Next.js standalone (.next/standalone + .next/static + public)
**User:** nextjs (UID 1001, non-root)
**Port:** 3000

**Files:**
- `Dockerfile` - multi-stage build
- `.dockerignore` - excludes node_modules, .next, .git, .env*, tests

## Runtime Environment

Config is read via `lib/runtime-env.ts`, not direct `process.env`:
- `getRuntimeEnv(name)` - checks process.env first, then SECRETS JSON blob
- `requireEnv(name)` - same but throws if missing
- ECS injects secrets via a JSON-encoded `SECRETS` env var from Secrets Manager

See `lib/runtime-env.ts` for: getAuth0Domain(), getDatabaseUrl(), getQbrickBaseUrl()

## Key Files

| File | Purpose |
|------|---------|
| `.github/workflows/web-build-and-push.yaml` | CI/CD workflow |
| `Dockerfile` | Docker build |
| `.dockerignore` | Build context exclusions |
| `app/health-check/route.ts` | ALB health check endpoint |
| `lib/runtime-env.ts` | Environment variable abstraction |
| `next.config.ts` | `output: "standalone"` for Docker |

## AWS Resources (dev)

- **ECR:** mmbr-web-platform
- **ECS cluster:** ecs-dev
- **ECS service:** web-platform-dev
- **Task definition:** dev-web-platform
- **SSM parameter:** web-platform-image-tag-dev
- **OIDC role:** github_oidc_role
- **Region:** us-east-2
