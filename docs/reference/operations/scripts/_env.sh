#!/bin/sh
# Shared env lookup for MMBR AWS ops scripts.
# Source this file from sibling scripts and call resolve_env <env>.
# After resolve_env succeeds, AWS_PROFILE/AWS_REGION + the AWS_* vars below are exported.
#
# Supported envs: dev, qa, prod
# Region is constant: us-east-2

AWS_REGION="us-east-2"
export AWS_REGION

resolve_env() {
  env_name="$1"
  if [ -z "$env_name" ]; then
    echo "Usage: $0 <env>   (env: dev|qa|prod)" >&2
    return 2
  fi

  case "$env_name" in
    dev)
      AWS_PROFILE="AdministratorAccess-455842406405"
      ECS_CLUSTER="ecs-dev"
      WEB_SERVICE="web-platform-dev"
      WEB_CONTAINER="web-platform"
      BASTION_ID="i-0c3297763d5e2f501"
      RDS_HOST="mmbr-dev-rds-proxy.proxy-cfq0o6q0ocfv.us-east-2.rds.amazonaws.com"
      RDS_PORT="5432"
      ;;
    qa)
      AWS_PROFILE="AdministratorAccess-542035162757"
      ECS_CLUSTER="ecs-qa"
      WEB_SERVICE="web-platform-qa"
      WEB_CONTAINER="web-platform"
      BASTION_ID="i-0159859cb317ed24d"
      RDS_HOST="mmbr-qa-rds-proxy.proxy-cfia6guo0e4z.us-east-2.rds.amazonaws.com"
      RDS_PORT="5432"
      ;;
    prod)
      AWS_PROFILE="AdministratorAccess-819743217049"
      ECS_CLUSTER="ecs-prod"
      WEB_SERVICE="web-platform-prod"
      WEB_CONTAINER="web-platform"
      BASTION_ID="i-08bbb0ebb0e55dfce"
      RDS_HOST="mmbr-prod-rds-proxy.proxy-cbukqk42yxep.us-east-2.rds.amazonaws.com"
      RDS_PORT="5432"
      ;;
    *)
      echo "Unknown env: $env_name (expected: dev|qa|prod)" >&2
      return 2
      ;;
  esac

  export AWS_PROFILE ECS_CLUSTER WEB_SERVICE WEB_CONTAINER BASTION_ID RDS_HOST RDS_PORT

  # Friendly check: SSO session may have expired. We do not auto-login because
  # `aws sso login` opens a browser and is interactive.
  if ! aws sts get-caller-identity --profile "$AWS_PROFILE" --region "$AWS_REGION" >/dev/null 2>&1; then
    echo "AWS SSO session is missing or expired for profile $AWS_PROFILE." >&2
    echo "Run: aws sso login --profile $AWS_PROFILE" >&2
    return 3
  fi

  return 0
}

# Resolve the running web-platform task ID for the chosen env.
# Caller must have already called resolve_env.
resolve_task_id() {
  TASK_ID=$(aws ecs list-tasks \
    --cluster "$ECS_CLUSTER" \
    --service-name "$WEB_SERVICE" \
    --profile "$AWS_PROFILE" \
    --region "$AWS_REGION" \
    --query 'taskArns[0]' \
    --output text 2>/dev/null | awk -F'/' '{print $NF}')

  if [ -z "$TASK_ID" ] || [ "$TASK_ID" = "None" ]; then
    echo "No running task found for $WEB_SERVICE on cluster $ECS_CLUSTER." >&2
    return 1
  fi

  export TASK_ID
  return 0
}
