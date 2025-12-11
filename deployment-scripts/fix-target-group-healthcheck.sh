#!/bin/bash
# Fix Target Group Health Check Protocol
# SSL 인증서 오류를 해결하기 위해 Target Group의 health check 프로토콜을 HTTPS에서 HTTP로 변경
# 사용법: ./deployment-scripts/fix-target-group-healthcheck.sh

set -e

source .env.deployment

echo "🔧 Fixing Target Group Health Check Protocol"
echo "=========================================="
echo ""

# Target Group 이름
TG_NAME="ktb-backend-tg"

# Target Group ARN 찾기
echo "Looking for Target Group: $TG_NAME"
TG_ARN=$(aws elbv2 describe-target-groups \
    --names $TG_NAME \
    --region $AWS_REGION \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text 2>/dev/null)

if [ "$TG_ARN" == "None" ] || [ -z "$TG_ARN" ]; then
    echo "❌ Target Group '$TG_NAME' not found!"
    echo ""
    echo "Please create Target Group first via AWS Console:"
    echo "  EC2 → Target Groups → Create target group"
    echo "  Name: $TG_NAME"
    echo "  Protocol: HTTP, Port: 5001"
    echo "  Health check: /api/health"
    exit 1
fi

echo "✅ Found Target Group: $TG_ARN"
echo ""

# 현재 Health Check 설정 확인
echo "Current Health Check Settings:"
aws elbv2 describe-target-groups \
    --target-group-arns $TG_ARN \
    --region $AWS_REGION \
    --query 'TargetGroups[0].[HealthCheckProtocol,HealthCheckPath,HealthCheckPort]' \
    --output table

echo ""

# Health Check 프로토콜을 HTTP로 변경
echo "Updating Health Check Protocol to HTTP..."
aws elbv2 modify-target-group \
    --target-group-arn $TG_ARN \
    --region $AWS_REGION \
    --health-check-protocol HTTP \
    --health-check-path /api/health \
    --health-check-port 5001 \
    --health-check-interval-seconds 30 \
    --health-check-timeout-seconds 5 \
    --healthy-threshold-count 2 \
    --unhealthy-threshold-count 3

echo "✅ Health Check Protocol updated to HTTP"
echo ""

# 업데이트된 설정 확인
echo "Updated Health Check Settings:"
aws elbv2 describe-target-groups \
    --target-group-arns $TG_ARN \
    --region $AWS_REGION \
    --query 'TargetGroups[0].[HealthCheckProtocol,HealthCheckPath,HealthCheckPort,HealthCheckIntervalSeconds,HealthCheckTimeoutSeconds,HealthyThresholdCount,UnhealthyThresholdCount]' \
    --output table

echo ""
echo "=========================================="
echo "✅ Target Group Health Check Fix Complete!"
echo ""
echo "이제 health check가 HTTP 프로토콜을 사용합니다."
echo "SSL 인증서 오류 없이 정상적으로 health check가 수행됩니다."
echo ""
echo "Target 상태 확인:"
echo "  aws elbv2 describe-target-health --target-group-arn $TG_ARN"
echo ""
