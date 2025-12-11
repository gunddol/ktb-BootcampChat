#!/bin/bash
# ALB에 Socket.IO용 경로 기반 라우팅 설정
# 사용법: ./deployment-scripts/setup-alb-socketio-routing.sh

set -e

source .env.deployment

echo "🔧 Setting up ALB Path-Based Routing for Socket.IO"
echo "=========================================="
echo ""

# ALB ARN 가져오기
ALB_NAME="ktb-production-alb"
echo "Looking for ALB: $ALB_NAME"

ALB_ARN=$(aws elbv2 describe-load-balancers \
    --names $ALB_NAME \
    --region $AWS_REGION \
    --query 'LoadBalancers[0].LoadBalancerArn' \
    --output text 2>/dev/null)

if [ "$ALB_ARN" == "None" ] || [ -z "$ALB_ARN" ]; then
    echo "❌ ALB not found: $ALB_NAME"
    exit 1
fi

echo "✅ Found ALB: $ALB_ARN"
echo ""

# VPC ID 가져오기
VPC_ID=$(aws elbv2 describe-load-balancers \
    --load-balancer-arns $ALB_ARN \
    --region $AWS_REGION \
    --query 'LoadBalancers[0].VpcId' \
    --output text)

echo "VPC ID: $VPC_ID"
echo ""

# Socket.IO용 Target Group 생성 (5002 포트)
TG_NAME_WS="ktb-socketio-tg"

echo "Checking if Socket.IO Target Group exists..."
TG_WS_ARN=$(aws elbv2 describe-target-groups \
    --region $AWS_REGION \
    --query "TargetGroups[?TargetGroupName=='${TG_NAME_WS}'].TargetGroupArn" \
    --output text 2>/dev/null)

if [ -z "$TG_WS_ARN" ] || [ "$TG_WS_ARN" == "None" ]; then
    echo "Creating Socket.IO Target Group..."
    TG_WS_ARN=$(aws elbv2 create-target-group \
        --name $TG_NAME_WS \
        --protocol HTTP \
        --port 5002 \
        --vpc-id $VPC_ID \
        --target-type instance \
        --health-check-enabled \
        --health-check-protocol HTTP \
        --health-check-path /api/health \
        --health-check-port 5001 \
        --health-check-interval-seconds 30 \
        --health-check-timeout-seconds 5 \
        --healthy-threshold-count 2 \
        --unhealthy-threshold-count 3 \
        --region $AWS_REGION \
        --query 'TargetGroups[0].TargetGroupArn' \
        --output text)
    
    echo "✅ Created Target Group: $TG_WS_ARN"
else
    echo "✅ Target Group already exists: $TG_WS_ARN"
fi

echo ""

# Backend 인스턴스들을 Socket.IO Target Group에 등록
echo "Registering Backend instances to Socket.IO Target Group..."

INSTANCE_IDS=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=ktb-backend-*" \
              "Name=instance-state-name,Values=running" \
    --region $AWS_REGION \
    --query 'Reservations[].Instances[].InstanceId' \
    --output text)

if [ -z "$INSTANCE_IDS" ]; then
    echo "❌ No Backend instances found!"
    exit 1
fi

INSTANCE_ARRAY=($INSTANCE_IDS)
echo "Found ${#INSTANCE_ARRAY[@]} instances"

TARGETS=""
for instance_id in ${INSTANCE_ARRAY[@]}; do
    if [ -z "$TARGETS" ]; then
        TARGETS="Id=$instance_id,Port=5002"
    else
        TARGETS="$TARGETS Id=$instance_id,Port=5002"
    fi
done

aws elbv2 register-targets \
    --target-group-arn $TG_WS_ARN \
    --targets $TARGETS \
    --region $AWS_REGION

echo "✅ Registered ${#INSTANCE_ARRAY[@]} instances to Socket.IO Target Group"
echo ""

# HTTPS 리스너에 경로 기반 규칙 추가
echo "Configuring ALB listener rules..."

HTTPS_LISTENER_ARN=$(aws elbv2 describe-listeners \
    --load-balancer-arn $ALB_ARN \
    --region $AWS_REGION \
    --query 'Listeners[?Protocol==`HTTPS`&&Port==`443`].ListenerArn' \
    --output text)

if [ -z "$HTTPS_LISTENER_ARN" ]; then
    echo "❌ HTTPS listener not found"
    exit 1
fi

echo "HTTPS Listener: $HTTPS_LISTENER_ARN"

# Socket.IO 경로 규칙 추가 (/socket.io/* → Socket.IO Target Group)
echo "Adding path-based routing rule for /socket.io/*..."

# 기존 규칙 확인
EXISTING_RULE=$(aws elbv2 describe-rules \
    --listener-arn $HTTPS_LISTENER_ARN \
    --region $AWS_REGION \
    --query "Rules[?Conditions[?Field=='path-pattern'&&Values[?contains(@, '/socket.io/*')]]].RuleArn" \
    --output text 2>/dev/null)

if [ -n "$EXISTING_RULE" ] && [ "$EXISTING_RULE" != "None" ]; then
    echo "⚠️  Socket.IO routing rule already exists: $EXISTING_RULE"
    echo "Modifying existing rule..."
    
    aws elbv2 modify-rule \
        --rule-arn $EXISTING_RULE \
        --actions Type=forward,TargetGroupArn=$TG_WS_ARN \
        --region $AWS_REGION \
        > /dev/null
    
    echo "✅ Updated existing rule"
else
    # 새 규칙 추가 (우선순위: 10)
    aws elbv2 create-rule \
        --listener-arn $HTTPS_LISTENER_ARN \
        --priority 10 \
        --conditions Field=path-pattern,Values='/socket.io/*' \
        --actions Type=forward,TargetGroupArn=$TG_WS_ARN \
        --region $AWS_REGION \
        > /dev/null
    
    echo "✅ Created new routing rule (priority: 10)"
fi

echo ""
echo "=========================================="
echo "✅ ALB Path-Based Routing Setup Complete!"
echo "=========================================="
echo ""
echo "Configuration:"
echo "  REST API (5001): Default → ktb-backend-tg"
echo "  Socket.IO (5002): /socket.io/* → ktb-socketio-tg"
echo ""
echo "Wait 30 seconds for health checks, then test:"
echo "  https://api.chat.goorm-ktb-015.goorm.team/api/health (REST API)"
echo "  wss://api.chat.goorm-ktb-015.goorm.team/socket.io/ (Socket.IO)"
echo ""
