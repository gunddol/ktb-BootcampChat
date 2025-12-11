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
