import type { NextConfig } from 'next';
import securityHeaders from './security-headers.json';

const nextConfig: NextConfig = {
  async headers() {
    return [{
      source: '/:path*',
      headers: securityHeaders,
    }];
  },
};

export default nextConfig;
