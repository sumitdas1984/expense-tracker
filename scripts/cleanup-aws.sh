#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="ap-south-1"
CLUSTER_NAME="expense-tracker-cluster"
RDS_IDENTIFIER="expense-tracker-db"
NAMESPACE_NAME="expense-tracker.local"

# Security Groups
ECS_SG_NAME="expense-tracker-ecs-sg"
RDS_SG_NAME="expense-tracker-rds-sg"
ALB_SG_NAME="expense-tracker-alb-sg"

SERVICES=(
  "ui-service"
  "report-service"
  "category-service"
  "expense-service"
)

REPOSITORIES=(
  "expense-service"
  "category-service"
  "report-service"
  "ui-service"
)

echo "============================================================"
echo "WARNING: This will delete ALL Expense Tracker resources in $AWS_REGION."
echo "Preserved: node-app-cluster, launch-wizard-1, default VPC/SG."
echo "============================================================"
read -rp "Are you sure you want to proceed with full cleanup? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
  echo "Cleanup cancelled."
  exit 0
fi

echo "=== 1. Scaling Down & Deleting ECS Services ==="
for svc in "${SERVICES[@]}"; do
  STATUS=$(aws ecs describe-services \
    --cluster "$CLUSTER_NAME" \
    --services "$svc" \
    --region "$AWS_REGION" \
    --query "services[?status=='ACTIVE'].serviceName" \
    --output text 2>/dev/null || true)

  if [ -n "$STATUS" ] && [ "$STATUS" != "None" ]; then
    echo "Deleting ECS service '$svc'..."
    aws ecs update-service --cluster "$CLUSTER_NAME" --service "$svc" --desired-count 0 --region "$AWS_REGION" >/dev/null 2>&1 || true
    aws ecs delete-service --cluster "$CLUSTER_NAME" --service "$svc" --force --region "$AWS_REGION" >/dev/null 2>&1 || true
  fi
done

# Wait for active tasks to stop before deleting the cluster
ACTIVE_TASKS=$(aws ecs list-tasks --cluster "$CLUSTER_NAME" --desired-status RUNNING --region "$AWS_REGION" --query "taskArns" --output text 2>/dev/null || true)
if [ -n "$ACTIVE_TASKS" ] && [ "$ACTIVE_TASKS" != "None" ]; then
  echo "Waiting for remaining tasks to stop..."
  aws ecs wait tasks-stopped --cluster "$CLUSTER_NAME" --tasks $ACTIVE_TASKS --region "$AWS_REGION" 2>/dev/null || sleep 15
fi

echo "=== 2. Deleting ECS Cluster ==="
CLUSTER_STATUS=$(aws ecs describe-clusters \
  --clusters "$CLUSTER_NAME" \
  --region "$AWS_REGION" \
  --query "clusters[?status=='ACTIVE'].clusterName" \
  --output text 2>/dev/null || true)

if [ "$CLUSTER_STATUS" = "$CLUSTER_NAME" ]; then
  aws ecs delete-cluster --cluster "$CLUSTER_NAME" --region "$AWS_REGION" >/dev/null
  echo "Deleted cluster: $CLUSTER_NAME"
fi

echo "=== 3. Deleting ALB, Listeners, and Target Groups ==="
# Find any ALB matching expense-tracker
ALB_ARNS=$(aws elbv2 describe-load-balancers \
  --region "$AWS_REGION" \
  --query "LoadBalancers[?contains(LoadBalancerName, 'expense-tracker')].LoadBalancerArn" \
  --output text 2>/dev/null || true)

for alb_arn in $ALB_ARNS; do
  if [ -n "$alb_arn" ] && [ "$alb_arn" != "None" ]; then
    echo "Deleting ALB: $alb_arn..."
    aws elbv2 delete-load-balancer --load-balancer-arn "$alb_arn" --region "$AWS_REGION" >/dev/null
    echo "Waiting for ALB deletion to release ENIs..."
    aws elbv2 wait load-balancers-deleted --load-balancer-arns "$alb_arn" --region "$AWS_REGION" 2>/dev/null || sleep 15
  fi
done

# Delete Target Groups matching expense-tracker
TG_ARNS=$(aws elbv2 describe-target-groups \
  --region "$AWS_REGION" \
  --query "TargetGroups[?contains(TargetGroupName, 'expense') || contains(TargetGroupName, 'category') || contains(TargetGroupName, 'report') || contains(TargetGroupName, 'ui')].TargetGroupArn" \
  --output text 2>/dev/null || true)

for tg_arn in $TG_ARNS; do
  if [ -n "$tg_arn" ] && [ "$tg_arn" != "None" ]; then
    aws elbv2 delete-target-group --target-group-arn "$tg_arn" --region "$AWS_REGION" >/dev/null 2>&1 || true
  fi
done
echo "Load balancer components removed."

echo "=== 4. Deleting Cloud Map Service Discovery ==="
NAMESPACE_ID=$(aws servicediscovery list-namespaces \
  --region "$AWS_REGION" \
  --filters "Name=NAME,Values=${NAMESPACE_NAME}" "Name=TYPE,Values=DNS_PRIVATE" \
  --query "Namespaces[0].Id" \
  --output text 2>/dev/null || true)

if [ -n "$NAMESPACE_ID" ] && [ "$NAMESPACE_ID" != "None" ]; then
  # Services inside the namespace must be deleted first
  SD_SERVICES=$(aws servicediscovery list-services \
    --region "$AWS_REGION" \
    --filters "Name=NAMESPACE_ID,Values=${NAMESPACE_ID}" \
    --query "Services[*].Id" \
    --output text 2>/dev/null || true)

  for sd_svc in $SD_SERVICES; do
    if [ -n "$sd_svc" ] && [ "$sd_svc" != "None" ]; then
      aws servicediscovery delete-service --id "$sd_svc" --region "$AWS_REGION" >/dev/null 2>&1 || true
    fi
  done
  sleep 5
  aws servicediscovery delete-namespace --id "$NAMESPACE_ID" --region "$AWS_REGION" >/dev/null 2>&1 || true
  echo "Deleted Cloud Map namespace: $NAMESPACE_NAME"
fi

echo "=== 5. Deleting IAM Task/Execution Roles ==="
for role in "expense-tracker-execution-role" "expense-tracker-task-role"; do
  ROLE_EXISTS=$(aws iam get-role --role-name "$role" --query "Role.RoleName" --output text 2>/dev/null || true)
  if [ "$ROLE_EXISTS" = "$role" ]; then
    POLICIES=$(aws iam list-attached-role-policies --role-name "$role" --query "AttachedPolicies[*].PolicyArn" --output text 2>/dev/null || true)
    for pol in $POLICIES; do
      aws iam detach-role-policy --role-name "$role" --policy-arn "$pol" 2>/dev/null || true
    done
    aws iam delete-role --role-name "$role" 2>/dev/null || true
    echo "Deleted IAM role: $role"
  fi
done

echo "=== 6. Deleting RDS PostgreSQL Instance ==="
RDS_EXISTS=$(aws rds describe-db-instances \
  --db-instance-identifier "$RDS_IDENTIFIER" \
  --region "$AWS_REGION" \
  --query "DBInstances[0].DBInstanceStatus" \
  --output text 2>/dev/null || true)

if [ -n "$RDS_EXISTS" ] && [ "$RDS_EXISTS" != "None" ] && [ "$RDS_EXISTS" != "deleting" ]; then
  echo "Deleting RDS instance '$RDS_IDENTIFIER'..."
  aws rds delete-db-instance \
    --db-instance-identifier "$RDS_IDENTIFIER" \
    --skip-final-snapshot \
    --delete-automated-backups \
    --region "$AWS_REGION" >/dev/null
  echo "Waiting for RDS instance deletion (takes a few minutes)..."
  aws rds wait db-instance-deleted \
    --db-instance-identifier "$RDS_IDENTIFIER" \
    --region "$AWS_REGION"
  echo "RDS instance deleted."
fi

echo "=== 7. Deleting Project Security Groups ==="
# Retry loop to allow lingering ENIs from ALB and Fargate tasks to detach
for sg_name in "$RDS_SG_NAME" "$ECS_SG_NAME" "$ALB_SG_NAME"; do
  SG_ID=$(aws ec2 describe-security-groups \
    --region "$AWS_REGION" \
    --filters "Name=group-name,Values=$sg_name" \
    --query "SecurityGroups[0].GroupId" \
    --output text 2>/dev/null || true)

  if [ -n "$SG_ID" ] && [ "$SG_ID" != "None" ]; then
    echo "Deleting Security Group '$sg_name' ($SG_ID)..."
    for i in {1..6}; do
      if aws ec2 delete-security-group --group-id "$SG_ID" --region "$AWS_REGION" >/dev/null 2>&1; then
        echo "Deleted $sg_name."
        break
      fi
      sleep 10
    done
  fi
done

echo "=== 8. Deleting ECR Repositories ==="
for repo in "${REPOSITORIES[@]}"; do
  if aws ecr describe-repositories --repository-names "$repo" --region "$AWS_REGION" >/dev/null 2>&1; then
    aws ecr delete-repository --repository-name "$repo" --force --region "$AWS_REGION" >/dev/null
    echo "Deleted ECR repo: $repo"
  fi
done

# Cleanup local generated files
rm -f scripts/.infrastructure-output.env

echo "============================================================"
echo "All Expense Tracker resources cleaned up successfully!"
echo "============================================================"