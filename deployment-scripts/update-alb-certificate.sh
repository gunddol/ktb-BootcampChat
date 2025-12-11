#!/bin/bash
# Update ALB HTTPS Listener Certificate
# This script updates the ALB HTTPS listener to use a new SSL certificate
# Usage: ./deployment-scripts/update-alb-certificate.sh [CERTIFICATE_ARN]

set -e

source .env.deployment

echo "🔄 Updating ALB HTTPS Listener Certificate"
echo "=========================================="
echo ""

# Certificate ARN (from argument or prompt)
CERT_ARN=${1:-}

if [ -z "$CERT_ARN" ]; then
    echo "Available certificates:"
    aws acm list-certificates \
        --region $AWS_REGION \
        --query 'CertificateSummaryList[].[DomainName,CertificateArn,Status]' \
        --output table
    echo ""
    read -p "Enter Certificate ARN: " CERT_ARN
fi

# Validate certificate exists and is issued
echo "Validating certificate..."
CERT_STATUS=$(aws acm describe-certificate \
    --certificate-arn $CERT_ARN \
    --region $AWS_REGION \
    --query 'Certificate.Status' \
    --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$CERT_STATUS" == "NOT_FOUND" ]; then
    echo "❌ Certificate not found: $CERT_ARN"
    exit 1
elif [ "$CERT_STATUS" != "ISSUED" ]; then
    echo "❌ Certificate status is not ISSUED: $CERT_STATUS"
    echo "Please wait for the certificate to be issued first"
    exit 1
fi

CERT_DOMAIN=$(aws acm describe-certificate \
    --certificate-arn $CERT_ARN \
    --region $AWS_REGION \
    --query 'Certificate.DomainName' \
    --output text)

echo "✅ Certificate validated"
echo "   ARN: $CERT_ARN"
echo "   Domain: $CERT_DOMAIN"
echo "   Status: $CERT_STATUS"
echo ""

# Get ALB ARN
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

# Get HTTPS Listener ARN
echo "Looking for HTTPS listener (Port 443)..."
HTTPS_LISTENER_ARN=$(aws elbv2 describe-listeners \
    --load-balancer-arn $ALB_ARN \
    --region $AWS_REGION \
    --query 'Listeners[?Protocol==`HTTPS`&&Port==`443`].ListenerArn' \
    --output text)

if [ -z "$HTTPS_LISTENER_ARN" ]; then
    echo "❌ HTTPS listener not found on port 443"
    echo ""
    echo "Please create an HTTPS listener first via AWS Console:"
    echo "  EC2 → Load Balancers → $ALB_NAME → Listeners"
    echo "  Add listener: HTTPS:443 → Forward to ktb-backend-tg"
    exit 1
fi

echo "✅ Found HTTPS listener: $HTTPS_LISTENER_ARN"
echo ""

# Show current certificate
CURRENT_CERT=$(aws elbv2 describe-listeners \
    --listener-arns $HTTPS_LISTENER_ARN \
    --region $AWS_REGION \
    --query 'Listeners[0].Certificates[0].CertificateArn' \
    --output text)

echo "Current certificate: $CURRENT_CERT"
echo "New certificate:     $CERT_ARN"
echo ""

if [ "$CURRENT_CERT" == "$CERT_ARN" ]; then
    echo "✅ Certificate is already configured on the listener"
    echo "No changes needed"
    exit 0
fi

# Update listener certificate
echo "Updating HTTPS listener certificate..."
aws elbv2 modify-listener \
    --listener-arn $HTTPS_LISTENER_ARN \
    --certificates CertificateArn=$CERT_ARN \
    --region $AWS_REGION \
    > /dev/null

echo "✅ Certificate updated on HTTPS listener"
echo ""

# Verify the update
echo "Verifying update..."
UPDATED_CERT=$(aws elbv2 describe-listeners \
    --listener-arns $HTTPS_LISTENER_ARN \
    --region $AWS_REGION \
    --query 'Listeners[0].Certificates[0].CertificateArn' \
    --output text)

if [ "$UPDATED_CERT" == "$CERT_ARN" ]; then
    echo "✅ Verification successful"
else
    echo "⚠️  Verification: Certificate ARN mismatch"
    echo "   Expected: $CERT_ARN"
    echo "   Got:      $UPDATED_CERT"
fi

echo ""
echo "=========================================="
echo "✅ ALB Certificate Update Complete!"
echo "=========================================="
echo ""
echo "ALB DNS: $(aws elbv2 describe-load-balancers --load-balancer-arns $ALB_ARN --region $AWS_REGION --query 'LoadBalancers[0].DNSName' --output text)"
echo ""
echo "Test HTTPS connections:"
echo "  curl -v https://api.chat.goorm-ktb-015.goorm.team/api/health"
echo "  curl -v https://chat.goorm-ktb-015.goorm.team"
echo ""

# Optional: Setup HTTP to HTTPS redirect
echo "Would you like to setup HTTP to HTTPS redirect? (y/n)"
read -p "> " SETUP_REDIRECT

if [[ "$SETUP_REDIRECT" =~ ^[Yy]$ ]]; then
    echo ""
    echo "Setting up HTTP to HTTPS redirect..."
    
    # Get HTTP Listener ARN
    HTTP_LISTENER_ARN=$(aws elbv2 describe-listeners \
        --load-balancer-arn $ALB_ARN \
        --region $AWS_REGION \
        --query 'Listeners[?Protocol==`HTTP`&&Port==`80`].ListenerArn' \
        --output text)
    
    if [ -z "$HTTP_LISTENER_ARN" ]; then
        echo "⚠️  HTTP listener not found on port 80"
        echo "Skipping redirect setup"
    else
        # Modify HTTP listener to redirect to HTTPS
        aws elbv2 modify-listener \
            --listener-arn $HTTP_LISTENER_ARN \
            --default-actions Type=redirect,RedirectConfig="{Protocol=HTTPS,Port=443,StatusCode=HTTP_301}" \
            --region $AWS_REGION \
            > /dev/null
        
        echo "✅ HTTP to HTTPS redirect configured"
        echo ""
        echo "Test redirect:"
        echo "  curl -I http://api.chat.goorm-ktb-015.goorm.team/api/health"
    fi
fi

echo ""
echo "Done!"
echo ""
