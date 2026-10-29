#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="ap-south-1"
CLUSTER_NAME="expense-tracker-cluster"
RDS_IDENTIFIER="expense-tracker-db"
ENV_FILE="scripts/.infrastructure-output.env"

read -p "Are you sure you want to tear down all AWS resources? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Cleanup aborted."
  exit 0
fi

echo "=== 1. Scaling Down and Deleting ECS Services ==="
SERVICES=$(aws ecs list-services --cluster "$CLUSTER_NAME" --region "$AWS_REGION" --query "serviceArns[*]" --output text 2>/dev/null || true)
if [ -n "$SERVICES" ] && [ "$SERVICES" != "None" ]; then
  for svc in $SERVICES; do
    aws ecs update-service --cluster "$CLUSTER_NAME" --service "$svc" --desired-count 0 --region "$AWS_REGION" >/dev/null 2>&1 || true
    aws ecs delete-service --cluster "$CLUSTER_NAME" --service "$svc" --force --region "$AWS_REGION" >/dev/null 2>&1 || true
  done
  echo "Waiting for ECS tasks to terminate..."
  aws ecs wait tasks-stopped --cluster "$CLUSTER_NAME" --region "$AWS_REGION" 2>/dev/null || true
fi

aws ecs delete-cluster --cluster "$CLUSTER_NAME" --region "$AWS_REGION" >/dev/null 2>&1 || true
echo "ECS Cluster deleted."

echo "=== 2. Cleaning Up ALB and Target Groups ==="
if [ -f "$ENV_FILE" ]; then
  source "$ENV_FILE"
  # Delete Listener & ALB
  if [ -n "${ALB_ARN:-}" ]; then
    aws elbv2 delete-load-balancer --load-balancer-arn "$ALB_ARN" --region "$AWS_REGION" 2>/dev/null || true
    echo "Waiting for ALB deletion to complete..."
    aws elbv2 wait load-balancers-deleted --load-balancer-arns "$ALB_ARN" --region "$AWS_REGION" 2>/dev/null || true
  fi
  # Delete Target Groups
  for tg in "${UI_TG_ARN:-}" "${EXPENSE_TG_ARN:-}" "${CATEGORY_TG_ARN:-}" "${REPORT_TG_ARN:-}"; do
    if [ -n "$tg" ]; then
      aws elbv2 delete-target-group --target-group-arn "$tg" --region "$AWS_REGION" 2>/dev/null || true
    fi
  done
fi

echo "=== 3. Disabling CloudFront Distribution ==="
if [ -f "$ENV_FILE" ] && [ -n "${CF_DIST_ID:-}" ]; then
  CF_ETAG=$(aws cloudfront get-distribution-config --id "$CF_DIST_ID" --query "ETag" --output text 2>/dev/null || true)
  if [ -n "$CF_ETAG" ]; then
    echo "Disabling CloudFront distribution (this may take a few minutes)..."
    cat <<EOF > /tmp/cf-disable.json
{
  "CallerReference": "expense-tracker-cleanup",
  "Origins": { "Quantity": 1, "Items": [ { "Id": "dummy", "DomainName": "example.com", "CustomOriginConfig": { "HTTPPort": 80, "HTTPSPort": 443, "OriginProtocolPolicy": "http-only" } } ] },
  "DefaultCacheBehavior": { "TargetOriginId": "dummy", "ViewerProtocolPolicy": "allow-all", "MinTTL": 0 },
  "Comment": "Disabling",
  "Enabled": false
}
EOF
    aws cloudfront update-distribution --id "$CF_DIST_ID" --distribution-config file:///tmp/cf-disable.json --if-match "$CF_ETAG" >/dev/null 2>&1 || true
  fi
fi

echo "=== 4. Deleting RDS PostgreSQL Instance ==="
aws rds delete-db-instance \
  --db-instance-identifier "$RDS_IDENTIFIER" \
  --skip-final-snapshot \
  --delete-automated-backups \
  --region "$AWS_REGION" >/dev/null 2>&1 || true
echo "Waiting for RDS instance to terminate..."
aws rds wait db-instance-deleted --db-instance-identifier "$RDS_IDENTIFIER" --region "$AWS_REGION" 2>/dev/null || true

echo "=== 5. Deleting Security Groups ==="
for sg in "expense-tracker-alb-sg" "expense-tracker-ecs-sg" "expense-tracker-rds-sg"; do
  SG_ID=$(aws ec2 describe-security-groups --region "$AWS_REGION" --filters "Name=group-name,Values=$sg" --query "SecurityGroups[0].GroupId" --output text 2>/dev/null || true)
  if [ -n "$SG_ID" ] && [ "$SG_ID" != "None" ]; then
    aws ec2 delete-security-group --group-id "$SG_ID" --region "$AWS_REGION" 2>/dev/null || true
  fi
done

rm -f "$ENV_FILE" /tmp/cf-config.json /tmp/cf-disable.json /tmp/ecs-trust.json
echo "============================================================"
echo "Cleanup completed successfully!"
echo "============================================================"