import { readFileSync, writeFileSync } from 'node:fs';

const headers = JSON.parse(readFileSync(new URL('../security-headers.json', import.meta.url), 'utf8'));
// Cloudflare serves hashed assets before the worker: next.config headers alone cannot cover them.
writeFileSync(new URL('../public/_headers', import.meta.url), [
  '# Generated from security-headers.json; the worker uses the same policy.',
  '/*',
  ...headers.map(({ key, value }) => `  ${key}: ${value}`),
  '',
  '/_next/static/*',
  '  Cache-Control: public, max-age=31536000, immutable',
  '',
].join('\n'));
