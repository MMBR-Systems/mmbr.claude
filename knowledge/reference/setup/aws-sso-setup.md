# AWS SSO Setup

## Configuration

Configured via `aws configure sso` on 2026-04-11.

| Setting | Value |
|---------|-------|
| SSO session name | MMBR |
| SSO start URL | https://d-9a6757353d.awsapps.com/start/ |
| SSO region | us-east-2 |
| Account ID | 455842406405 |
| Role | AdministratorAccess |
| Default region | us-east-2 |
| Output format | json (default) |
| Profile name | AdministratorAccess-455842406405 |

## AWS Accounts

| Account | ID | Purpose |
|---------|-----|---------|
| MMBR Systems | 363267119562 | Main/management account |
| MMBR-Knowledge-dev | 455842406405 | Dev environment - `ecs-dev` cluster lives here |
| MMBR-Knowledge-demo | 542035162757 | QA/demo environment |
| MMBR-Knowledge-prod | 819743217049 | Production environment |

## Resources (dev account - 455842406405)

### ECS cluster: `ecs-dev`

| Service | ECR Repo | Status |
|---------|----------|--------|
| `web-platform-dev` | `mmbr-web-platform` | Active (desired: 1, running: 0) |
| `qbrick-dev` | `mmbr-qbrick` | - |
| `backend-ui-dev` | `mmbr-backend-ui` | - |

Task definition: `dev-web-platform:1`
Region: `us-east-2`

## Usage

```bash
# Login (opens browser for SSO auth)
aws sso login --profile AdministratorAccess-455842406405

# Verify identity
aws sts get-caller-identity --profile AdministratorAccess-455842406405

# List ECS clusters
aws ecs list-clusters --profile AdministratorAccess-455842406405

# List services in dev cluster
aws ecs list-services --cluster ecs-dev --profile AdministratorAccess-455842406405

# Describe web-platform service
aws ecs describe-services --cluster ecs-dev --services web-platform-dev --profile AdministratorAccess-455842406405

# Quick status check (any service)
aws ecs describe-services --cluster ecs-dev --services web-platform-dev --profile AdministratorAccess-455842406405 --query 'services[0].{status:status,desired:desiredCount,running:runningCount}'
aws ecs describe-services --cluster ecs-dev --services qbrick-dev --profile AdministratorAccess-455842406405 --query 'services[0].{status:status,desired:desiredCount,running:runningCount}'
aws ecs describe-services --cluster ecs-dev --services backend-ui-dev --profile AdministratorAccess-455842406405 --query 'services[0].{status:status,desired:desiredCount,running:runningCount}'

# List ECR repositories
aws ecr describe-repositories --profile AdministratorAccess-455842406405

# --- Secrets Manager ---

# Read a secret (JSON formatted)
aws secretsmanager get-secret-value --secret-id mmbr-dev-web-platform --profile AdministratorAccess-455842406405 --query 'SecretString' --output text | python3 -m json.tool

# List all secrets
aws secretsmanager list-secrets --profile AdministratorAccess-455842406405 --query 'SecretList[].Name' --output text

# --- CloudWatch Logs ---

# List log groups
aws logs describe-log-groups --profile AdministratorAccess-455842406405 --query 'logGroups[].logGroupName' --output text

# Get latest logs from web-platform
aws logs describe-log-streams --log-group-name web-platform-dev --order-by LastEventTime --descending --limit 1 --profile AdministratorAccess-455842406405 --query 'logStreams[0].logStreamName' --output text
```

## Secrets

| Secret Name | Service | Key vars |
|-------------|---------|----------|
| `mmbr-dev-web-platform` | web-platform-dev | DB_*, DEV_BYPASS_AUTH, QBRICK_BASE_URL |

Console: AWS Portal > MMBR-Knowledge-dev > Secrets Manager > `mmbr-dev-web-platform` > "Retrieve secret value"
