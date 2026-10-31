# Security remediation — 2026-10-28

Follow-up to [the initial review](security-review-2026-10-27.md). This change remediates the initial dependency inventory, streaming response limits and website header gaps. It does not publish the website or distribute an app release.

## Dependencies

- OSV 2.7.0 now reports **zero** advisory matches across nine tracked inputs. The 99 initial exact-match exceptions have been removed, without extending their original expiry. Every new advisory match blocks. npm audit also reports zero findings in both the website and ACP adapter trees.
- ACP provider versions stay pinned at Claude ACP 0.76.0 and Codex ACP 1.11.0; compatible transitive updates fix the findings. Transport code and provider capabilities do not change. The fake-agent transport suite is separate from authenticated installed-provider verification.
- Website React/RSC, vinext, Vite, Cloudflare tooling and formatter pins move to patched versions, with compatible peers. Two temporary, exact transitive overrides remain: `miniflare` uses undici 7.30.1 (same major, upstream pinned an affected version); fflate uses patched 0.7.5 (within its upstream 0.7 range). Recheck and remove overrides when upstream constraints resolve to safe versions without them. No forced audit downgrade or peer-dependency bypass is used.
- The site imported only CSS from the `shadcn` component-generation CLI. Its exact existing 4.18.0 stylesheet is retained locally with provenance, SHA-256 and MIT license, removing that unused CLI/registry dependency tree without changing design tokens. Review future stylesheet updates independently.
- Native CI uses hash-locked `tools/security/requirements.txt`, including cryptography and transitive packages. The exact environment passes the Raycast archive/persistence fixtures. OSV scans it too.
- `tools/security/Package.resolved` inventories the existing Sparkle 2.10.0 revision. CI checks the URL/version against `project.yml`. OSV's all-packages output confirmed `SwiftURL` / `github.com/sparkle-project/Sparkle`, avoiding a false claim of coverage under a different ecosystem. This inventory does not change Xcode's existing exact-version resolution behavior or independently prove the integrity of downloaded artifacts.

## Rates helper

`VolantRatesHost` now uses data-delegate callbacks with per-request bounded buffers. An oversized advertised length is refused before body receipt; every chunk is checked before append, including unknown-length and cumulative overflow. Cancellation removes pending state before replying, so later completion callbacks cannot reply again. Provider URLs, redirect refusal, parsing before reply, keyless requests, the saved-key rejection and 429 backoff message remain intact. Session initialization is eager, and cookies, credential storage and cache are disabled.

Six isolated URLProtocol tests exercise the real helper class: exactly-at-limit chunked success, unknown-length overflow before completion, advertised oversize without a body, one oversized chunk, status-specific failures and malformed success data. No provider credentials or owner data are used. The signed fixture passed actual XPC delivery and parsed ECB, ExchangeRate-API and keyless CoinGecko replies from the built Debug helper; this is not a distributed-release or installed-app verification.

## Website policy and verification

- Worker responses and Cloudflare static assets share `security-headers.json`: nosniff, DENY framing, Referrer-Policy, disabled camera/microphone/geolocation, and same-origin opener/resource policy. The prebuild generates `_headers` for assets; testing only worker responses missed hashed JS/CSS because the asset service runs first.
- HTML has an unpredictable per-request 192-bit script nonce, strict-dynamic, restricted source directives, and no-store caching. A visitor-supplied CSP cannot select the nonce. Dynamic rendering is intentional: nonce-bearing HTML cannot be shared in a CDN cache. Static hashed assets retain immutable caching.
- The existing client component libraries need inline styles and style attributes. `style-src 'unsafe-inline'` is a documented CSS-only compatibility exception; inline scripts and production eval are not permitted by the document policy. No broad ZAP ignore was added to conceal this exception.
- Headless Chromium checks desktop/mobile and OS light/dark preferences, home/docs/agents/calculator and 404 responses, hydration without runtime/CSP errors, actual documentation navigation, fresh nonces, rejection of injected untrusted markup scripts, and compiled-asset headers. Home/docs screenshots are separately inspected for readable layout and overflow. The existing website intentionally uses its dark palette in both OS appearances.
- CI runs these browser checks on PRs as well as weekly/manual runs. ZAP remains passive and weekly/manual; downloads stay excluded. Local Docker and Ubuntu hosted execution are separate evidence. CSP and header behavior must still be checked after a future authorized production deployment, since CDN/TLS configuration can differ.

The CSP implementation follows the framework's [nonce/dynamic-rendering guidance](https://nextjs.org/docs/app/guides/content-security-policy), verified against the actual compiled vinext worker and browser. [npm documents](https://docs.npmjs.com/cli/commands/npm-audit/) why compatible lockfile fixes can be applied without invoking lifecycle scripts; installation uses `--ignore-scripts` and avoids `--force`.

## Local validation results

- `Scripts/test.sh --base origin/main`: passed, including 400 app tests (four existing skips), Core and transport/persistence checks. Native UI was unchanged and not selected.
- Six real rates-helper fixture tests and the signed keyless live-XPC smoke: passed.
- Hash-locked Python install plus 31 Raycast archive/persistence checks: passed.
- Website clean install, build, lint and browser security smoke: passed. Desktop/mobile and both OS appearance settings were checked; rendered screenshots were inspected separately from test assertions.
- OSV across nine inputs: zero matches; npm audits: zero findings. Dependency gate/context tests, input alignment check, actionlint and zizmor: passed.
- Final local pinned ZAP: **63 rule passes, four warning groups, exit 2**, no configured FAIL alerts. Remaining groups are the explicit CSS inline compatibility exception, missing COEP, and the previously inspected public documentation SQL/timestamp false positives. COEP is not enabled by this change: cross-origin isolation was not required by the site. Keep this remaining policy choice visible rather than claiming all headers or warnings are resolved.

## Recurring lesson

- Symptom: a header check passed for HTML and a public icon, while hashed bundles still lacked protections.
- Cause: Cloudflare's asset path bypasses the worker; component-injected styles also differ from server-rendered styles.
- Prevention: one policy for worker and assets, assertions against assets actually loaded by a browser, and hydration/navigation checks alongside header assertions. These checks are automated in PR CI; screenshot inspection and signed live-XPC smoke remain separately reported evidence.

## Production verification — 2026-10-30

Read-only checks against the 0.3.28 deployment, with no configuration change (#313):

- `VOLANT_WEBSITE_TARGET=production npm run test:security` (`test:security:production`, fixed to `https://usevolant.com`; the loopback guard still applies to every other run) passed every browser assertion: desktop and mobile, both appearance settings, CSP with a fresh nonce per response, no inline-script or eval allowance, the shared header policy and no-store HTML on `/`, `/docs`, `/docs/agents`, `/docs/calculator` and a 404, documentation navigation without runtime errors or CSP violations, a blocked injected markup script, and `nosniff`, resource-policy and immutable caching on the hashed JS and CSS the browser actually loaded. The screenshots were inspected; the site is dark-only by design.
- It then failed its HTTP check: `http://usevolant.com/`, `/docs/agents` and `/updates/appcast.xml` return 200 over plain HTTP. The app is unaffected (its feed is `https://` and the DMG is signed and notarized), but browsers following an `http://` link stay on HTTP.

Policy decided October 30, 2026: the owner turns on Cloudflare's **Always Use HTTPS** for the usevolant.com zone, and the site sends `Strict-Transport-Security: max-age=31536000` from `security-headers.json` (Worker and static assets), without `includeSubDomains` or preload, so the `getvolant.*` redirect domains and future subdomains are unaffected and the policy stays reversible. Browsers ignore HSTS over plain HTTP, so it takes effect only once a visitor reaches HTTPS. `Scripts/ship.sh` now refuses to start a release while plain HTTP does not redirect permanently, and runs the production smoke, including the redirect and HSTS checks, before publishing the GitHub release.

## Remaining backlog

1. Continue to treat ZAP warning exits as warnings, not a clean scan. Keep the CSS-only CSP exception explicit; do not weaken script protection to make libraries render.
2. Recheck the temporary overrides and vendored CSS when upstream packages change; run OSV/npm and the browser suite again.
3. Production headers and cache behavior were verified on October 30, 2026 (below). TLS configuration beyond certificate/hostname and TLS 1.2/1.3 negotiation has not been audited. Installed authenticated ACP provider testing remains separate from dependency resolution and fake transports.
