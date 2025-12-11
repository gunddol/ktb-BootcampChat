#!/bin/bash
# 배포 상태 확인 스크립트
# 사용법: ./deployment-scripts/99-check-deployment.sh

set -e

source .env.deployment

echo "🔍 Deployment Status Check"
echo "========================================"
echo ""

# 색상 정의
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 1. VPC & Subnets
echo "📡 1. Network Infrastructure"
echo "----------------------------"

if [ -n "$VPC_ID" ]; then
    VPC_STATE=$(aws ec2 describe-vpcs --vpc-ids $VPC_ID --query 'Vpcs[0].State' --output text 2>/dev/null || echo "not found")
    if [ "$VPC_STATE" == "available" ]; then
        echo -e "VPC: ${GREEN}✓${NC} $VPC_ID"
    else
        echo -e "VPC: ${RED}✗${NC} $VPC_ID ($VPC_STATE)"
    fi
else
    echo -e "VPC: ${YELLOW}⚠${NC} Not configured"
fi

if [ -n "$SUBNET_PUBLIC_2A_ID" ]; then
    echo -e "Subnet 2A: ${GREEN}✓${NC} $SUBNET_PUBLIC_2A_ID"
fi

if [ -n "$SUBNET_PUBLIC_2C_ID" ]; then
    echo -e "Subnet 2C: ${GREEN}✓${NC} $SUBNET_PUBLIC_2C_ID"
fi

echo ""

# 2. Security Groups
echo "🔐 2. Security Groups"
echo "----------------------------"

for sg in BACKEND_SG_ID DATABASE_SG_ID ALB_SG_ID; do
    sg_value="${!sg}"
    if [ -n "$sg_value" ]; then
        sg_name=$(aws ec2 describe-security-groups --group-ids $sg_value --query 'SecurityGroups[0].GroupName' --output text 2>/dev/null || echo "not found")
        if [ "$sg_name" != "not found" ]; then
            echo -e "$sg: ${GREEN}✓${NC} $sg_value ($sg_name)"
        else
            echo -e "$sg: ${RED}✗${NC} $sg_value"
        fi
    fi
done

echo ""

# 3. Database Instances
echo "🗄️  3. Database Instances"
echo "----------------------------"

# MongoDB
MONGODB_COUNT=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=ktb-mongodb-*" "Name=instance-state-name,Values=running" \
    --query 'length(Reservations[].Instances[])' \
    --output text 2>/dev/null || echo 0)

if [ "$MONGODB_COUNT" -ge 2 ]; then
    echo -e "MongoDB: ${GREEN}✓${NC} $MONGODB_COUNT instances running"
else
    echo -e "MongoDB: ${YELLOW}⚠${NC} $MONGODB_COUNT instances (expected: 2)"
fi

# Redis
REDIS_COUNT=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=redis-*" "Name=instance-state-name,Values=running" \
    --query 'length(Reservations[].Instances[])' \
    --output text 2>/dev/null || echo 0)

if [ "$REDIS_COUNT" -ge 3 ]; then
    echo -e "Redis: ${GREEN}✓${NC} $REDIS_COUNT instances running"
else
    echo -e "Redis: ${YELLOW}⚠${NC} $REDIS_COUNT instances (expected: 3)"
fi

echo ""

# 4. Backend Instances
echo "⚙️  4. Backend Instances"
echo "----------------------------"

BACKEND_COUNT=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=ktb-backend-*" "Name=instance-state-name,Values=running" \
    --query 'length(Reservations[].Instances[])' \
    --output text 2>/dev/null || echo 0)

if [ "$BACKEND_COUNT" -ge 12 ]; then
    echo -e "Backend: ${GREEN}✓${NC} $BACKEND_COUNT instances running"
else
    echo -e "Backend: ${RED}✗${NC} $BACKEND_COUNT instances (expected: 12)"
fi

echo ""

# 5. Target Group
echo "🎯 5. Target Group"
echo "----------------------------"

TG_ARN=$(aws elbv2 describe-target-groups \
    --names ktb-backend-tg \
    --query 'TargetGroups[0].TargetGroupArn' \
    --output text 2>/dev/null || echo "not found")

if [ "$TG_ARN" != "not found" ]; then
    HEALTHY_COUNT=$(aws elbv2 describe-target-health \
        --target-group-arn $TG_ARN \
        --query 'length(TargetHealthDescriptions[?TargetHealth.State==`healthy`])' \
        --output text 2>/dev/null || echo 0)
    
    TOTAL_COUNT=$(aws elbv2 describe-target-health \
        --target-group-arn $TG_ARN \
        --query 'length(TargetHealthDescriptions)' \
        --output text 2>/dev/null || echo 0)
    
    if [ "$HEALTHY_COUNT" -eq "$TOTAL_COUNT" ] && [ "$TOTAL_COUNT" -gt 0 ]; then
        echo -e "Target Group: ${GREEN}✓${NC} $HEALTHY_COUNT/$TOTAL_COUNT healthy"
    else
        echo -e "Target Group: ${YELLOW}⚠${NC} $HEALTHY_COUNT/$TOTAL_COUNT healthy"
    fi
else
    echo -e "Target Group: ${RED}✗${NC} Not found"
fi

echo ""

# 6. Load Balancer
echo "⚖️  6. Application Load Balancer"
echo "----------------------------"

ALB_DNS=$(aws elbv2 describe-load-balancers \
    --names ktb-production-alb \
    --query 'LoadBalancers[0].DNSName' \
    --output text 2>/dev/null || echo "not found")

if [ "$ALB_DNS" != "not found" ]; then
    ALB_STATE=$(aws elbv2 describe-load-balancers \
        --names ktb-production-alb \
        --query 'LoadBalancers[0].State.Code' \
        --output text 2>/dev/null)
    
    if [ "$ALB_STATE" == "active" ]; then
        echo -e "ALB: ${GREEN}✓${NC} $ALB_DNS"
        
        # Health check
        HEALTH_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" http://$ALB_DNS/api/health || echo "000")
        if [ "$HEALTH_RESPONSE" == "200" ]; then
            echo -e "Health Check: ${GREEN}✓${NC} /api/health responding"
        else
            echo -e "Health Check: ${YELLOW}⚠${NC} HTTP $HEALTH_RESPONSE"
        fi
    else
        echo -e "ALB: ${YELLOW}⚠${NC} $ALB_DNS ($ALB_STATE)"
    fi
else
    echo -e "ALB: ${RED}✗${NC} Not found"
fi

echo ""

# 7. Frontend
echo "🎨 7. Frontend (S3 + CloudFront)"
echo "----------------------------"

BUCKET_NAME="${BUCKET_NAME:-chat.goorm-ktb-015.goorm.team}"
BUCKET_EXISTS=$(aws s3 ls s3://$BUCKET_NAME 2>&1 || true)

if [[ $BUCKET_EXISTS != *"NoSuchBucket"* ]] && [[ $BUCKET_EXISTS != *"does not exist"* ]]; then
    FILE_COUNT=$(aws s3 ls s3://$BUCKET_NAME/ --recursive | wc -l)
    echo -e "S3 Bucket: ${GREEN}✓${NC} $BUCKET_NAME ($FILE_COUNT files)"
else
    echo -e "S3 Bucket: ${RED}✗${NC} Not found"
fi

# CloudFront
CF_COUNT=$(aws cloudfront list-distributions \
    --query 'length(DistributionList.Items)' \
    --output text 2>/dev/null || echo 0)

if [ "$CF_COUNT" -gt 0 ]; then
    echo -e "CloudFront: ${GREEN}✓${NC} $CF_COUNT distribution(s)"
else
    echo -e "CloudFront: ${YELLOW}⚠${NC} No distributions"
fi

echo ""

# 8. DNS
echo "🌐 8. DNS (Route 53)"
echo "----------------------------"

# Frontend DNS
FRONTEND_DNS=$(dig +short $DOMAIN 2>/dev/null | head -1 || echo "")
if [ -n "$FRONTEND_DNS" ]; then
    echo -e "chat.$DOMAIN: ${GREEN}✓${NC} $FRONTEND_DNS"
else
    echo -e "chat.$DOMAIN: ${YELLOW}⚠${NC} Not resolved"
fi

# Backend DNS
BACKEND_DNS=$(dig +short api.$DOMAIN 2>/dev/null | head -1 || echo "")
if [ -n "$BACKEND_DNS" ]; then
    echo -e "api.$DOMAIN: ${GREEN}✓${NC} $BACKEND_DNS"
else
    echo -e "api.$DOMAIN: ${YELLOW}⚠${NC} Not resolved"
fi

echo ""
echo "========================================"
echo ""

# 총 인스턴스 수
TOTAL_INSTANCES=$((MONGODB_COUNT + REDIS_COUNT + BACKEND_COUNT))
echo "📊 Summary:"
echo "  Total Instances: $TOTAL_INSTANCES"
echo "    - MongoDB: $MONGODB_COUNT"
echo "    - Redis: $REDIS_COUNT"
echo "    - Backend: $BACKEND_COUNT"
echo ""

# 다음 단계 제안
echo "📝 Next Steps:"
if [ "$ALB_DNS" == "not found" ]; then
    echo "  → Create ALB (see: final_deployment_steps.md Step 1)"
elif [ "$BUCKET_EXISTS" == *"NoSuchBucket"* ]; then
    echo "  → Deploy Frontend (run: ./deployment-scripts/05-deploy-frontend.sh)"
elif [ -z "$FRONTEND_DNS" ]; then
    echo "  → Configure Route 53 DNS (see: final_deployment_steps.md Step 3)"
else
    echo "  → Test full deployment:"
    echo "    curl http://api.$DOMAIN/api/health  # or with SSL: curl -k https://api.$DOMAIN/api/health"
    echo "    open https://chat.$DOMAIN"
fi
