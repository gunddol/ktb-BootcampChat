#!/bin/bash
# Frontend 빌드 및 S3 배포 자동화
# 사용법: ./deployment-scripts/05-deploy-frontend.sh

set -e

echo "🎨 Frontend Deployment Script"
echo ""

# 환경 변수 로드
if [ -f .env.deployment ]; then
    source .env.deployment
else
    echo "❌ .env.deployment not found!"
    exit 1
fi

# S3 버킷 이름
BUCKET_NAME="${BUCKET_NAME:-ktb-015-chat-frontend}"
FRONTEND_DIR="/Users/gunddol/DEV/KTB_Workspace/ktb-BootcampChat/apps/frontend"

echo "Configuration:"
echo "  Bucket: $BUCKET_NAME"
echo "  Frontend: $FRONTEND_DIR"
echo "  Domain: $DOMAIN"
echo ""

# 1. Next.js 설정 확인
echo "📝 Step 1: Checking Next.js configuration..."

cd "$FRONTEND_DIR"

# next.config.js 생성
cat > next.config.js << 'EOF'
/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: false,
  transpilePackages: ['@vapor-ui/core', '@vapor-ui/icons'],
  
  // S3/CloudFront 배포용
  output: 'export',
  
  // 이미지 최적화 비활성화
  images: {
    unoptimized: true,
  },
  
  // Trailing slash
  trailingSlash: true,
  
  // 압축
  compress: true,
};

module.exports = nextConfig;
EOF

echo "✅ next.config.js updated"

# .env.production 생성
cat > .env.production << EOF
NEXT_PUBLIC_API_URL=https://api.$DOMAIN
NODE_ENV=production
EOF

echo "✅ .env.production created"
echo ""

# 2. 빌드
echo "🔨 Step 2: Building Next.js..."
npm run build

if [ ! -d "out" ]; then
    echo "❌ Build failed! 'out' directory not found"
    exit 1
fi

echo "✅ Build complete"
echo ""

# 3. S3 버킷 확인
echo "☁️  Step 3: Checking S3 bucket..."

BUCKET_EXISTS=$(aws s3 ls s3://$BUCKET_NAME 2>&1 || true)

if [[ $BUCKET_EXISTS == *"NoSuchBucket"* ]]; then
    echo "📦 Creating S3 bucket: $BUCKET_NAME"
    
    aws s3 mb s3://$BUCKET_NAME --region $AWS_REGION
    
    # 정적 웹 호스팅 활성화
    aws s3 website s3://$BUCKET_NAME \
        --index-document index.html \
        --error-document 404.html
    
    echo "✅ Bucket created and configured"
else
    echo "✅ Bucket exists: $BUCKET_NAME"
fi

echo ""

# 4. S3 업로드
echo "⬆️  Step 4: Uploading to S3..."

# 전체 파일 업로드
aws s3 sync out/ s3://$BUCKET_NAME/ \
    --delete \
    --cache-control "public, max-age=31536000, immutable" \
    --region $AWS_REGION

# HTML 파일 캐시 설정 (캐시 없음)
aws s3 sync out/ s3://$BUCKET_NAME/ \
    --exclude "*" \
    --include "*.html" \
    --cache-control "public, max-age=0, must-revalidate" \
    --region $AWS_REGION

echo "✅ Upload complete"
echo ""

# 5. S3 버킷 정책 설정 (임시 - CloudFront 전)
echo "🔐 Step 5: Setting bucket policy..."

cat > /tmp/bucket-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "PublicReadGetObject",
            "Effect": "Allow",
            "Principal": "*",
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::$BUCKET_NAME/*"
        }
    ]
}
EOF

aws s3api put-bucket-policy \
    --bucket $BUCKET_NAME \
    --policy file:///tmp/bucket-policy.json \
    --region $AWS_REGION

rm /tmp/bucket-policy.json

echo "✅ Bucket policy set"
echo ""

# 6. 결과
S3_WEBSITE_URL="http://$BUCKET_NAME.s3-website.$AWS_REGION.amazonaws.com"

echo "✅ Frontend Deployment Complete!"
echo ""
echo "S3 Website URL:"
echo "  $S3_WEBSITE_URL"
echo ""
echo "Test it:"
echo "  curl -I $S3_WEBSITE_URL"
echo "  open $S3_WEBSITE_URL"
echo ""
echo "⚠️  Next steps:"
echo "  1. Create CloudFront distribution (AWS Console)"
echo "  2. Update bucket policy for CloudFront OAC"
echo "  3. Configure Route 53 DNS"
echo ""
echo "See: final_deployment_steps.md (Step 2-4 ~ 2-9)"
