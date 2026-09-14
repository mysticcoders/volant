# Volant hosting

Deploy directly to the owner Cloudflare account, never to Sites.
Primary: https://usevolant.com
Worker: volant-marketing
Account: 55b50ebf1d3295768fc53dd77cb0e2e6

Build: `npm run build`
Deploy: `npx wrangler deploy --config dist/server/wrangler.json`
The Vite config declares the Worker and usevolant.com Worker custom domain. Cloudflare manages its DNS and certificate.

getvolant.com and getvolant.app (including www) use Cloudflare dynamic redirect rules: permanent 301 to https://usevolant.com, preserving path and query. HTTPS redirects verified September 13, 2026. Mail records preserved.

Cloudflare DNS token is in the root ignored .env.cloudflare; load only in the deployment process, never application builds or client code. Wrangler OAuth handles Worker publishing. GitHub repository is public under MIT at https://github.com/mysticcoders/volant.

Lesson: hosting provider must match owner intent. The earlier Sites custom hostname and verification records were removed during migration. No Sites plugin is used by the build. Verify primary HTML and static assets after each deployment; a successful upload alone does not verify routing.

Latest verification: direct https://volant-marketing.andrew-55b.workers.dev returns HTTP 200 for the page and notes screenshot. Both alternate domains return 301 with path/query preserved. usevolant.com is registered as a Worker custom domain but returned Cloudflare 1034 / HTTP 403 at 22:45 UTC on September 13, 2026. Authoritative DNS still returned the former Sites edge addresses; recheck propagation and routing before declaring primary live. No new visual browser inspection was performed for this hosting-only migration.

## September 14, 2026 — native launcher screenshot published
Owner approved publishing the screenshot update. Deployed existing Cloudflare Worker `volant-marketing`, version `00a12181-38f6-4fa4-9921-e3e9d1ba8224`. Primary `https://usevolant.com/` now responds successfully and contains the native capture and expanded Herdr description. The live `/images/launcher-dark.png` matches the validated local asset byte-for-byte (SHA-256 `53859685e60a486478525954937d9024aefdb4ad34beabd478adb9e8878aec6d`). The earlier custom-domain routing failure is resolved. No DMG or update feed was published.


## Packaged download — September 14, 2026
Published Volant 0.1.0 (build 2), notarized and stapled DMG, signed Sparkle appcast, and checksums under `/updates/`. Download for Mac buttons now link directly to `/updates/Volant-0.1.0.dmg`; FAQ includes drag-to-Applications instructions. Worker version `cd45f136-3ef1-4483-b70b-dbd65a5a74b5`. Live DMG and feed returned HTTP 200 and matched the validated artifacts. Downloaded DMG passed stapler and Gatekeeper verification. Desktop/mobile CTA renders inspected. See `docs/release-quality.md` in the repository for remaining installed-upgrade and hardware verification.
