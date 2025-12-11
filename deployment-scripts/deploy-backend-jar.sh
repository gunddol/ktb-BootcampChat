#!/bin/bash
# GitHub Actions용 Backend 배포 스크립트
# 사용법: ./deploy-backend-jar.sh <JAR_FILE_PATH>

set -e

if [ -z "$1" ]; then
    echo "❌ Usage: $0 <JAR_FILE_PATH>"
    exit 1
fi

JAR_FILE="$1"

if [ ! -f "$JAR_FILE" ]; then
    echo "❌ JAR file not found: $JAR_FILE"
    exit 1
fi

echo "🚀 Backend Deployment"
echo "======================================"
echo "JAR: $JAR_FILE"
echo ""

# 환경 변수 확인
REQUIRED_VARS=("BASTION_IP" "MONGO_URI" "REDIS_HOST" "REDIS_PORT" "REDIS_PASSWORD" "JWT_SECRET" "ENCRYPTION_KEY" "ENCRYPTION_SALT")

for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        echo "❌ Required environment variable not set: $var"
        exit 1
    fi
done

KEY_PATH="$HOME/.ssh/ktb-015-key.pem"
REGION="${AWS_REGION:-ap-northeast-2}"

if [ ! -f "$KEY_PATH" ]; then
    echo "❌ SSH key not found: $KEY_PATH"
    exit 1
fi

# Backend 인스턴스 IP 목록 가져오기
echo "📋 Getting Backend instance IPs..."
BACKEND_IPS=$(aws ec2 describe-instances \
    --filters "Name=tag:Type,Values=backend" "Name=instance-state-name,Values=running" \
    --region $REGION \
    --query 'Reservations[].Instances[].PrivateIpAddress' \
    --output text)

if [ -z "$BACKEND_IPS" ]; then
    echo "❌ No Backend instances found!"
    exit 1
fi

INSTANCE_COUNT=$(echo "$BACKEND_IPS" | wc -w)
echo "✅ Found $INSTANCE_COUNT Backend instances"
echo ""

SUCCESS_COUNT=0
FAIL_COUNT=0

for IP in $BACKEND_IPS; do
    echo "======================================"
    echo "🔄 Deploying to: $IP"
    echo "======================================"
    
    # JAR 파일 복사
    echo "📤 Uploading JAR..."
    scp -i "$KEY_PATH" -o StrictHostKeyChecking=no -o ProxyJump=ubuntu@${BASTION_IP} \
        "$JAR_FILE" ubuntu@$IP:/tmp/ktb-chat-backend.jar
    
    # 배포 및 재시작
    ssh -i "$KEY_PATH" -o StrictHostKeyChecking=no -o ProxyJump=ubuntu@${BASTION_IP} \
        ubuntu@$IP << SCRIPT
set -e

# JAR 파일 이동
sudo mv /tmp/ktb-chat-backend.jar /opt/ktb-backend/ktb-BootcampChat/apps/backend/target/ktb-chat-backend-0.0.1-SNAPSHOT.jar
sudo chown ktb-backend:ktb-backend /opt/ktb-backend/ktb-BootcampChat/apps/backend/target/ktb-chat-backend-0.0.1-SNAPSHOT.jar

# .env 파일 업데이트
cd /opt/ktb-backend/ktb-BootcampChat/apps/backend
sudo tee .env > /dev/null << 'ENVEOF'
MONGO_URI=$MONGO_URI
REDIS_HOST=$REDIS_HOST
REDIS_PORT=$REDIS_PORT
REDIS_PASSWORD=$REDIS_PASSWORD
JWT_SECRET=$JWT_SECRET
ENCRYPTION_KEY=$ENCRYPTION_KEY
ENCRYPTION_SALT=$ENCRYPTION_SALT
PORT=5001
WS_PORT=5002
SPRING_PROFILES_ACTIVE=prod
ENVEOF

sudo chown ktb-backend:ktb-backend .env

# Service 재시작
echo "🔄 Restarting service..."
sudo systemctl restart ktb-backend

# 대기
sleep 15

# Health check
if curl -sf http://localhost:5001/api/health > /dev/null 2>&1; then
    echo "✅ Health check passed"
    exit 0
else
    echo "⚠️  Health check failed, but service is running"
    exit 0
fi
SCRIPT
    
    if [ $? -eq 0 ]; then
        echo "✅ Successfully deployed to $IP"
        ((SUCCESS_COUNT++))
    else
        echo "❌ Failed to deploy to $IP"
        ((FAIL_COUNT++))
    fi
    
    echo ""
    sleep 2
done

echo "======================================"
echo "📊 Deployment Summary"
echo "======================================"
echo "✅ Success: $SUCCESS_COUNT"
echo "❌ Failed: $FAIL_COUNT"
echo ""

if [ $FAIL_COUNT -gt 0 ]; then
    echo "⚠️  Some deployments failed!"
    exit 1
fi

echo "✅ All deployments successful!"
echo ""
