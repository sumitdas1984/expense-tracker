#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="scripts/.infrastructure-output.env"
if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: $ENV_FILE not found. Run deploy-infrastructure.sh first."
  exit 1
fi
source "$ENV_FILE"

NAMESPACE_NAME="expense-tracker.local"
EXECUTION_ROLE_NAME="expense-tracker-execution-role"

# Map ports for services
declare -A SERVICE_PORTS=(
  ["expense-service"]="8001"
  ["category-service"]="8002"
  ["report-service"]="8003"
  ["ui-service"]="8501"
)

SERVICES=("expense-service" "category-service" "report-service" "ui-service")

echo "=== 1. Ensuring IAM Task Execution Role Exists ==="
ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text)
ROLE_ARN=$(aws iam get-role --role-name "$EXECUTION_ROLE_NAME" --query "Role.Arn" --output text 2>/dev/null || true)

if [ -z "$ROLE_ARN" ] || [ "$ROLE_ARN" = "None" ]; then
  TRUST_POLICY='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ecs-tasks.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
  
  ROLE_ARN=$(aws iam create-role \
    --role-name "$EXECUTION_ROLE_NAME" \
    --assume-role-policy-document "$TRUST_POLICY" \
    --query "Role.Arn" --output text)
  
  aws iam attach-role-policy \
    --role-name "$EXECUTION_ROLE_NAME" \
    --policy-arn "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
  echo "Created IAM Execution Role: $ROLE_ARN"
  sleep 10 # Allow IAM eventual consistency
else
  echo "IAM Execution Role exists: $ROLE_ARN"
fi

echo "=== 2. Ensuring CloudWatch Log Group Exists ==="
aws logs create-log-group --log-group-name "/ecs/expense-tracker" --region "$AWS_REGION" 2>/dev/null || true

echo "=== 3. Ensuring Cloud Map Private DNS Namespace Exists ==="
NAMESPACE_ID=$(aws servicediscovery list-namespaces \
  --region "$AWS_REGION" \
  --filters "Name=NAME,Values=${NAMESPACE_NAME}" "Name=TYPE,Values=DNS_PRIVATE" \
  --query "Namespaces[0].Id" --output text 2>/dev/null || true)

if [ -z "$NAMESPACE_ID" ] || [ "$NAMESPACE_ID" = "None" ]; then
  OP_ID=$(aws servicediscovery create-private-dns-namespace \
    --name "$NAMESPACE_NAME" \
    --vpc "$VPC_ID" \
    --region "$AWS_REGION" \
    --query "OperationId" --output text)
  echo "Creating Cloud Map namespace $NAMESPACE_NAME (waiting)..."
  while true; do
    OP_STATUS=$(aws servicediscovery get-operation --operation-id "$OP_ID" --region "$AWS_REGION" --query "Operation.Status" --output text)
    if [ "$OP_STATUS" = "SUCCESS" ]; then break; fi
    sleep 3
  done
  NAMESPACE_ID=$(aws servicediscovery list-namespaces \
    --region "$AWS_REGION" \
    --filters "Name=NAME,Values=${NAMESPACE_NAME}" \
    --query "Namespaces[0].Id" --output text)
  echo "Created Cloud Map Namespace ID: $NAMESPACE_ID"
else
  echo "Cloud Map Namespace exists: $NAMESPACE_ID"
fi

echo "=== 4. Docker Login & Build/Push Images ==="
REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$REGISTRY"

for svc in "${SERVICES[@]}"; do
  IMAGE_TAG="${REGISTRY}/${svc}:latest"
  echo "Building and pushing $svc..."
  docker build -q -t "$IMAGE_TAG" -f "${svc}/Dockerfile" "${svc}"
  docker push -q "$IMAGE_TAG"
done

echo "=== 5. Register Task Definitions & Create/Update ECS Services ==="
DATABASE_URL="postgresql+psycopg://${DB_USERNAME}:${DB_PASSWORD}@${RDS_ENDPOINT}:5432/${DB_NAME}"

for svc in "${SERVICES[@]}"; do
  port="${SERVICE_PORTS[$svc]}"
  IMAGE_TAG="${REGISTRY}/${svc}:latest"

  # Cloud Map discovery registration
  SD_ARN=$(aws servicediscovery list-services \
    --region "$AWS_REGION" \
    --filters "Name=NAMESPACE_ID,Values=${NAMESPACE_ID}" \
    --query "Services[?Name=='$svc'].Arn | [0]" --output text 2>/dev/null || true)

  if [ -z "$SD_ARN" ] || [ "$SD_ARN" = "None" ]; then
    SD_ARN=$(aws servicediscovery create-service \
      --name "$svc" \
      --namespace-id "$NAMESPACE_ID" \
      --dns-config "RoutingPolicy=MULTIVALUE,DnsRecords=[{Type=A,TTL=60}]" \
      --region "$AWS_REGION" \
      --query "Service.Arn" --output text)
  fi

  # Environment variables per service
  ENV_JSON="[]"
  if [ "$svc" = "expense-service" ] || [ "$svc" = "category-service" ]; then
    ENV_JSON="[{\"name\":\"DATABASE_URL\",\"value\":\"${DATABASE_URL}\"}]"
  elif [ "$svc" = "report-service" ]; then
    ENV_JSON="[
      {\"name\":\"EXPENSE_SERVICE_URL\",\"value\":\"http://expense-service.${NAMESPACE_NAME}:8001\"},
      {\"name\":\"CATEGORY_SERVICE_URL\",\"value\":\"http://category-service.${NAMESPACE_NAME}:8002\"}
    ]"
  elif [ "$svc" = "ui-service" ]; then
    ENV_JSON="[
      {\"name\":\"EXPENSE_SERVICE_URL\",\"value\":\"http://expense-service.${NAMESPACE_NAME}:8001\"},
      {\"name\":\"CATEGORY_SERVICE_URL\",\"value\":\"http://category-service.${NAMESPACE_NAME}:8002\"},
      {\"name\":\"REPORT_SERVICE_URL\",\"value\":\"http://report-service.${NAMESPACE_NAME}:8003\"}
    ]"
  fi

  # Register Task Definition
  TASK_DEF_JSON=$(cat <<EOF
{
  "family": "${svc}",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "256",
  "memory": "512",
  "executionRoleArn": "${ROLE_ARN}",
  "containerDefinitions": [
    {
      "name": "${svc}",
      "image": "${IMAGE_TAG}",
      "essential": true,
      "portMappings": [{"containerPort": ${port}, "protocol": "tcp"}],
      "environment": ${ENV_JSON},
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/expense-tracker",
          "awslogs-region": "${AWS_REGION}",
          "awslogs-stream-prefix": "${svc}"
        }
      }
    }
  ]
}
EOF
)
  aws ecs register-task-definition --cli-input-json "$TASK_DEF_JSON" --region "$AWS_REGION" >/dev/null

  # Create or update service
  # Keep comma-separated format without spaces:
  NETWORK_CONFIG="awsvpcConfiguration={subnets=[${TASK_SUBNET_IDS}],securityGroups=[${ECS_SG_ID}],assignPublicIp=ENABLED}"

  SVC_EXISTS=$(aws ecs describe-services \
    --cluster "$CLUSTER_NAME" \
    --services "$svc" \
    --region "$AWS_REGION" \
    --query "services[?status=='ACTIVE'].serviceName | [0]" \
    --output text 2>/dev/null || true)

  if [ -z "$SVC_EXISTS" ] || [ "$SVC_EXISTS" = "None" ]; then
    echo "Creating ECS service '$svc'..."
    aws ecs create-service \
      --cluster "$CLUSTER_NAME" \
      --service-name "$svc" \
      --task-definition "$svc" \
      --launch-type FARGATE \
      --desired-count 1 \
      --network-configuration "$NETWORK_CONFIG" \
      --service-registries "registryArn=${SD_ARN}" \
      --region "$AWS_REGION" >/dev/null
  else
    echo "Updating ECS service '$svc'..."
    aws ecs update-service \
      --cluster "$CLUSTER_NAME" \
      --service "$svc" \
      --task-definition "$svc" \
      --desired-count 1 \
      --region "$AWS_REGION" >/dev/null
  fi
done

echo "=== 6. Waiting for Services to Reach Steady State ==="
aws ecs wait services-stable \
  --cluster "$CLUSTER_NAME" \
  --services "${SERVICES[@]}" \
  --region "$AWS_REGION"

echo "============================================================"
echo "All microservices deployed and stable!"
echo "============================================================"
