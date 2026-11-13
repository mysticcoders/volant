// Checks the homepage hero's replay in headless Chromium against a local build: first paint shows
// only the prompt, the replayed frames match lib/try-hero-examples.json keystroke by keystroke,
// the recorded final answers match what /try shows for the same text, focus/click/typing hand over
// to /try, reduced motion shows one recorded example, the homepage makes no WebAssembly or rates
// requests, and the replay keeps its timing: 90–150 ms keystrokes, about 250 ms after a space, 0.7 s
// before Return, 3.75 s holds (5 s for the extension) plus a 0.3 s fade, and 1.35 s on the prompt.
// Saves light, dark and mobile screenshots at first paint, mid-typing and inside the extension as PNG.
// Usage (from website/, with the site served): node scripts/try-hero-check.mjs http://127.0.0.1:8811 <out-dir>
import fs from 'node:fs';
import { mkdir } from 'node:fs/promises';
import { chromium } from 'playwright';

const [base, out] = process.argv.slice(2);
await mkdir(out, { recursive: true });
const capture = JSON.parse(fs.readFileSync(new URL('../lib/try-hero-examples.json', import.meta.url), 'utf8'));
const browser = await chromium.launch({ headless: true });
const failures = [];
const results = {};

/** Records a failed expectation without stopping the run. */
function expect(ok, message) {
  if (!ok) failures.push(message);
}

/** The text a recorded row draws, in the order the hero renders it. */
function rowText(index) {
  const row = capture.rows[index];
  const ext = row.e ? capture.extensions[row.e] : undefined;
  if (row.r !== undefined) return [row.r, row.s, row.k].join('');
  if (row.t) return [row.t, row.s, ...(row.b ?? [])].join('');
  return [ext.name, ext.placeholder, ext.kind].join('');
}

/** Watches the hero from the first script run, logging each distinct field text and row list with
 * its time, plus every request the page makes. */
async function watched(context, path) {
  const page = await context.newPage();
  const requests = [];
  const problems = [];
  page.on('request', (r) => requests.push(r.url()));
  page.on('pageerror', (e) => problems.push(String(e)));
  page.on('console', (m) => { if (m.type() === 'error') problems.push(m.text()); });
  await page.addInitScript(() => {
    window.__heroLog = [];
    /** Appends the hero's current field text and rows when they change. */
    const sample = () => {
      const card = document.querySelector('.hero-launcher');
      if (card) {
        const ghost = card.querySelector('.hero-live .hero-ghost-text');
        const chip = card.querySelector('.hero-live .try-chip');
        const text = ghost ? (ghost.querySelector('.hero-placeholder') ? '' : ghost.textContent) : null;
        const rows = [...card.querySelectorAll('.hero-live .try-row')].map((r) => r.textContent);
        const selected = [...card.querySelectorAll('.hero-live .try-row')].findIndex((r) => r.getAttribute('aria-current') === 'true');
        const entry = { text, scope: chip ? chip.textContent.replace('‹', '') : null, rows, selected, t: performance.now() };
        const last = window.__heroLog[window.__heroLog.length - 1];
        if (!last || last.text !== entry.text || last.scope !== entry.scope || JSON.stringify(last.rows) !== JSON.stringify(entry.rows)) window.__heroLog.push(entry);
      }
      requestAnimationFrame(sample);
    };
    requestAnimationFrame(sample);
    addEventListener('load', () => { window.__heroLoad = performance.now(); });
  });
  await page.goto(`${base}${path}`, { waitUntil: 'load' });
  return { page, requests, problems };
}

/** Checks one full replay cycle against the recorded frames and grabs a mid-typing screenshot. */
async function replayRun(scheme, viewport, label, path) {
  const context = await browser.newContext({ colorScheme: scheme, viewport, deviceScaleFactor: 2 });
  const { page, requests, problems } = await watched(context, path);
  await page.waitForFunction(() => window.__heroLog.some((e) => e.scope), null, { timeout: 30000 });
  await page.waitForTimeout(400);
  await page.locator('.hero-launcher').screenshot({ path: `${out}/hero-${label}-extension.png` });
  await page.waitForFunction(() => document.querySelector('.hero-live .hero-ghost-text')?.textContent === '15% of 8', null, { timeout: 60000 });
  await page.locator('.hero-launcher').screenshot({ path: `${out}/hero-${label}-typing.png` });
  const last = capture.examples[capture.examples.length - 1];
  await page.waitForFunction((final) => {
    const log = window.__heroLog;
    const at = log.findIndex((e) => e.text === final);
    return at >= 0 && log.slice(at + 1).some((e) => e.text === null);
  }, last.query, { timeout: 60000 });
  const log = await page.evaluate(() => window.__heroLog);
  const load = await page.evaluate(() => window.__heroLoad);
  expect(log[0].text === null && log[0].rows.length === 0, `${label}: first paint was not prompt-only: ${JSON.stringify(log[0])}`);
  const typed = log.filter((e) => e.text !== null || e.scope);
  const firstChar = typed[0]?.t ?? Infinity;
  results[`${label} first character`] = `${Math.round(firstChar - load)} ms after load (${Math.round(firstChar)} ms after navigation start)`;
  expect(firstChar - load < 400, `${label}: first character ${Math.round(firstChar - load)} ms after load`);
  const expected = capture.examples.flatMap((example, e) => example.frames.map(([text, rows, scope], f) => ({
    text: scope ? '' : text, scope: scope ? capture.extensions[scope].name : null, rows: rows.map(rowText),
    example: e, last: f === example.frames.length - 1, nextText: example.frames[f + 1]?.[0], nextScope: !!example.frames[f + 1]?.[2],
  })));
  let matched = 0;
  const timings = { keystroke: [], afterSpace: [], beforeReturn: [], hold: [], extensionHold: [], rest: [] };
  const start = log.indexOf(typed[0]);
  for (let i = start; i < log.length && matched < expected.length; i++) {
    const entry = log[i];
    const following = log[i + 1];
    if (entry.text === null && !entry.scope) {
      if (following) timings.rest.push(following.t - entry.t);
      continue;
    }
    const frame = expected[matched];
    const same = entry.text === frame.text && entry.scope === frame.scope && JSON.stringify(entry.rows) === JSON.stringify(frame.rows) && entry.selected === (frame.rows.length ? 0 : -1);
    expect(same, `${label}: frame ${matched} shown ${JSON.stringify(entry)} expected ${JSON.stringify(frame)}`);
    if (!same) break;
    matched += 1;
    if (!following) continue;
    const gap = following.t - entry.t;
    if (frame.last) (frame.scope ? timings.extensionHold : timings.hold).push(gap);
    else if (frame.nextScope) timings.beforeReturn.push(gap);
    else if (frame.nextText.length - frame.text.length === 1) (frame.text.endsWith(' ') ? timings.afterSpace : timings.keystroke).push(gap);
  }
  expect(matched === expected.length, `${label}: replayed ${matched} of ${expected.length} frames`);
  const within = (name, low, high) => {
    const list = timings[name];
    expect(list.length > 0 && list.every((g) => g >= low && g <= high), `${label}: ${name} gaps ${list.map(Math.round).join(', ')} outside ${low}–${high} ms`);
    return `${name} ${Math.round(Math.min(...list))}–${Math.round(Math.max(...list))}`;
  };
  results[`${label} frames`] = `${matched}/${expected.length} matched; ms: ${[
    within('keystroke', 70, 185), within('afterSpace', 220, 305), within('beforeReturn', 650, 800),
    within('hold', 3900, 4250), within('extensionHold', 5150, 5500), within('rest', 1300, 1450),
  ].join(', ')} (holds include the 300 ms fade)`;
  const clears = log.filter((e, i) => i > 0 && e.text === null);
  expect(clears.every((e) => e.rows.length === 0), `${label}: a cleared frame still showed rows`);
  const bad = requests.filter((u) => /\.wasm|\/try\/rates|calculator|samples\.json|manifest\.json/.test(u));
  expect(bad.length === 0, `${label}: homepage requested ${bad.join(', ')}`);
  results[`${label} same-origin requests after load`] = [...new Set(requests.filter((u) => u.startsWith(base) && /\.(webp|png|svg)/.test(u)).map((u) => u.slice(base.length)))].join(', ');
  expect(problems.length === 0, `${label}: console problems ${problems.join(' | ')}`);
  await context.close();
}

/** Screenshots the server-rendered card with JavaScript off, which is what first paint shows. */
async function firstPaintRun(scheme, viewport, label, path) {
  const context = await browser.newContext({ colorScheme: scheme, viewport, deviceScaleFactor: 2, javaScriptEnabled: false });
  const page = await context.newPage();
  await page.goto(`${base}${path}`, { waitUntil: 'load' });
  const rows = await page.locator('.hero-live .try-row').count();
  const ghost = await page.locator('.hero-ghost').count();
  expect(rows === 0 && ghost === 0, `${label}: first paint showed ${rows} rows`);
  await page.locator('.hero-launcher').screenshot({ path: `${out}/hero-${label}-first-paint.png` });
  await context.close();
}

/** Checks focus stops and clears the replay without leaving, then a keystroke hands over with it,
 * and a click on the card opens /try. */
async function handOffRun(path, label) {
  const context = await browser.newContext({ viewport: { width: 1280, height: 900 } });
  const { page } = await watched(context, path);
  await page.waitForFunction(() => document.querySelector('.hero-live .hero-ghost-text'), null, { timeout: 15000 });
  await page.locator('.hero-launcher input').focus();
  await page.waitForTimeout(600);
  const cleared = await page.evaluate(() => ({ ghost: !!document.querySelector('.hero-live .hero-ghost'), rows: document.querySelectorAll('.hero-live .try-row').length, url: location.pathname }));
  expect(!cleared.ghost && cleared.rows === 0 && cleared.url === '/', `${label}: focus did not stop and clear: ${JSON.stringify(cleared)}`);
  await page.keyboard.type('5');
  await page.waitForURL('**/try?q=5', { timeout: 15000 });
  results[`${label} focus then type`] = page.url().slice(base.length);
  await page.goto(`${base}${path}`, { waitUntil: 'load' });
  await page.locator('.hero-launcher .hero-results').first().click();
  await page.waitForURL('**/try', { timeout: 15000 });
  results[`${label} click`] = page.url().slice(base.length);
  await context.close();
}

/** Under reduced motion: nothing is typed and one example's final frame shows with its caption. */
async function reducedRun(scheme, viewport, label, path) {
  const context = await browser.newContext({ colorScheme: scheme, viewport, deviceScaleFactor: 2, reducedMotion: 'reduce' });
  const { page } = await watched(context, path);
  await page.waitForTimeout(2500);
  const log = await page.evaluate(() => window.__heroLog);
  expect(log.every((e) => e.text === null), `${label}: reduced motion still typed`);
  const caption = await page.locator('.hero-static-caption').textContent();
  const shown = await page.locator('.hero-static .try-row').allTextContents();
  expect(await page.locator('.hero-static').isVisible(), `${label}: static example hidden`);
  results[`${label} reduced motion`] = `${caption} → ${shown.join(' | ')}`;
  await page.locator('.hero-launcher').screenshot({ path: `${out}/hero-${label}-reduced.png` });
  await context.close();
}

/** Compares each example's recorded final frame with what /try shows for the same text. */
async function tryMatchRun() {
  const context = await browser.newContext({ viewport: { width: 1280, height: 900 }, timezoneId: capture.zone, locale: 'en-US' });
  const page = await context.newPage();
  for (const example of capture.examples) {
    const [text, rows, scope] = example.frames[example.frames.length - 1];
    await page.goto(`${base}/try?q=${encodeURIComponent(example.query)}`, { waitUntil: 'networkidle' });
    if (scope) {
      await page.locator('.try-row').first().waitFor({ timeout: 30000 });
      await page.locator('.try-bar input').press('Enter');
      await page.locator('.try-chip').waitFor({ timeout: 15000 });
      await page.waitForFunction(() => document.querySelectorAll('.try-results .try-row').length >= 4, null, { timeout: 30000 });
      const titles = (await page.locator('.try-results .try-title').allTextContents()).slice(0, rows.length);
      const recorded = rows.map((i) => capture.rows[i].t);
      expect(JSON.stringify(titles) === JSON.stringify(recorded), `/try ${example.query} ↩ rows ${JSON.stringify(titles)} vs recorded ${JSON.stringify(recorded)}`);
      results[`/try ${example.query} ↩`] = titles.join(' | ');
    } else {
      await page.locator('.try-answer').first().waitFor({ timeout: 180000 });
      const live = await page.locator('.try-answer-result').allTextContents();
      const recorded = rows.filter((i) => capture.rows[i].r !== undefined).map((i) => capture.rows[i].r);
      expect(JSON.stringify(live) === JSON.stringify(recorded), `/try ${text}: ${JSON.stringify(live)} vs recorded ${JSON.stringify(recorded)}`);
      results[`/try ${text}`] = `${live.join(' | ')} (recorded ${recorded.join(' | ')})`;
    }
  }
  await context.close();
}

const desktop = { width: 1280, height: 900 };
const phone = { width: 390, height: 844 };
for (const [prefix, path] of [['home', '/']]) {
  await firstPaintRun('light', desktop, `${prefix}-light`, path);
  await firstPaintRun('dark', desktop, `${prefix}-dark`, path);
  await firstPaintRun('light', phone, `${prefix}-mobile`, path);
  await replayRun('light', desktop, `${prefix}-light`, path);
  await replayRun('dark', desktop, `${prefix}-dark`, path);
  await replayRun('light', phone, `${prefix}-mobile`, path);
  await reducedRun('light', desktop, `${prefix}-light`, path);
  await handOffRun(path, prefix);
}
await tryMatchRun();
await browser.close();
console.log(JSON.stringify(results, null, 2));
if (failures.length) {
  console.log(`FAILURES:\n${failures.join('\n')}`);
  process.exit(1);
}
console.log('All hero checks passed.');
