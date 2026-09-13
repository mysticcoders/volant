# Volant hosting

Deploy directly to the owner Cloudflare account, never to Sites.
Primary: https://usevolant.com
Worker: volant-marketing
Account: 55b50ebf1d3295768fc53dd77cb0e2e6

Build: `npm run build`
Deploy: `npx wrangler deploy --config dist/server/wrangler.json`
The Vite config declares the Worker and usevolant.com Worker custom domain. Cloudflare manages its DNS and certificate.

getvolant.com and getvolant.app (including www) use Cloudflare dynamic redirect rules: permanent 301 to https://usevolant.com, preserving path and query. HTTPS redirects verified September 13, 2026. Mail records preserved.

Cloudflare DNS token is in the root ignored .env.cloudflare; load only in the deployment process, never application builds or client code. Wrangler OAuth handles Worker publishing. GitHub repository remains private until 0.1.

Lesson: hosting provider must match owner intent. The earlier Sites custom hostname and verification records were removed during migration. No Sites plugin is used by the build. Verify primary HTML and static assets after each deployment; a successful upload alone does not verify routing.
