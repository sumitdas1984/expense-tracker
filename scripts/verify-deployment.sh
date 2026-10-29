#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="ap-south-1"
CLUSTER_NAME="expense-tracker-cluster"
RDS_IDENTIFIER="expense-tracker-db"

SERVICES=("expense-service" "category-service" "report-service" "ui-service")

echo "=== 1. Checking RDS Status ==="
RDS_STATUS=$(aws rds describe-db-instances \
  --db-instance-identifier "$RDS_IDENTIFIER" \
  --region "$AWS_REGION" \
  --query "DBInstances[0].DBInstanceStatus" \
  --output text 2>/dev/null || echo "NOT_FOUND")

echo "RDS Instance '$RDS_IDENTIFIER': $RDS_STATUS"

echo "=== 2. Checking ECS Service Counts ==="
aws ecs describe-services \
  --cluster "$CLUSTER_NAME" \
  --services "${SERVICES[@]}" \
  --region "$AWS_REGION" \
  --query 'services[*].[serviceName,runningCount,desiredCount,status]' \
  --output table

echo "=== 3. Resolving UI Service Public Endpoint ==="
UI_TASK_ARN=$(aws ecs list-tasks \
  --cluster "$CLUSTER_NAME" \
  --service-name "ui-service" \
  --desired-status RUNNING \
  --region "$AWS_REGION" \
  --query "taskArns[0]" \
  --output text)

if [ -n "$UI_TASK_ARN" ] && [ "$UI_TASK_ARN" != "None" ]; then
  ENI_ID=$(aws ecs describe-tasks \
    --cluster "$CLUSTER_NAME" \
    --tasks "$UI_TASK_ARN" \
    --region "$AWS_REGION" \
    --query "tasks[0].attachments[0].details[?name=='networkInterfaceId'].value | [0]" \
    --output text)

  UI_PUBLIC_IP=$(aws ec2 describe-network-interfaces \
    --network-interface-ids "$ENI_ID" \
    --region "$AWS_REGION" \
    --query "NetworkInterfaces[0].Association.PublicIp" \
    --output text 2>/dev/null || echo "None")

  echo "UI Task Public IP: $UI_PUBLIC_IP"
  echo "Streamlit UI URL:  http://${UI_PUBLIC_IP}:8501"
else
  echo "No running UI task found."
fi

echo "=== 4. Checking Database Connections in Service Logs ==="
for svc in "expense-service" "category-service"; do
  echo "--- Logs for $svc (last 5 lines) ---"
  MSYS_NO_PATHCONV=1 aws logs filter-log-events \
    --log-group-name "/ecs/expense-tracker" \
    --log-stream-name-prefix "$svc" \
    --limit 5 \
    --region "$AWS_REGION" \
    --query "events[*].message" \
    --output text 2>/dev/null || echo "No logs found for $svc"
done

echo "============================================================"
echo "Verification complete!"
echo "============================================================"
