import { NextRequest, NextResponse } from 'next/server';

export function proxy(request: NextRequest) {
  // The renderer reads the request CSP and applies this nonce to its own scripts/styles.
  // Never reuse or accept a nonce supplied by a visitor, and never cache nonce-bearing HTML.
  const nonce = btoa(String.fromCharCode(...crypto.getRandomValues(new Uint8Array(24))));
  const development = process.env.NODE_ENV === 'development';
  const csp = [
    "default-src 'self'",
    `script-src 'self' 'nonce-${nonce}' 'strict-dynamic'${development ? " 'unsafe-eval'" : ''}`,
    // Existing component libraries inject styles and use style attributes during hydration.
    // This exception applies only to CSS; scripts still require the per-request nonce.
    "style-src 'self' 'unsafe-inline'",
    "img-src 'self' data: blob:",
    "font-src 'self'",
    `connect-src 'self'${development ? ' ws: wss:' : ''}`,
    "object-src 'none'",
    "base-uri 'self'",
    "form-action 'self'",
    "frame-ancestors 'none'",
  ].join('; ');
  const headers = new Headers(request.headers);
  headers.set('Content-Security-Policy', csp);
  const response = NextResponse.next({ request: { headers } });
  response.headers.set('Content-Security-Policy', csp);
  response.headers.set('Cache-Control', 'private, no-store');
  return response;
}

export const config = {
  matcher: ['/((?!_next/static/|images/|icons/|fonts/|updates/|favicon\\.svg).*)'],
};
