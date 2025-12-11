#!/bin/bash
# Frontend 로컬 배포 스크립트
# 사용법: ./deployment-scripts/05-deploy-frontend.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FRONTEND_DIR="$PROJECT_ROOT/apps/frontend"

echo "🎨 Frontend Local Deployment"
echo ""

# .env.deployment 파일 로드
if [ -f "$PROJECT_ROOT/.env.deployment" ]; then
    echo "📋 Loading .env.deployment..."
    source "$PROJECT_ROOT/.env.deployment"
else
    echo "⚠️  .env.deployment not found, using defaults"
fi

# 환경 변수 설정
export AWS_REGION="${AWS_REGION:-ap-northeast-2}"
export S3_BUCKET_NAME="${S3_BUCKET_NAME:-chat.goorm-ktb-015.goorm.team}"
export CLOUDFRONT_DISTRIBUTION_ID="${CLOUDFRONT_DISTRIBUTION_ID:-E2E73NUEYWCXNJ}"

# 도메인 기반 URL 설정
DOMAIN="${DOMAIN:-chat.goorm-ktb-015.goorm.team}"
export NEXT_PUBLIC_SITE_URL="https://$DOMAIN"
export NEXT_PUBLIC_API_URL="https://api.$DOMAIN"
export NEXT_PUBLIC_SOCKET_URL="https://api.$DOMAIN"
export PRODUCTION_URL="https://$DOMAIN"

# 프론트엔드 디렉토리로 이동
cd "$FRONTEND_DIR"

# 의존성 설치 확인
if [ ! -d "node_modules" ]; then
    echo "📦 Installing dependencies..."
    npm install
fi

# 공통 배포 스크립트 실행
source "$SCRIPT_DIR/deploy-frontend-common.sh"

echo ""
echo "💡 Next steps (if first time):"
echo "  1. Verify CloudFront distribution is configured"
echo "  2. Check Route 53 DNS settings"
echo "  3. Test: open https://$DOMAIN"
echo ""
