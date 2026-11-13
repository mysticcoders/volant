// Drives the /try demo in headless Chromium against a local build and captures screenshots.
// Usage (from website/, with the site served): node scripts/try-drive.mjs http://127.0.0.1:8797 <out-dir>
import { mkdir } from 'node:fs/promises';
import { chromium } from 'playwright';

const [base, out] = process.argv.slice(2);
await mkdir(out, { recursive: true });
const browser = await chromium.launch({ headless: true });
const results = {};

/** Opens /try in a fresh page with the given appearance and viewport, failing on CSP violations. */
async function open(scheme, viewport) {
  const context = await browser.newContext({ colorScheme: scheme, viewport, deviceScaleFactor: 2 });
  const page = await context.newPage();
  const problems = [];
  page.on('console', (m) => { if (m.type() === 'error') problems.push(m.text()); });
  page.on('pageerror', (e) => problems.push(String(e)));
  let bytes = 0;
  page.on('response', async (r) => { try { bytes += (await r.body()).length; } catch {} });
  const started = Date.now();
  await page.goto(`${base}/try`, { waitUntil: 'networkidle' });
  await page.locator('.try-row').first().waitFor();
  return { page, context, problems, loadMs: Date.now() - started, bytes: () => bytes };
}

/** Types into the field, waits for the demo to settle, and returns the visible row titles. */
async function type(page, text) {
  await page.locator('.try-bar input').fill(text);
  await page.waitForTimeout(700);
  return page.locator('.try-title').allTextContents();
}

/** Types a query at the top level and returns the calculator's answer texts once they settle. */
async function calc(page, text) {
  await page.locator('.try-bar input').fill(text);
  // The demo shows only answers computed for the current text, so any answer row is this query's.
  await page.waitForFunction((q) => document.querySelector('.try-bar input').value === q
    && (document.querySelector('.try-answer') || document.querySelector('.try-error')
      || [...document.querySelectorAll('.try-empty')].some((e) => /^(Nothing matches|Live rates)/.test(e.textContent))), text, { timeout: 120000 }).catch(() => {});
  await page.waitForTimeout(400);
  return page.locator('.try-answer').evaluateAll((rows) => rows.map((r) => r.textContent.replace(/\s+/g, ' ').trim()));
}

/** Loads /try over a throttled connection (about 3 MB/s) so the calculator's progress bar is
 * visible: captures it mid-download, types a calculator query and an extension word while it
 * loads, checks the answer arrives by itself, then reloads to confirm the cached module skips it. */
async function progressRun(scheme) {
  const context = await browser.newContext({ colorScheme: scheme, viewport: { width: 1280, height: 900 }, deviceScaleFactor: 2 });
  const page = await context.newPage();
  const problems = [];
  page.on('pageerror', (e) => problems.push(String(e)));
  page.on('console', (m) => { if (m.type() === 'error') problems.push(m.text()); });
  const cdp = await context.newCDPSession(page);
  await cdp.send('Network.enable');
  await cdp.send('Network.emulateNetworkConditions', { offline: false, latency: 20, downloadThroughput: 3 * 1024 * 1024, uploadThroughput: 1024 * 1024 });
  await page.goto(`${base}/try`, { waitUntil: 'domcontentloaded' });
  const started = Date.now();
  await page.waitForFunction(() => /\b([2-9]\d)%/.test(document.querySelector('.try-progress-label')?.textContent ?? ''), null, { timeout: 60000 });
  results[`${scheme} bar label mid-load`] = await page.locator('.try-progress-label').textContent();
  await page.screenshot({ path: `${out}/try-${scheme}-loading.png` });
  await page.locator('.try-bar input').fill('3pm tokyo in new york');
  await page.waitForTimeout(300);
  results[`${scheme} inline while loading`] = await page.locator('.try-empty').allTextContents();
  await page.locator('.try-bar input').fill('h');
  await page.waitForTimeout(300);
  results[`${scheme} extensions while loading`] = (await page.locator('.try-title').allTextContents()).length;
  await page.locator('.try-bar input').fill('3pm tokyo in new york');
  await page.screenshot({ path: `${out}/try-${scheme}-loading-query.png` });
  await page.locator('.try-answer').first().waitFor({ timeout: 120000 });
  results[`${scheme} answer after load`] = (await page.locator('.try-answer-result').allTextContents())[0];
  results[`${scheme} throttled load ms`] = Date.now() - started;
  results[`${scheme} ready label`] = await page.locator('.try-progress-label').textContent().catch(() => '(bar already hidden)');
  await page.screenshot({ path: `${out}/try-${scheme}-ready.png` });
  await page.waitForTimeout(2000);
  results[`${scheme} bar after ready`] = await page.locator('.try-progress').count();
  await page.reload({ waitUntil: 'domcontentloaded' });
  const seen = await page.waitForFunction(() => /\d+%/.test(document.querySelector('.try-progress-label')?.textContent ?? ''), null, { timeout: 4000 }).then(() => true, () => false);
  results[`${scheme} second visit showed percent`] = seen;
  results[`${scheme} progress problems`] = problems;
  await context.close();
}

/** Blocks the calculator module so loading fails, checks the error and Retry, then lets Retry load it. */
async function failureRun() {
  const context = await browser.newContext({ colorScheme: 'light', viewport: { width: 1280, height: 900 }, deviceScaleFactor: 2 });
  let blocked = true;
  await context.route('**/try/calculator/**', (route) => (blocked ? route.abort() : route.continue()));
  const page = await context.newPage();
  await page.goto(`${base}/try`, { waitUntil: 'domcontentloaded' });
  const failed = await page.locator('.try-progress[data-state="error"]').waitFor({ timeout: 15000 }).then(() => true, () => false);
  results['failure shown'] = failed ? await page.locator('.try-progress').textContent() : '(not observed: route may not reach worker fetches)';
  if (failed) {
    await page.locator('.try-bar input').fill('2+2');
    await page.waitForTimeout(300);
    results['failure answers'] = await page.locator('.try-answer').count();
    await page.screenshot({ path: `${out}/try-light-load-failed.png` });
    blocked = false;
    await page.getByRole('button', { name: 'Retry' }).click();
    await page.locator('.try-answer').first().waitFor({ timeout: 60000 }).catch(() => {});
    results['after retry'] = (await page.locator('.try-answer-result').allTextContents())[0] ?? '(no answer)';
  }
  await context.close();
}

/** Captures the homepage hero card mid-loop with an answer showing, checks the appearance button
 * still switches it, and that typing hands over to /try with the text and the calculator answering. */
async function heroRun(scheme, viewport, label, query = '') {
  const context = await browser.newContext({ colorScheme: scheme, viewport, deviceScaleFactor: 2 });
  const page = await context.newPage();
  const problems = [];
  page.on('pageerror', (e) => problems.push(String(e)));
  page.on('console', (m) => { if (m.type() === 'error') problems.push(m.text()); });
  await page.goto(`${base}/${query}`, { waitUntil: 'networkidle' });
  results[`hero ${label} prompt`] = await page.locator('.hero-launcher input').getAttribute('placeholder');
  await page.locator('.hero-live .try-row[aria-current="true"]').waitFor({ timeout: 15000 });
  results[`hero ${label} frame`] = `${await page.locator('.hero-ghost').textContent()} → ${await page.locator('.hero-live .try-row[aria-current="true"]').textContent()}`;
  results[`hero ${label} note`] = await page.locator('.hero-launcher .try-footer-note').textContent();
  await page.screenshot({ path: `${out}/hero-${label}-animating.png` });
  if (label === 'light') {
    const before = await page.locator('.home-refresh').getAttribute('data-theme');
    await page.locator('.home-appearance').click();
    results['appearance button'] = `${before} -> ${await page.locator('.home-refresh').getAttribute('data-theme')}`;
  }
  await page.getByRole('textbox', { name: 'Try Volant in your browser now' }).pressSequentially('1');
  await page.waitForURL('**/try?q=1', { timeout: 15000 });
  await page.locator('.try-bar input').pressSequentially('5% of 80');
  await page.locator('.try-answer').first().waitFor({ timeout: 120000 });
  results[`hand-off ${label}`] = `${await page.locator('.try-bar input').inputValue()} → ${(await page.locator('.try-answer-result').allTextContents())[0]}`;
  await page.screenshot({ path: `${out}/handoff-${label}.png` });
  results[`hero ${label} problems`] = problems;
  await context.close();
}

/** Captures the hero as first painted, with JavaScript disabled: the prompt and an empty results
 * area, like an empty launcher. */
async function firstPaintRun(scheme, viewport, label, query = '') {
  const context = await browser.newContext({ colorScheme: scheme, viewport, deviceScaleFactor: 2, javaScriptEnabled: false });
  const page = await context.newPage();
  await page.goto(`${base}/${query}`, { waitUntil: 'load' });
  results[`first paint ${label}`] = `${await page.locator('.hero-live .try-row').count()} rows; prompt ${await page.locator('.hero-launcher input').getAttribute('placeholder')}`;
  await page.screenshot({ path: `${out}/hero-${label}-first-paint.png` });
  await context.close();
}

/** Captures /try at rest in the site's design with a calculator answer showing. */
async function tryPageRun(scheme, viewport, label) {
  const context = await browser.newContext({ colorScheme: scheme, viewport, deviceScaleFactor: 2 });
  const page = await context.newPage();
  await page.goto(`${base}/try?q=${encodeURIComponent('3pm tokyo in new york')}`, { waitUntil: 'networkidle' });
  await page.locator('.try-answer').first().waitFor({ timeout: 120000 });
  await page.waitForTimeout(1800);
  await page.screenshot({ path: `${out}/try-page-${label}.png` });
  results[`try page ${label}`] = (await page.locator('.try-answer-result').allTextContents())[0];
  await context.close();
}

/** Captures the header nav (Try it first), the hero's "Try it now" link, the homepage's WebAssembly
 * section and its line on /try, and checks where the link goes. */
async function wasmRun(scheme, viewport, label) {
  const context = await browser.newContext({ colorScheme: scheme, viewport, deviceScaleFactor: 2 });
  const page = await context.newPage();
  await page.goto(`${base}/`, { waitUntil: 'networkidle' });
  results[`nav ${label}`] = (await page.locator('nav[aria-label="Main navigation"] a').allTextContents()).join(', ');
  await page.locator('header.nav').screenshot({ path: `${out}/nav-${label}.png` });
  const cta = page.locator('.home-hero .home-secondary');
  results[`hero cta ${label}`] = `${(await cta.textContent()).trim()} -> ${await cta.getAttribute('href')}`;
  await page.locator('.home-hero').screenshot({ path: `${out}/hero-cta-${label}.png` });
  await page.locator('.home-wasm').scrollIntoViewIfNeeded();
  await page.locator('.home-wasm').screenshot({ path: `${out}/wasm-home-${label}.png` });
  results[`wasm home ${label}`] = await page.locator('.home-wasm h2').textContent();
  await page.goto(`${base}/try`, { waitUntil: 'networkidle' });
  await page.locator('.try-notes').screenshot({ path: `${out}/wasm-try-${label}.png` });
  results[`wasm try ${label}`] = (await page.locator('.try-notes li').nth(1).textContent()).slice(0, 60);
  await context.close();
}

await wasmRun('light', { width: 1280, height: 900 }, 'light');
await wasmRun('dark', { width: 1280, height: 900 }, 'dark');
await wasmRun('dark', { width: 390, height: 844 }, 'mobile-dark');
for (const { scheme, viewport, label } of [
  { scheme: 'light', viewport: { width: 1280, height: 900 }, label: 'light' },
  { scheme: 'dark', viewport: { width: 1280, height: 900 }, label: 'dark' },
  { scheme: 'dark', viewport: { width: 390, height: 844 }, label: 'mobile-dark' },
]) {
  await firstPaintRun(scheme, viewport, label);
}
await heroRun('light', { width: 1280, height: 900 }, 'light');
await heroRun('dark', { width: 1280, height: 900 }, 'dark');
await heroRun('dark', { width: 390, height: 844 }, 'mobile-dark');
await tryPageRun('light', { width: 1280, height: 900 }, 'light');
await tryPageRun('dark', { width: 1280, height: 900 }, 'dark');
await tryPageRun('light', { width: 390, height: 844 }, 'mobile-light');
await progressRun('light');
await progressRun('dark');
await failureRun();

for (const scheme of ['light', 'dark']) {
  const { page, context, problems, loadMs, bytes } = await open(scheme, { width: 1280, height: 900 });
  results[`${scheme} load ms`] = loadMs;
  const coldStart = Date.now();
  results[`${scheme} 2+2`] = await calc(page, '2+2');
  results[`${scheme} calculator cold ms`] = Date.now() - coldStart;
  results[`${scheme} calculator footer`] = await page.locator('.try-footer-note').textContent();
  for (const q of ['15% of 80', '5 km in miles', '3pm tokyo in new york', 'now in london']) results[`${scheme} ${q}`] = await calc(page, q);
  await calc(page, '3pm tokyo in new york');
  await page.screenshot({ path: `${out}/try-${scheme}-time.png` });
  results[`${scheme} 100 usd in eur`] = await calc(page, '100 usd in eur');
  results[`${scheme} currency credits`] = await page.locator('.try-hint').allTextContents();
  await page.screenshot({ path: `${out}/try-${scheme}-currency.png` });
  results[`${scheme} 0.1 btc in usd`] = await calc(page, '0.1 btc in usd');
  results[`${scheme} 1000 aed in usd`] = await calc(page, '1000 aed in usd');
  results[`${scheme} credits after aed`] = await page.locator('.try-hint').allTextContents();
  await page.locator('.try-bar input').fill('');
  await type(page, 'hn');
  await page.keyboard.press('Enter');
  await page.locator('.try-badge').first().waitFor({ timeout: 5000 });
  results[`${scheme} hn rows`] = (await page.locator('.try-title').allTextContents()).length;
  results[`${scheme} footer`] = await page.locator('.try-footer-note').textContent();
  await page.screenshot({ path: `${out}/try-${scheme}-hn.png`, fullPage: false });
  await page.selectOption('.try-filter', 'show');
  await page.waitForTimeout(700);
  results[`${scheme} show hn first`] = (await page.locator('.try-title').allTextContents())[0];
  await page.keyboard.press('Escape');
  await page.locator('.try-bar input').focus();
  await page.keyboard.press('Escape');
  await type(page, 'case');
  await page.keyboard.press('Enter');
  results[`${scheme} case`] = await type(page, 'try volant now');
  await page.screenshot({ path: `${out}/try-${scheme}-case.png` });
  await page.keyboard.press('Escape');
  await page.keyboard.press('Escape');
  await type(page, 'wiki');
  await page.keyboard.press('Enter');
  results[`${scheme} wiki`] = (await type(page, 'WebAssembly')).slice(0, 3);
  results[`${scheme} wiki miss`] = await (async () => { await type(page, 'Volant launcher'); return page.locator('.try-footer-note').textContent(); })();
  await page.keyboard.press('Escape');
  await page.keyboard.press('Escape');
  await type(page, 'hello');
  await page.keyboard.press('Enter');
  results[`${scheme} hello`] = await type(page, 'visitor');
  results[`${scheme} problems`] = problems;
  results[`${scheme} payload KB`] = Math.round(bytes() / 1024);
  await context.close();
}

const mobile = await open('dark', { width: 390, height: 844 });
results['mobile 3pm tokyo'] = await calc(mobile.page, '3pm tokyo in new york');
await mobile.page.screenshot({ path: `${out}/try-mobile-dark-time.png` });
await mobile.page.locator('.try-bar input').fill('');
await type(mobile.page, 'lobsters');
await mobile.page.keyboard.press('Enter');
await mobile.page.locator('.try-badge').first().waitFor({ timeout: 5000 }).catch(() => {});
await mobile.page.waitForTimeout(500);
await mobile.page.screenshot({ path: `${out}/try-mobile-dark-lobsters.png` });
results['mobile lobsters rows'] = (await mobile.page.locator('.try-title').allTextContents()).length;
results['mobile problems'] = mobile.problems;
await mobile.context.close();
await browser.close();
console.log(JSON.stringify(results, null, 2));
