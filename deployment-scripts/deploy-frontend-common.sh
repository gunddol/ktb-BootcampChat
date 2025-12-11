#!/bin/bash
# 공통 Frontend 배포 스크립트
# GitHub Actions와 로컬 배포 모두에서 사용
# 사용법: ./deployment-scripts/deploy-frontend-common.sh

set -e

# 색상 코드
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# 필수 환경 변수 확인
check_required_vars() {
    local missing_vars=()
    
    [ -z "$S3_BUCKET_NAME" ] && missing_vars+=("S3_BUCKET_NAME")
    [ -z "$AWS_REGION" ] && missing_vars+=("AWS_REGION")
    [ -z "$NEXT_PUBLIC_API_URL" ] && missing_vars+=("NEXT_PUBLIC_API_URL")
    [ -z "$NEXT_PUBLIC_SOCKET_URL" ] && missing_vars+=("NEXT_PUBLIC_SOCKET_URL")
    
    if [ ${#missing_vars[@]} -ne 0 ]; then
        log_error "Required environment variables are missing:"
        for var in "${missing_vars[@]}"; do
            echo "  - $var"
        done
        exit 1
    fi
}

# Next.js config 생성
create_nextjs_config() {
    log_info "Creating next.config.js..."
    
    cat > next.config.js << 'EOF'
/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: false,
  transpilePackages: ['@vapor-ui/core', '@vapor-ui/icons'],
  output: 'export',
  images: { unoptimized: true },
  trailingSlash: true,
  compress: true,
};

module.exports = nextConfig;
EOF
    
    log_success "next.config.js created"
}

# .env.production 생성
create_env_production() {
    log_info "Creating .env.production..."
    
    cat > .env.production << EOF
NEXT_PUBLIC_SITE_URL=${NEXT_PUBLIC_SITE_URL:-https://chat.goorm-ktb-015.goorm.team}
NEXT_PUBLIC_API_URL=${NEXT_PUBLIC_API_URL}
NEXT_PUBLIC_SOCKET_URL=${NEXT_PUBLIC_SOCKET_URL}
NODE_ENV=production
EOF
    
    log_success ".env.production created"
}

# Next.js 빌드
build_nextjs() {
    log_info "Building Next.js application..."
    
    npm run build
    
    if [ ! -d "out" ]; then
        log_error "Build failed! 'out' directory not found"
        exit 1
    fi
    
    log_success "Next.js build complete"
}

# S3 업로드
upload_to_s3() {
    log_info "Uploading to S3: s3://$S3_BUCKET_NAME/"
    
    # 모든 파일 업로드 (긴 캐시)
    aws s3 sync out/ s3://$S3_BUCKET_NAME/ \
        --delete \
        --cache-control "public, max-age=31536000, immutable" \
        --region $AWS_REGION
    
    # HTML 파일은 캐시 없음
    aws s3 sync out/ s3://$S3_BUCKET_NAME/ \
        --exclude "*" \
        --include "*.html" \
        --cache-control "public, max-age=0, must-revalidate" \
        --region $AWS_REGION
    
    log_success "S3 upload complete"
}

# CloudFront 캐시 무효화
invalidate_cloudfront() {
    if [ -z "$CLOUDFRONT_DISTRIBUTION_ID" ]; then
        log_warning "CLOUDFRONT_DISTRIBUTION_ID not set, skipping cache invalidation"
        return 0
    fi
    
    log_info "Invalidating CloudFront cache..."
    
    INVALIDATION_ID=$(aws cloudfront create-invalidation \
        --distribution-id $CLOUDFRONT_DISTRIBUTION_ID \
        --paths "/*" \
        --query 'Invalidation.Id' \
        --output text)
    
    log_success "CloudFront cache invalidation started (ID: $INVALIDATION_ID)"
}

# 배포 확인
verify_deployment() {
    if [ -z "$PRODUCTION_URL" ]; then
        log_warning "PRODUCTION_URL not set, skipping deployment verification"
        return 0
    fi
    
    log_info "Waiting for deployment to propagate..."
    sleep 10
    
    log_info "Verifying deployment at $PRODUCTION_URL..."
    
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$PRODUCTION_URL" || echo "000")
    
    if [ "$HTTP_CODE" == "200" ]; then
        log_success "Production site is accessible (HTTP $HTTP_CODE)"
    else
        log_warning "Production site returned HTTP $HTTP_CODE"
    fi
}

# 메인 실행
main() {
    echo ""
    echo "🚀 Frontend Deployment Script"
    echo "================================"
    echo ""
    
    # 환경 변수 확인
    check_required_vars
    
    log_info "Configuration:"
    echo "  S3 Bucket: $S3_BUCKET_NAME"
    echo "  AWS Region: $AWS_REGION"
    echo "  API URL: $NEXT_PUBLIC_API_URL"
    echo "  Socket URL: $NEXT_PUBLIC_SOCKET_URL"
    [ -n "$CLOUDFRONT_DISTRIBUTION_ID" ] && echo "  CloudFront: $CLOUDFRONT_DISTRIBUTION_ID"
    [ -n "$PRODUCTION_URL" ] && echo "  Production URL: $PRODUCTION_URL"
    echo ""
    
    # 작업 디렉토리 확인
    if [ ! -f "package.json" ]; then
        log_error "package.json not found. Run this script from apps/frontend directory"
        exit 1
    fi
    
    # 배포 단계 실행
    create_nextjs_config
    create_env_production
    build_nextjs
    upload_to_s3
    invalidate_cloudfront
    verify_deployment
    
    echo ""
    log_success "Deployment completed successfully!"
    echo ""
}

# 스크립트 직접 실행 시에만 main 함수 실행
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main
fi
