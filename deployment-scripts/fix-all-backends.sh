#!/bin/bash
# Fix all Backend instances - update MongoDB URI and restart services

BASTION_IP="52.79.105.90"
KEY_PATH="$HOME/.ssh/ktb-015-key.pem"
REGION="ap-northeast-2"

echo "🔧 Fixing all Backend instances..."
echo ""

# Get all Backend instance IPs
BACKEND_IPS=$(aws ec2 describe-instances \
    --filters "Name=tag:Type,Values=backend" "Name=instance-state-name,Values=running" \
    --region $REGION \
    --query 'Reservations[].Instances[].PrivateIpAddress' \
    --output text)

echo "Found Backend instances:"
echo "$BACKEND_IPS" | tr '\t' '\n'
echo ""

SUCCESS_COUNT=0
FAIL_COUNT=0

for IP in $BACKEND_IPS; do
    echo "=========================================="
    echo "🔄 Processing: $IP"
    echo "=========================================="
    
    ssh -i "$KEY_PATH" -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@${BASTION_IP} << OUTER
ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 ubuntu@$IP << 'INNER'
cd /opt/ktb-backend/ktb-BootcampChat/apps/backend

# Update .env file
sudo tee .env > /dev/null << 'ENVEOF'
MONGO_URI=mongodb://10.0.101.160:27017/ktb-chat
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=ktb-015
JWT_SECRET=78ba3b45fa8b7a3c50e34acbcd887f76ca387034712e152b7bb20bd82841067a
ENCRYPTION_KEY=7132063e4cae50af2b8b834e417de700985d82c081c072a91a8c96692fb61f625ec487c6e9d54d61507115db8d61a0e18e90647739fc6c69a56e3a63ef821fe8
ENCRYPTION_SALT=c6e78f35b4414a26e69142befdd7561ae14bccd8e31b50aafedd2d834eeeb061
PORT=5001
WS_PORT=5002
SPRING_PROFILES_ACTIVE=prod
ENVEOF

sudo chown ubuntu:ubuntu .env

# Restart service
sudo systemctl restart ktb-backend
sleep 15

# Check status
if sudo systemctl is-active ktb-backend > /dev/null 2>&1; then
    echo "✅ Service is running"
    # Test health
    if curl -s -f http://localhost:5001/api/health > /dev/null 2>&1; then
        echo "✅ Health check passed"
        exit 0
    else
        echo "⚠️  Service running but health check not ready yet"
        exit 0
    fi
else
    echo "❌ Service failed to start"
    exit 1
fi
INNER
OUTER

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

echo "=========================================="
echo "📊 Summary"
echo "=========================================="
echo "✅ Success: $SUCCESS_COUNT"
echo "❌ Failed: $FAIL_COUNT"
echo ""

if [ $SUCCESS_COUNT -gt 0 ]; then
    echo "⏳ Waiting 30 seconds for all services to fully start..."
    sleep 30
    
    echo ""
    echo "📊 Checking ALB Target Health..."
    aws elbv2 describe-target-health \
        --target-group-arn arn:aws:elasticloadbalancing:ap-northeast-2:613482338543:targetgroup/ktb-backend-tg/11e1ba2e4e456aeb \
        --region $REGION \
        --query 'TargetHealthDescriptions[*].[Target.Id,TargetHealth.State,TargetHealth.Reason]' \
        --output table
fi

echo ""
echo "🎉 Done!"
