#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="ap-south-1"
CLUSTER_NAME="expense-tracker-cluster"
RDS_IDENTIFIER="expense-tracker-db"
DB_NAME="expense_tracker"
DB_USERNAME="postgres"
DB_PASSWORD="${DB_PASSWORD:-ExpenseTrackerSecure123}"
DB_SUBNET_GROUP="rds-ec2-db-subnet-group-1"
OUTPUT_FILE="scripts/.infrastructure-output.env"

REPOSITORIES=(
  "expense-service"
  "category-service"
  "report-service"
  "ui-service"
)

echo "=== 1. Checking AWS Identity ==="
ACCOUNT_ID=$(aws sts get-caller-identity --region "$AWS_REGION" --query "Account" --output text)
echo "Authenticated to Account: $ACCOUNT_ID"

echo "=== 2. Resolving Default VPC and Subnets ==="
VPC_ID=$(aws ec2 describe-vpcs \
  --region "$AWS_REGION" \
  --filters "Name=isDefault,Values=true" \
  --query "Vpcs[0].VpcId" \
  --output text)

SUBNET_LIST=($(aws ec2 describe-subnets \
  --region "$AWS_REGION" \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=map-public-ip-on-launch,Values=true" \
  --query "Subnets[*].SubnetId" \
  --output text))

TASK_SUBNET_IDS=$(IFS=,; echo "${SUBNET_LIST[*]}")
ALB_SUBNETS=("${SUBNET_LIST[@]:0:2}")
echo "Using VPC: $VPC_ID, Subnets: $TASK_SUBNET_IDS"

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

echo "=== 4. Ensuring ECS Cluster Exists and is ACTIVE ==="
CLUSTER_STATUS=$(aws ecs describe-clusters \
  --clusters "$CLUSTER_NAME" \
  --region "$AWS_REGION" \
  --query "clusters[?status=='ACTIVE'].clusterName | [0]" \
  --output text 2>/dev/null || true)

if [ "$CLUSTER_STATUS" = "$CLUSTER_NAME" ]; then
  echo "ECS cluster '$CLUSTER_NAME' already exists and is ACTIVE."
else
  aws ecs create-cluster --cluster-name "$CLUSTER_NAME" --region "$AWS_REGION" >/dev/null
  echo "Created/Reactivated ECS cluster: $CLUSTER_NAME"
fi

echo "=== 5. Setting Up Security Groups ==="
# ALB Security Group (Public HTTP from world)
ALB_SG_ID=$(aws ec2 describe-security-groups \
  --region "$AWS_REGION" \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=expense-tracker-alb-sg" \
  --query "SecurityGroups[0].GroupId" \
  --output text 2>/dev/null || true)

if [ -z "$ALB_SG_ID" ] || [ "$ALB_SG_ID" = "None" ]; then
  ALB_SG_ID=$(aws ec2 create-security-group \
    --group-name "expense-tracker-alb-sg" \
    --description "Security group for Expense Tracker ALB" \
    --vpc-id "$VPC_ID" \
    --region "$AWS_REGION" \
    --query "GroupId" --output text)
  echo "Created ALB Security Group: $ALB_SG_ID"
fi
aws ec2 authorize-security-group-ingress \
  --group-id "$ALB_SG_ID" --protocol tcp --port 80 --cidr 0.0.0.0/0 \
  --region "$AWS_REGION" 2>/dev/null || true

# ECS Tasks Security Group (Inbound only from ALB and internal tasks)
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
    --query "GroupId" --output text)
  echo "Created ECS Security Group: $ECS_SG_ID"
fi
aws ec2 authorize-security-group-ingress \
  --group-id "$ECS_SG_ID" --protocol -1 --source-group "$ECS_SG_ID" \
  --region "$AWS_REGION" 2>/dev/null || true
aws ec2 authorize-security-group-ingress \
  --group-id "$ECS_SG_ID" --protocol tcp --port 8000-8501 --source-group "$ALB_SG_ID" \
  --region "$AWS_REGION" 2>/dev/null || true

# RDS Security Group (Inbound 5432 only from ECS tasks)
RDS_SG_ID=$(aws ec2 describe-security-groups \
  --region "$AWS_REGION" \
  --filters "Name=vpc-id,Values=$VPC_ID" "Name=group-name,Values=expense-tracker-rds-sg" \
  --query "SecurityGroups[0].GroupId" \
  --output text 2>/dev/null || true)

if [ -z "$RDS_SG_ID" ] || [ "$RDS_SG_ID" = "None" ]; then
  RDS_SG_ID=$(aws ec2 create-security-group \
    --group-name "expense-tracker-rds-sg" \
    --description "Security group for Expense Tracker RDS" \
    --vpc-id "$VPC_ID" \
    --region "$AWS_REGION" \
    --query "GroupId" --output text)
  echo "Created RDS Security Group: $RDS_SG_ID"
fi
aws ec2 authorize-security-group-ingress \
  --group-id "$RDS_SG_ID" --protocol tcp --port 5432 --source-group "$ECS_SG_ID" \
  --region "$AWS_REGION" 2>/dev/null || true

echo "=== 6. Setting Up Application Load Balancer & Target Groups ==="
ALB_ARN=$(aws elbv2 describe-load-balancers \
  --region "$AWS_REGION" \
  --names "expense-tracker-alb" \
  --query "LoadBalancers[0].LoadBalancerArn" \
  --output text 2>/dev/null || true)

if [ -z "$ALB_ARN" ] || [ "$ALB_ARN" = "None" ]; then
  ALB_ARN=$(aws elbv2 create-load-balancer \
    --name "expense-tracker-alb" \
    --subnets "${ALB_SUBNETS[@]}" \
    --security-groups "$ALB_SG_ID" \
    --region "$AWS_REGION" \
    --query "LoadBalancers[0].LoadBalancerArn" --output text)
  echo "Created ALB: $ALB_ARN"
fi

ALB_DNS=$(aws elbv2 describe-load-balancers \
  --load-balancer-arns "$ALB_ARN" \
  --region "$AWS_REGION" \
  --query "LoadBalancers[0].DNSName" --output text)

# Helper function to create target groups
create_or_get_tg() {
  local name=$1
  local port=$2
  local health_path=$3
  local tg_arn
  tg_arn=$(aws elbv2 describe-target-groups \
    --names "$name" --region "$AWS_REGION" \
    --query "TargetGroups[0].TargetGroupArn" --output text 2>/dev/null || true)
  if [ -z "$tg_arn" ] || [ "$tg_arn" = "None" ]; then
    tg_arn=$(aws elbv2 create-target-group \
      --name "$name" \
      --protocol HTTP \
      --port "$port" \
      --vpc-id "$VPC_ID" \
      --target-type ip \
      --health-check-path "$health_path" \
      --region "$AWS_REGION" \
      --query "TargetGroups[0].TargetGroupArn" --output text)
  fi
  echo "$tg_arn"
}

UI_TG_ARN=$(create_or_get_tg "tg-ui-service" 8501 "/_stcore/health")
EXPENSE_TG_ARN=$(create_or_get_tg "tg-expense-service" 8001 "/health")
CATEGORY_TG_ARN=$(create_or_get_tg "tg-category-service" 8002 "/health")
REPORT_TG_ARN=$(create_or_get_tg "tg-report-service" 8003 "/health")

# Enable stickiness on UI Target Group for Streamlit
aws elbv2 modify-target-group-attributes \
  --target-group-arn "$UI_TG_ARN" \
  --attributes Key=stickiness.enabled,Value=true Key=stickiness.type,Value=lb_cookie Key=stickiness.lb_cookie.duration_seconds,Value=86400 \
  --region "$AWS_REGION" >/dev/null

ORIGIN_HEADER_VALUE="ExpenseTrackerSecureHeader123"

# Listener on ALB Port 80
LISTENER_ARN=$(aws elbv2 describe-listeners \
  --load-balancer-arn "$ALB_ARN" \
  --region "$AWS_REGION" \
  --query "Listeners[?Port==\`80\`].ListenerArn | [0]" \
  --output text 2>/dev/null || true)

if [ -z "$LISTENER_ARN" ] || [ "$LISTENER_ARN" = "None" ]; then
  LISTENER_ARN=$(aws elbv2 create-listener \
    --load-balancer-arn "$ALB_ARN" \
    --protocol HTTP \
    --port 80 \
    --default-actions Type=forward,TargetGroupArn="$UI_TG_ARN" \
    --region "$AWS_REGION" \
    --query "Listeners[0].ListenerArn" --output text)
  echo "Created ALB HTTP Listener."

  # Path Rules for Microservices
  aws elbv2 create-rule --listener-arn "$LISTENER_ARN" --priority 10 \
    --conditions Field=path-pattern,Values='/expenses*' \
    --actions Type=forward,TargetGroupArn="$EXPENSE_TG_ARN" --region "$AWS_REGION" >/dev/null
  aws elbv2 create-rule --listener-arn "$LISTENER_ARN" --priority 20 \
    --conditions Field=path-pattern,Values='/categories*' \
    --actions Type=forward,TargetGroupArn="$CATEGORY_TG_ARN" --region "$AWS_REGION" >/dev/null
  aws elbv2 create-rule --listener-arn "$LISTENER_ARN" --priority 30 \
    --conditions Field=path-pattern,Values='/reports*' \
    --actions Type=forward,TargetGroupArn="$REPORT_TG_ARN" --region "$AWS_REGION" >/dev/null
fi

echo "=== 7. Setting Up CloudFront Distribution ==="
CF_DIST_ID=$(aws cloudfront list-distributions \
  --query "DistributionList.Items[?Origins.Items[?DomainName=='${ALB_DNS}']].Id | [0]" \
  --output text 2>/dev/null || true)

if [ -z "$CF_DIST_ID" ] || [ "$CF_DIST_ID" = "None" ]; then
  cat <<EOF > /tmp/cf-config.json
{
  "CallerReference": "expense-tracker-$(date +%s)",
  "Origins": {
    "Quantity": 1,
    "Items": [
      {
        "Id": "alb-origin",
        "DomainName": "${ALB_DNS}",
        "CustomOriginConfig": {
          "HTTPPort": 80,
          "HTTPSPort": 443,
          "OriginProtocolPolicy": "http-only",
          "OriginKeepaliveTimeout": 60,
          "OriginReadTimeout": 60
        },
        "CustomHeaders": {
          "Quantity": 1,
          "Items": [
            {
              "HeaderName": "X-Origin-Verify",
              "HeaderValue": "${ORIGIN_HEADER_VALUE}"
            }
          ]
        }
      }
    ]
  },
  "DefaultCacheBehavior": {
    "TargetOriginId": "alb-origin",
    "ViewerProtocolPolicy": "redirect-to-https",
    "AllowedMethods": {
      "Quantity": 7,
      "Items": ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"],
      "CachedMethods": { "Quantity": 2, "Items": ["GET", "HEAD"] }
    },
    "CachePolicyId": "4135ea2d-6df8-44a3-9df3-4b5a84be39ad",
    "OriginRequestPolicyId": "b689b0a8-53d0-40ab-baf2-68738e2966ac",
    "Compress": true
  },
  "Comment": "Expense Tracker CloudFront Edge",
  "Enabled": true
}
EOF
  CF_RES=$(aws cloudfront create-distribution --distribution-config file:///tmp/cf-config.json)
  CF_DIST_ID=$(echo "$CF_RES" | grep -o '"Id": "[^"]*' | cut -d'"' -f4 | head -1)
  CF_DOMAIN=$(echo "$CF_RES" | grep -o '"DomainName": "[^"]*' | cut -d'"' -f4 | head -1)
  echo "Created CloudFront Distribution: $CF_DIST_ID ($CF_DOMAIN)"
else
  CF_DOMAIN=$(aws cloudfront get-distribution --id "$CF_DIST_ID" --query "Distribution.DomainName" --output text)
  echo "Reusing CloudFront Distribution: $CF_DOMAIN"
fi

echo "=== 8. Ensuring RDS PostgreSQL Exists ==="
RDS_STATUS=$(aws rds describe-db-instances \
  --db-instance-identifier "$RDS_IDENTIFIER" \
  --region "$AWS_REGION" \
  --query "DBInstances[0].DBInstanceStatus" \
  --output text 2>/dev/null || true)

if [ -z "$RDS_STATUS" ] || [ "$RDS_STATUS" = "None" ]; then
  ENGINE_VER=$(aws rds describe-db-engine-versions \
    --engine postgres --region "$AWS_REGION" \
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
fi

echo "Waiting for RDS instance to be ready..."
aws rds wait db-instance-available --db-instance-identifier "$RDS_IDENTIFIER" --region "$AWS_REGION"

RDS_ENDPOINT=$(aws rds describe-db-instances \
  --db-instance-identifier "$RDS_IDENTIFIER" \
  --region "$AWS_REGION" \
  --query "DBInstances[0].Endpoint.Address" --output text)

echo "=== 9. Writing Environment Output ==="
cat <<EOF > "$OUTPUT_FILE"
AWS_REGION="${AWS_REGION}"
VPC_ID="${VPC_ID}"
TASK_SUBNET_IDS="${TASK_SUBNET_IDS}"
CLUSTER_NAME="${CLUSTER_NAME}"
ECS_SG_ID="${ECS_SG_ID}"
RDS_SG_ID="${RDS_SG_ID}"
RDS_ENDPOINT="${RDS_ENDPOINT}"
DB_NAME="${DB_NAME}"
DB_USERNAME="${DB_USERNAME}"
DB_PASSWORD="${DB_PASSWORD}"
ALB_ARN="${ALB_ARN}"
ALB_DNS="${ALB_DNS}"
UI_TG_ARN="${UI_TG_ARN}"
EXPENSE_TG_ARN="${EXPENSE_TG_ARN}"
CATEGORY_TG_ARN="${CATEGORY_TG_ARN}"
REPORT_TG_ARN="${REPORT_TG_ARN}"
CF_DIST_ID="${CF_DIST_ID}"
CF_DOMAIN="${CF_DOMAIN}"
EOF

echo "============================================================"
echo "Infrastructure Setup Complete!"
echo "CloudFront Secure URL: https://${CF_DOMAIN}"
echo "============================================================"