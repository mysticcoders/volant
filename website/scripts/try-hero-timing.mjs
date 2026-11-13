// Measures the homepage hero in headless Chromium with a 4x CPU throttle and DevTools' "Fast 4G"
// profile (9 Mbps down, 1.5 Mbps up, 60 ms latency): first contentful paint, largest contentful
// paint, and when the hero card first shows replayed example content (a typed character).
// Usage: node scripts/try-hero-timing.mjs <base URL> [runs]
import { chromium } from 'playwright';

const [base, runsArg] = process.argv.slice(2);
const runs = Number(runsArg ?? 5);
const browser = await chromium.launch({ headless: true });

/** One cold load of `path`: returns FCP, LCP and the first time example content was visible, in ms. */
async function measure(path) {
  const context = await browser.newContext({ viewport: { width: 1280, height: 900 } });
  const page = await context.newPage();
  const cdp = await context.newCDPSession(page);
  await cdp.send('Network.enable');
  await cdp.send('Network.setCacheDisabled', { cacheDisabled: true });
  await cdp.send('Emulation.setCPUThrottlingRate', { rate: 4 });
  await cdp.send('Network.emulateNetworkConditions', {
    offline: false, latency: 60, downloadThroughput: (9 * 1024 * 1024) / 8, uploadThroughput: (1.5 * 1024 * 1024) / 8,
  });
  await page.addInitScript(() => {
    window.__heroTimes = { lcp: 0, example: 0, cls: 0 };
    new PerformanceObserver((list) => {
      for (const entry of list.getEntries()) window.__heroTimes.lcp = entry.startTime;
    }).observe({ type: 'largest-contentful-paint', buffered: true });
    new PerformanceObserver((list) => {
      for (const entry of list.getEntries()) if (!entry.hadRecentInput) window.__heroTimes.cls += entry.value;
    }).observe({ type: 'layout-shift', buffered: true });
    /** Records the first frame in which the hero card shows a typed character of a recorded example. */
    const check = () => {
      const node = document.querySelector('.hero-launcher .hero-ghost-text');
      if (node && node.getBoundingClientRect().height > 0 && !window.__heroTimes.example) {
        window.__heroTimes.example = performance.now();
        return;
      }
      if (!window.__heroTimes.example) requestAnimationFrame(check);
    };
    requestAnimationFrame(check);
  });
  await page.goto(`${base}${path}`, { waitUntil: 'load' });
  await page.waitForFunction(() => window.__heroTimes.example > 0, null, { timeout: 30000 }).catch(() => {});
  // Long enough for hydration and the typing loop to start, so their layout shifts would count.
  await page.waitForTimeout(3000);
  const fcp = await page.evaluate(() => performance.getEntriesByName('first-contentful-paint')[0]?.startTime ?? 0);
  const times = await page.evaluate(() => window.__heroTimes);
  await context.close();
  return { fcp, lcp: times.lcp, example: times.example, cls: times.cls };
}

/** The median of a list of numbers. */
const median = (values) => [...values].sort((a, b) => a - b)[Math.floor(values.length / 2)];

for (const path of ['/']) {
  const samples = [];
  for (let i = 0; i < runs; i++) samples.push(await measure(path));
  const summary = Object.fromEntries(['fcp', 'lcp', 'example'].map((key) => [key, Math.round(median(samples.map((s) => s[key])))]));
  const cls = Math.max(...samples.map((s) => s.cls)).toFixed(3);
  console.log(`${path}: median of ${runs}: FCP ${summary.fcp} ms, LCP ${summary.lcp} ms, first example content ${summary.example} ms; worst CLS ${cls}`);
}
await browser.close();
