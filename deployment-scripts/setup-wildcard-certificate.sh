#!/bin/bash
# Setup Wildcard SSL Certificate for *.goorm-ktb-015.goorm.team
# This script creates a wildcard certificate in ACM and validates it via Route53
# Usage: ./deployment-scripts/setup-wildcard-certificate.sh

set -e

source .env.deployment

echo "🔐 Setting up Wildcard SSL Certificate"
echo "=========================================="
echo ""

# 도메인 설정
BASE_DOMAIN="goorm-ktb-015.goorm.team"
WILDCARD_DOMAIN="*.${BASE_DOMAIN}"

echo "Domain: $WILDCARD_DOMAIN"
echo "Region: $AWS_REGION"
echo ""

# Route53 Hosted Zone ID 찾기
echo "Looking for Route53 Hosted Zone..."
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones \
    --query "HostedZones[?Name=='${BASE_DOMAIN}.'].Id" \
    --output text 2>/dev/null | cut -d'/' -f3)

if [ -z "$HOSTED_ZONE_ID" ]; then
    echo "❌ Route53 Hosted Zone not found for ${BASE_DOMAIN}"
    echo ""
    echo "Please create a hosted zone first:"
    echo "  Route53 → Hosted zones → Create hosted zone"
    echo "  Domain name: ${BASE_DOMAIN}"
    exit 1
fi

echo "✅ Found Hosted Zone: $HOSTED_ZONE_ID"
echo ""

# 기존 와일드카드 인증서 확인
echo "Checking for existing wildcard certificate..."
EXISTING_CERT=$(aws acm list-certificates \
    --region $AWS_REGION \
    --query "CertificateSummaryList[?DomainName=='${WILDCARD_DOMAIN}'].CertificateArn" \
    --output text 2>/dev/null)

if [ -n "$EXISTING_CERT" ]; then
    CERT_STATUS=$(aws acm describe-certificate \
        --certificate-arn $EXISTING_CERT \
        --region $AWS_REGION \
        --query 'Certificate.Status' \
        --output text)
    
    echo "⚠️  Wildcard certificate already exists:"
    echo "   ARN: $EXISTING_CERT"
    echo "   Status: $CERT_STATUS"
    echo ""
    
    if [ "$CERT_STATUS" == "ISSUED" ]; then
        echo "✅ Certificate is already issued and ready to use!"
        echo ""
        echo "Certificate ARN: $EXISTING_CERT"
        echo ""
        echo "Next step: Update ALB listener with this certificate"
        echo "  ./deployment-scripts/update-alb-certificate.sh $EXISTING_CERT"
        exit 0
    fi
fi

# 새 인증서 요청
echo "Requesting new wildcard certificate..."
CERT_ARN=$(aws acm request-certificate \
    --domain-name "$WILDCARD_DOMAIN" \
    --validation-method DNS \
    --subject-alternative-names "$BASE_DOMAIN" \
    --region $AWS_REGION \
    --query 'CertificateArn' \
    --output text)

echo "✅ Certificate requested: $CERT_ARN"
echo ""

# DNS 검증 레코드 정보 가져오기
echo "Waiting for DNS validation records..."
sleep 5

MAX_RETRIES=10
RETRY_COUNT=0

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    VALIDATION_RECORDS=$(aws acm describe-certificate \
        --certificate-arn $CERT_ARN \
        --region $AWS_REGION \
        --query 'Certificate.DomainValidationOptions[*].ResourceRecord' \
        --output json 2>/dev/null)
    
    if [ "$VALIDATION_RECORDS" != "null" ] && [ -n "$VALIDATION_RECORDS" ]; then
        break
    fi
    
    echo "  Waiting for validation records... (attempt $((RETRY_COUNT + 1))/$MAX_RETRIES)"
    sleep 3
    RETRY_COUNT=$((RETRY_COUNT + 1))
done

if [ "$VALIDATION_RECORDS" == "null" ] || [ -z "$VALIDATION_RECORDS" ]; then
    echo "❌ Failed to get DNS validation records"
    echo "Please check the certificate in AWS Console:"
    echo "  ACM → Certificates → $CERT_ARN"
    exit 1
fi

echo "✅ Got validation records"
echo ""

# DNS 검증 레코드 자동 생성
echo "Creating Route53 DNS validation records..."

# Extract validation record details
RECORD_NAME=$(echo $VALIDATION_RECORDS | jq -r '.[0].Name')
RECORD_TYPE=$(echo $VALIDATION_RECORDS | jq -r '.[0].Type')
RECORD_VALUE=$(echo $VALIDATION_RECORDS | jq -r '.[0].Value')

echo "  Name: $RECORD_NAME"
echo "  Type: $RECORD_TYPE"
echo "  Value: $RECORD_VALUE"
echo ""

# Create change batch JSON
cat > /tmp/acm-validation-change-batch.json <<EOF
{
  "Changes": [{
    "Action": "UPSERT",
    "ResourceRecordSet": {
      "Name": "$RECORD_NAME",
      "Type": "$RECORD_TYPE",
      "TTL": 300,
      "ResourceRecords": [{"Value": "$RECORD_VALUE"}]
    }
  }]
}
EOF

# Apply DNS changes
aws route53 change-resource-record-sets \
    --hosted-zone-id $HOSTED_ZONE_ID \
    --change-batch file:///tmp/acm-validation-change-batch.json \
    > /dev/null

rm -f /tmp/acm-validation-change-batch.json

echo "✅ DNS validation records created"
echo ""

# 인증서 발급 대기
echo "⏳ Waiting for certificate validation and issuance..."
echo "   This may take 5-30 minutes..."
echo ""

WAIT_TIME=0
MAX_WAIT=1800  # 30 minutes

while [ $WAIT_TIME -lt $MAX_WAIT ]; do
    CERT_STATUS=$(aws acm describe-certificate \
        --certificate-arn $CERT_ARN \
        --region $AWS_REGION \
        --query 'Certificate.Status' \
        --output text)
    
    if [ "$CERT_STATUS" == "ISSUED" ]; then
        echo ""
        echo "✅ Certificate issued successfully!"
        break
    elif [ "$CERT_STATUS" == "FAILED" ]; then
        echo ""
        echo "❌ Certificate validation failed"
        aws acm describe-certificate \
            --certificate-arn $CERT_ARN \
            --region $AWS_REGION \
            --query 'Certificate.FailureReason'
        exit 1
    fi
    
    # Show progress every 30 seconds
    if [ $((WAIT_TIME % 30)) -eq 0 ]; then
        echo "  Status: $CERT_STATUS (${WAIT_TIME}s elapsed)"
    fi
    
    sleep 10
    WAIT_TIME=$((WAIT_TIME + 10))
done

if [ "$CERT_STATUS" != "ISSUED" ]; then
    echo ""
    echo "⏰ Certificate validation is taking longer than expected"
    echo "   Current status: $CERT_STATUS"
    echo ""
    echo "You can check the status manually:"
    echo "  aws acm describe-certificate --certificate-arn $CERT_ARN --region $AWS_REGION"
    echo ""
    echo "Once issued, run:"
    echo "  ./deployment-scripts/update-alb-certificate.sh $CERT_ARN"
    exit 0
fi

echo ""
echo "=========================================="
echo "✅ Wildcard Certificate Setup Complete!"
echo "=========================================="
echo ""
echo "Certificate ARN: $CERT_ARN"
echo "Domains covered:"
echo "  - *.goorm-ktb-015.goorm.team"
echo "  - goorm-ktb-015.goorm.team"
echo ""
echo "This certificate can be used for:"
echo "  - chat.goorm-ktb-015.goorm.team (frontend)"
echo "  - api.chat.goorm-ktb-015.goorm.team (backend API)"
echo "  - Any other subdomain"
echo ""
echo "Next step: Update ALB listener with this certificate"
echo "  ./deployment-scripts/update-alb-certificate.sh $CERT_ARN"
echo ""
