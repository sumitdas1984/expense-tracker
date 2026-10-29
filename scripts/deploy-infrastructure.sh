#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="ap-south-1"
CLUSTER_NAME="expense-tracker-cluster"
RDS_IDENTIFIER="expense-tracker-db"
DB_NAME="expense_tracker"
DB_USERNAME="postgres"
DB_PASSWORD="${DB_PASSWORD:-ExpenseTrackerSecure123}"
DB_SUBNET_GROUP="rds-ec2-db-subnet-group-1"

REPOSITORIES=(
  "expense-service"
  "category-service"
  "report-service"
  "ui-service"
)

OUTPUT_FILE="scripts/.infrastructure-output.env"

echo "=== 1. Checking AWS Identity ==="
aws sts get-caller-identity --region "$AWS_REGION" >/dev/null
echo "Authenticated successfully."

echo "=== 2. Resolving Default VPC and Public Subnets ==="
VPC_ID=$(aws ec2 describe-vpcs \
  --region "$AWS_REGION" \
  --filters "Name=isDefault,Values=true" \
  --query "Vpcs[0].VpcId" \
  --output text)

# Pick subnets that have MapPublicIpOnLaunch=true for Fargate tasks
TASK_SUBNET_IDS=$(aws ec2 describe-subnets \
  --region "$AWS_REGION" \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=map-public-ip-on-launch,Values=true" \
  --query "Subnets[*].SubnetId" \
  --output text | tr '\t' ',')

if [ -z "$TASK_SUBNET_IDS" ] || [ "$TASK_SUBNET_IDS" = "None" ]; then
  # Fallback to all VPC subnets if specific flag is not set
  TASK_SUBNET_IDS=$(aws ec2 describe-subnets \
    --region "$AWS_REGION" \
    --filters "Name=vpc-id,Values=$VPC_ID" \
    --query "Subnets[*].SubnetId" \
    --output text | tr '\t' ',')
fi
echo "Using VPC: $VPC_ID, Task Subnets: $TASK_SUBNET_IDS"

echo "=== 3. Ensuring ECR Repositories Exist with Scan-on-Push ==="
for repo in "${REPOSITORIES[@]}"; do
  if ! aws ecr describe-repositories --repository-names "$repo" --region "$AWS_REGION" >/dev/null 2>&1; then
    aws ecr create-repository --repository-name "$repo" --region "$AWS_REGION" >/dev/null
    echo "Created repo: $repo"
  else
    echo "ECR repo '$repo' exists. Reusing."
  fi
  aws ecr put-image-scanning-configuration \
    --repository-name "$repo" \
    --image-scanning-configuration scanOnPush=true \
    --region "$AWS_REGION" >/dev/null
done

echo "=== 4. Ensuring ECS Cluster Exists ==="
CLUSTER_STATUS=$(aws ecs describe-clusters \
  --clusters "$CLUSTER_NAME" \
  --region "$AWS_REGION" \
  --query "clusters[?status=='ACTIVE'].clusterName | [0]" \
  --output text 2>/dev/null || true)

if [ "$CLUSTER_STATUS" = "$CLUSTER_NAME" ]; then
  echo "ECS cluster '$CLUSTER_NAME' already exists and is ACTIVE. Reusing."
else
  echo "Creating/Reactivating ECS cluster '$CLUSTER_NAME'..."
  aws ecs create-cluster --cluster-name "$CLUSTER_NAME" --region "$AWS_REGION" >/dev/null
  echo "ECS cluster '$CLUSTER_NAME' is ready."
fi

echo "=== 5. Setting Up Security Groups ==="
# ECS Task Security Group
ECS_SG_ID=$(aws ec2 describe-security-groups \
  --region "$AWS_REGION" \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=expense-tracker-ecs-sg" \
  --query "SecurityGroups[0].GroupId" \
  --output text 2>/dev/null || true)

if [ -z "$ECS_SG_ID" ] || [ "$ECS_SG_ID" = "None" ]; then
  ECS_SG_ID=$(aws ec2 create-security-group \
    --group-name "expense-tracker-ecs-sg" \
    --description "Security group for Expense Tracker ECS tasks" \
    --vpc-id "$VPC_ID" \
    --region "$AWS_REGION" \
    --query "GroupId" \
    --output text)
  echo "Created ECS Security Group: $ECS_SG_ID"
else
  echo "ECS Security Group exists: $ECS_SG_ID"
fi

# RDS Security Group
RDS_SG_ID=$(aws ec2 describe-security-groups \
  --region "$AWS_REGION" \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=expense-tracker-rds-sg" \
  --query "SecurityGroups[0].GroupId" \
  --output text 2>/dev/null || true)

if [ -z "$RDS_SG_ID" ] || [ "$RDS_SG_ID" = "None" ]; then
  RDS_SG_ID=$(aws ec2 create-security-group \
    --group-name "expense-tracker-rds-sg" \
    --description "Security group for Expense Tracker RDS PostgreSQL" \
    --vpc-id "$VPC_ID" \
    --region "$AWS_REGION" \
    --query "GroupId" \
    --output text)
  echo "Created RDS Security Group: $RDS_SG_ID"
else
  echo "RDS Security Group exists: $RDS_SG_ID"
fi

# Reconcile Ingress Rule on RDS SG (idempotent)
aws ec2 authorize-security-group-ingress \
  --group-id "$RDS_SG_ID" \
  --protocol tcp \
  --port 5432 \
  --source-group "$ECS_SG_ID" \
  --region "$AWS_REGION" 2>/dev/null || true

# Allow inter-service communication within the ECS security group
aws ec2 authorize-security-group-ingress \
  --group-id "$ECS_SG_ID" \
  --protocol -1 \
  --source-group "$ECS_SG_ID" \
  --region "$AWS_REGION" 2>/dev/null || true

# Allow inbound port 8501 for the Streamlit UI
aws ec2 authorize-security-group-ingress \
  --group-id "$ECS_SG_ID" \
  --protocol tcp \
  --port 8501 \
  --cidr 0.0.0.0/0 \
  --region "$AWS_REGION" 2>/dev/null || true

echo "=== 6. Ensuring RDS PostgreSQL Instance Exists ==="
RDS_STATUS=$(aws rds describe-db-instances \
  --db-instance-identifier "$RDS_IDENTIFIER" \
  --region "$AWS_REGION" \
  --query "DBInstances[0].DBInstanceStatus" \
  --output text 2>/dev/null || true)

if [ -z "$RDS_STATUS" ] || [ "$RDS_STATUS" = "None" ]; then
  # Dynamically pick latest valid 16.x or 17.x engine version
  ENGINE_VER=$(aws rds describe-db-engine-versions \
    --engine postgres \
    --region "$AWS_REGION" \
    --query "DBEngineVersions[?starts_with(EngineVersion, '16.')].EngineVersion" \
    --output text | tr '\t' '\n' | sort -V | tail -1)

  echo "Creating RDS instance '$RDS_IDENTIFIER' with PostgreSQL $ENGINE_VER..."
  aws rds create-db-instance \
    --db-instance-identifier "$RDS_IDENTIFIER" \
    --db-instance-class "db.t3.micro" \
    --engine "postgres" \
    --engine-version "$ENGINE_VER" \
    --allocated-storage 20 \
    --storage-type "gp3" \
    --master-username "$DB_USERNAME" \
    --master-user-password "$DB_PASSWORD" \
    --db-name "$DB_NAME" \
    --db-subnet-group-name "$DB_SUBNET_GROUP" \
    --vpc-security-group-ids "$RDS_SG_ID" \
    --no-publicly-accessible \
    --backup-retention-period 0 \
    --region "$AWS_REGION" >/dev/null
  echo "RDS creation initiated."
fi

echo "Waiting for RDS instance to reach available status..."
aws rds wait db-instance-available \
  --db-instance-identifier "$RDS_IDENTIFIER" \
  --region "$AWS_REGION"

RDS_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier "$RDS_IDENTIFIER" \
  --region "$AWS_REGION" \
  --query "DBInstances[0].Endpoint.Address" \
  --output text)

echo "=== 7. Writing Output Environment File ==="
cat <<EOF > "$OUTPUT_FILE"
AWS_REGION="${AWS_REGION}"
VPC_ID="${VPC_ID}"
TASK_SUBNET_IDS="${TASK_SUBNET_IDS}"
CLUSTER_NAME="${CLUSTER_NAME}"
ECS_SG_ID="${ECS_SG_ID}"
RDS_SG_ID="${RDS_SG_ID}"
RDS_IDENTIFIER="${RDS_IDENTIFIER}"
RDS_ENDPOINT="${RDS_ENDPOINT}"
DB_NAME="${DB_NAME}"
DB_USERNAME="${DB_USERNAME}"
DB_PASSWORD="${DB_PASSWORD}"
EOF

echo "============================================================"
echo "Infrastructure Setup Complete!"
echo "Outputs written to $OUTPUT_FILE"
echo "RDS Endpoint: $RDS_ENDPOINT"
echo "============================================================"
