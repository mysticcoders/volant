// Checks that a second visit to /try reuses the cached calculator module: a persistent Chromium
// profile (with a disk cache, as a real browser has) loads the page twice and reports where the
// module came from each time and whether a percentage was shown.
// Usage: node scripts/try-cache-check.mjs http://127.0.0.1:8798
import { mkdtemp } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { chromium } from 'playwright';

const base = process.argv[2];
const profile = await mkdtemp(path.join(os.tmpdir(), 'try-cache-'));
const context = await chromium.launchPersistentContext(profile, { headless: true });
const page = await context.newPage();
const cdp = await context.newCDPSession(page);
await cdp.send('Network.enable');
for (const visit of [1, 2]) {
  // The first visit downloads over a throttled connection (about 3 MB/s), as on a real network.
  const throughput = visit === 1 ? 3 * 1024 * 1024 : -1;
  await cdp.send('Network.emulateNetworkConditions', { offline: false, latency: 0, downloadThroughput: throughput, uploadThroughput: throughput });
  await page.goto(`${base}/try`, { waitUntil: 'domcontentloaded' });
  const percent = await page.waitForFunction(() => !!document.querySelector('.try-progress'), null, { timeout: 3000 }).then(() => true, () => false);
  await page.locator('.try-bar input').fill('2+2');
  await page.locator('.try-answer').first().waitFor({ timeout: 60000 });
  await page.waitForTimeout(300);
  console.log(`visit ${visit}: progress bar shown ${percent}; footer "${await page.locator('.try-footer-note').textContent()}"`);
}
await context.close();
