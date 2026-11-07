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
  // The /try demo's worker scripts, extension modules and data are static files; workers created
  // from them take this policy, which allows compiling WebAssembly and same-origin fetches only.
  '/try/*',
  "  Content-Security-Policy: default-src 'none'; script-src 'self' 'wasm-unsafe-eval'; connect-src 'self'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
  '',
].join('\n'));
