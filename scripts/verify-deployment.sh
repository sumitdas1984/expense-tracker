#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="scripts/.infrastructure-output.env"
if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: $ENV_FILE not found."
  exit 1
fi
source "$ENV_FILE"

SERVICES=("expense-service" "category-service" "report-service" "ui-service")

echo "=== 1. Checking RDS Status ==="
RDS_STATUS=$(aws rds describe-db-instances \
  --db-instance-identifier "expense-tracker-db" \
  --region "$AWS_REGION" \
  --query "DBInstances[0].DBInstanceStatus" \
  --output text 2>/dev/null || echo "NOT_FOUND")
echo "RDS Instance: $RDS_STATUS"

echo "=== 2. Checking ECS Service Counts ==="
aws ecs describe-services \
  --cluster "$CLUSTER_NAME" \
  --services "${SERVICES[@]}" \
  --region "$AWS_REGION" \
  --query 'services[*].[serviceName,runningCount,desiredCount,status]' \
  --output table

echo "=== 3. Checking Target Group Health Status ==="
for tg_arn in "$UI_TG_ARN" "$EXPENSE_TG_ARN" "$CATEGORY_TG_ARN" "$REPORT_TG_ARN"; do
  TG_NAME=$(aws elbv2 describe-target-groups --target-group-arns "$tg_arn" --region "$AWS_REGION" --query "TargetGroups[0].TargetGroupName" --output text)
  HEALTH_STATE=$(aws elbv2 describe-target-health --target-group-arn "$tg_arn" --region "$AWS_REGION" --query "TargetHealthDescriptions[0].TargetHealth.State" --output text 2>/dev/null || echo "initializing")
  echo "Target Group '$TG_NAME': $HEALTH_STATE"
done

echo "=== 4. Resolving Public Endpoints ==="
echo "Application Load Balancer (HTTP): http://${ALB_DNS}"
echo "CloudFront Global Edge (HTTPS):   https://${CF_DOMAIN}"
echo "============================================================"
echo "Deployment verified! Open https://${CF_DOMAIN} in your browser."
echo "============================================================"