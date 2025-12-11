#!/bin/bash
# Backend 인스턴스 Redis 설정 수정 및 재시작 스크립트
# Redis 없이 실행되도록 설정 변경

set -e

BASTION_IP="52.79.105.90"
KEY_PATH="$HOME/.ssh/ktb-015-key.pem"
REGION="ap-northeast-2"

echo "🔧 Fixing Backend instances to run without Redis..."
echo ""

# Backend 인스턴스 목록 가져오기
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

echo "Found Backend instances:"
echo "$BACKEND_IPS"
echo ""

# SSH 설정 확인
if [ ! -f "$KEY_PATH" ]; then
    echo "❌ SSH key not found: $KEY_PATH"
    exit 1
fi

# 먼저 Bastion(MongoDB)에 SSH 키를 복사
echo "📤 Copying SSH key to bastion..."
scp -i "$KEY_PATH" -o StrictHostKeyChecking=no "$KEY_PATH" ubuntu@${BASTION_IP}:~/.ssh/id_rsa
ssh -i "$KEY_PATH" -o StrictHostKeyChecking=no ubuntu@${BASTION_IP} "chmod 600 ~/.ssh/id_rsa"

echo "✅ SSH key copied to bastion"
echo ""

# 각 Backend 인스턴스에 대해 설정 수정
SUCCESS_COUNT=0
FAIL_COUNT=0

for IP in $BACKEND_IPS; do
    echo "----------------------------------------"
    echo "🔄 Processing Backend: $IP"
    echo "----------------------------------------"
    
    # Bastion을 통해 Backend 인스턴스에 접속하여 설정 수정
    ssh -i "$KEY_PATH" -o StrictHostKeyChecking=no ubuntu@${BASTION_IP} << ENDSSH
set -e

echo "Connecting to Backend $IP..."

# Backend 인스턴스에 접속하여 작업 수행
ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@$IP << 'ENDBACKEND'
set -e

echo "=== Current Backend Status ==="
sudo systemctl status ktb-backend --no-pager || echo "Service not running"

echo ""
echo "=== Updating .env file ==="
cd /opt/ktb-backend/ktb-BootcampChat/apps/backend

# .env 파일 백업
if [ -f .env ]; then
    sudo cp .env .env.backup
    echo "✅ Backed up .env to .env.backup"
fi

# Install and start local Redis
echo "📦 Installing Redis..."
sudo apt-get update -qq
sudo apt-get install -y redis-server

echo "🔧 Configuring Redis..."
# Redis 설정: 로컬에서만 접근 가능하도록
sudo sed -i 's/^bind .*/bind 127.0.0.1/' /etc/redis/redis.conf
# 비밀번호 설정
echo "requirepass ktb-015" | sudo tee -a /etc/redis/redis.conf > /dev/null

echo "🚀 Starting Redis..."
sudo systemctl enable redis-server
sudo systemctl restart redis-server
sudo systemctl status redis-server --no-pager

echo "✅ Redis installed and running"

echo ""
echo "=== Updating .env file to use localhost Redis ==="
cd /opt/ktb-backend/ktb-BootcampChat/apps/backend

# .env 파일에서 Redis 설정을 localhost로 변경
sudo tee .env > /dev/null << 'EOF'
MONGO_URI=mongodb://ktb-app:ktb-015@52.79.105.90:27017/ktb-chat
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=ktb-015
JWT_SECRET=78ba3b45fa8b7a3c50e34acbcd887f76ca387034712e152b7bb20bd82841067a
ENCRYPTION_KEY=7132063e4cae50af2b8b834e417de700985d82c081c072a91a8c96692fb61f625ec487c6e9d54d61507115db8d61a0e18e90647739fc6c69a56e3a63ef821fe8
ENCRYPTION_SALT=c6e78f35b4414a26e69142befdd7561ae14bccd8e31b50aafedd2d834eeeb061
PORT=5001
WS_PORT=5002
SPRING_PROFILES_ACTIVE=prod
EOF

sudo chown ubuntu:ubuntu .env
sudo chmod 600 .env

echo "✅ Updated .env file"

echo ""
echo "=== Restarting ktb-backend service ==="
sudo systemctl restart ktb-backend

echo ""
echo "⏳ Waiting for service to start (10 seconds)..."
sleep 10

echo ""
echo "=== Service Status ==="
sudo systemctl status ktb-backend --no-pager

echo ""
echo "=== Testing Health Check ==="
curl -s http://localhost:5001/api/health || echo "Health check failed"

echo ""
echo "✅ Backend $IP configured successfully"
ENDBACKEND

ENDSSH

    if [ $? -eq 0 ]; then
        echo "✅ Successfully configured $IP"
        ((SUCCESS_COUNT++))
    else
        echo "❌ Failed to configure $IP"
        ((FAIL_COUNT++))
    fi
    
    echo ""
    sleep 2
done

echo "========================================"
echo "📊 Configuration Summary"
echo "========================================"
echo "✅ Success: $SUCCESS_COUNT"
echo "❌ Failed: $FAIL_COUNT"
echo ""

if [ $SUCCESS_COUNT -gt 0 ]; then
    echo "🎉 Successfully configured $SUCCESS_COUNT Backend instances"
    echo ""
    echo "⏳ Waiting 30 seconds for all services to stabilize..."
    sleep 30
    
    echo ""
    echo "📊 Checking ALB Target Health..."
    aws elbv2 describe-target-health \
        --target-group-arn arn:aws:elasticloadbalancing:ap-northeast-2:613482338543:targetgroup/ktb-backend-tg/11e1ba2e4e456aeb \
        --region $REGION \
        --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State,TargetHealth.Reason]' \
        --output table
fi
