#!/bin/bash
# 단일 Backend 인스턴스 수정 스크립트
# 사용법: ./fix-one-backend.sh <BACKEND_IP>

BACKEND_IP=$1
BASTION_IP="52.79.105.90"
KEY_PATH="$HOME/.ssh/ktb-015-key.pem"

if [ -z "$BACKEND_IP" ]; then
    echo "Usage: $0 <BACKEND_IP>"
    echo ""
    echo "Available Backend IPs:"
    aws ec2 describe-instances \
        --filters "Name=tag:Type,Values=backend" "Name=instance-state-name,Values=running" \
        --region ap-northeast-2 \
        --query 'Reservations[].Instances[].[Tags[?Key==`Name`].Value|[0],PrivateIpAddress]' \
        --output table
    exit 1
fi

echo "🔧 Fixing Backend: $BACKEND_IP"
echo "Using Bastion: $BASTION_IP"
echo ""

# 먼저 Bastion에 키 복사
echo "📤 Ensuring SSH key is on bastion..."
scp -i "$KEY_PATH" -o StrictHostKeyChecking=no "$KEY_PATH" ubuntu@${BASTION_IP}:~/.ssh/id_rsa 2>/dev/null
ssh -i "$KEY_PATH" -o StrictHostKeyChecking=no ubuntu@${BASTION_IP} "chmod 600 ~/.ssh/id_rsa" 2>/dev/null

echo "✅ Ready"
echo ""

# Bastion을 통해 Backend에서 명령 실행
echo "🔗 Connecting via bastion..."
ssh -i "$KEY_PATH" -o StrictHostKeyChecking=no ubuntu@${BASTION_IP} bash << ENDSSH
echo "On bastion, connecting to Backend $BACKEND_IP..."

# Test connection first
echo "Testing SSH connection..."
timeout 10 ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 ubuntu@$BACKEND_IP "echo 'Connection OK'" || {
    echo "❌ Cannot connect to $BACKEND_IP"
    exit 1
}

echo "✅ Connection successful"
echo ""

# Now run the actual commands
ssh -o StrictHostKeyChecking=no ubuntu@$BACKEND_IP bash << 'ENDBACKEND'
set -e

echo "=== Installing Redis locally ==="
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y redis-server

echo ""
echo "=== Configuring Redis ==="
sudo sed -i 's/^bind .*/bind 127.0.0.1/' /etc/redis/redis.conf
sudo grep -q "^requirepass" /etc/redis/redis.conf || echo "requirepass ktb-015" | sudo tee -a /etc/redis/redis.conf > /dev/null

echo ""
echo "=== Starting Redis ==="
sudo systemctl enable redis-server
sudo systemctl restart redis-server
sleep 2

echo ""
echo "=== Updating Backend .env ==="
cd /opt/ktb-backend/ktb-BootcampChat/apps/backend

[ -f .env ] && sudo cp .env .env.backup

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

echo ""
echo "=== Restarting ktb-backend service ==="
sudo systemctl restart ktb-backend
sleep 10

echo ""
echo "=== Service Status ==="
sudo systemctl --no-pager status ktb-backend || true

echo ""
echo "=== Health Check ==="
curl -s http://localhost:5001/api/health || echo "Health check failed"

ENDBACKEND

ENDSSH

echo ""
echo "✅ Completed processing $BACKEND_IP"
