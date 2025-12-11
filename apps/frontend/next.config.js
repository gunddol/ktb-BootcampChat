/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: false,
  transpilePackages: ['@vapor-ui/core', '@vapor-ui/icons'],

  // ⭐ S3/CloudFront 배포를 위한 설정
  output: undefined,  // 정적 HTML 출력

  // 이미지 최적화 비활성화 (S3는 이미지 최적화 불가)
  images: {
    unoptimized: true,
  },

  // Trailing slash (S3 호환성)
  trailingSlash: false,

  // Asset prefix (CloudFront URL, 배포 후 추가)
  assetPrefix: process.env.NEXT_PUBLIC_CDN_URL || '',

  // Gzip 압축
  compress: true,
};
module.exports = nextConfig;
