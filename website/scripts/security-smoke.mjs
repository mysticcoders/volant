import assert from 'node:assert/strict';
import { mkdir } from 'node:fs/promises';
import { chromium } from 'playwright';

const base = new URL(process.env.VOLANT_WEBSITE_TEST_URL ?? 'http://127.0.0.1:8787');
assert.equal(base.hostname, '127.0.0.1', 'Only the isolated loopback fixture may be tested');
const artifacts = process.env.VOLANT_WEBSITE_ARTIFACTS ?? '/tmp/volant-website-security';
await mkdir(artifacts, { recursive: true });
const browser = await chromium.launch({ headless: true });
const staticAssets = new Set();
try {
  for (const viewport of [{ width: 1440, height: 1000 }, { width: 390, height: 844 }]) {
    for (const colorScheme of ['light', 'dark']) {
      const context = await browser.newContext({ viewport, colorScheme });
      const page = await context.newPage();
      page.on('response', response => {
        if (new URL(response.url()).pathname.startsWith('/_next/static/')) staticAssets.add(response.url());
      });
      const errors = [];
      page.on('pageerror', error => errors.push(error.message));
      await page.addInitScript(() => {
        window.securityViolations = [];
        document.addEventListener('securitypolicyviolation', event => window.securityViolations.push({
          directive: event.effectiveDirective, blocked: event.blockedURI,
        }));
      });
      let lastNonce;
      for (const route of ['/', '/docs', '/docs/agents', '/docs/calculator', '/fictional-missing-page']) {
        console.log(viewport.width, colorScheme, route);
        const response = await page.goto(new URL(route, base).href, { waitUntil: 'networkidle' });
        assert.equal(response.status(), route.includes('fictional-missing') ? 404 : 200, route);
        const headers = response.headers();
        for (const [name, value] of Object.entries({
          'x-content-type-options': 'nosniff', 'x-frame-options': 'DENY',
          'cross-origin-opener-policy': 'same-origin', 'cross-origin-resource-policy': 'same-origin',
        })) assert.equal(headers[name], value, `${route}: ${name}`);
        assert.match(headers['permissions-policy'], /geolocation=\(\)/);
        assert.match(headers['cache-control'], /no-store/);
        const csp = headers['content-security-policy'];
        assert.ok(csp);
        assert.ok(!csp.split(';').find(value => value.trim().startsWith('script-src ')).includes('unsafe-inline'));
        assert.ok(!csp.includes('unsafe-eval'));
        const nonce = csp.match(/'nonce-([^']+)'/)?.[1];
        assert.ok(nonce && nonce !== lastNonce, 'A fresh nonce is required');
        lastNonce = nonce;
        assert.equal(await page.locator('h1').count(), 1, route);
        assert.ok((await page.locator('body').innerText()).length > 30, route);
        assert.deepEqual(await page.evaluate(() => window.securityViolations), [], route);
        assert.deepEqual(await page.locator('script').evaluateAll(scripts => scripts
          .filter(script => !script.type || script.type === 'module')
          .map(script => script.nonce)), await page.locator('script').evaluateAll((scripts, expected) => scripts
          .filter(script => !script.type || script.type === 'module').map(() => expected), nonce), route);
        assert.ok(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1), 'Horizontal overflow');
        if (!route.includes('fictional-missing')) {
          await page.evaluate(() => scrollTo(0, 0));
          await page.screenshot({
          path: `${artifacts}/${viewport.width}-${colorScheme}-${route === '/' ? 'home' : route.slice(1).replaceAll('/', '-')}.png`, fullPage: false,
        });
        }
      }
      await page.goto(new URL('/docs', base).href, { waitUntil: 'networkidle' });
      await page.getByRole('navigation', { name: 'Documentation' }).getByRole('link', { name: 'Agents', exact: true }).click();
      await page.waitForURL('**/docs/agents');
      await page.waitForLoadState('networkidle');
      assert.deepEqual(errors, [], 'Browser runtime errors');
      assert.deepEqual(await page.evaluate(() => window.securityViolations), [], 'Navigation CSP violations');
      // Simulate markup injection in a document, rather than a script created by an
      // already-trusted runtime (which strict-dynamic intentionally trusts).
      const fixture = await context.request.get(new URL('/', base).href);
      const fixtureHeaders = fixture.headers();
      delete fixtureHeaders['content-length'];
      delete fixtureHeaders['content-encoding'];
      const injectedBody = (await fixture.text()).replace('<head>', '<head><script>window.untrustedScriptExecuted = true</script>');
      await page.route('**/fictional-csp-injection', route => route.fulfill({
        status: 200,
        headers: fixtureHeaders,
        body: injectedBody,
      }));
      await page.goto(new URL('/fictional-csp-injection', base).href, { waitUntil: 'networkidle' });
      assert.equal(await page.evaluate(() => window.untrustedScriptExecuted), undefined, 'Injected markup script must be blocked');
      await page.waitForFunction(() => window.securityViolations.some(value => value.directive === 'script-src-elem'));
      await context.close();
    }
  }
  // A visitor cannot choose the renderer's CSP nonce through request headers.
  const response = await fetch(new URL('/', base), { headers: { 'Content-Security-Policy': "script-src 'nonce-fictional'" } });
  assert.ok(!response.headers.get('Content-Security-Policy').includes('nonce-fictional'));
  assert.ok(staticAssets.size > 0, 'Compiled assets must have loaded');
  for (const path of ['/favicon.svg', '/images/volant-icon.png', ...staticAssets]) {
    const asset = await fetch(new URL(path, base));
    assert.equal(asset.status, 200);
    assert.equal(asset.headers.get('X-Content-Type-Options'), 'nosniff', path);
    assert.equal(asset.headers.get('Cross-Origin-Resource-Policy'), 'same-origin', path);
    if (new URL(path, base).pathname.startsWith('/_next/static/')) assert.match(asset.headers.get('Cache-Control'), /immutable/);
  }
  console.log('Website security smoke passed: desktop/mobile, light/dark, hydration, navigation, headers and fresh nonces.');
} finally {
  await browser.close();
}
