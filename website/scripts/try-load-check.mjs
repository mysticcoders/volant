// Opens /try in headless Chromium and reports how the calculator module loaded: the response's
// status and encoding, the progress or error label, and any console errors.
// Usage: node scripts/try-load-check.mjs http://127.0.0.1:8799
import { chromium } from 'playwright';

const base = process.argv[2];
const browser = await chromium.launch({ headless: true });
const context = await browser.newContext();
const page = await context.newPage();
const problems = [];
page.on('console', (m) => { if (m.type() === 'error') problems.push(m.text()); });
const cdp = await context.newCDPSession(page);
await cdp.send('Network.enable');
await page.goto(`${base}/try?q=2%2B2`, { waitUntil: 'domcontentloaded' });
const outcome = await Promise.race([
  page.locator('.try-answer').first().waitFor({ timeout: 60000 }).then(async () => `answer ${await page.locator('.try-answer-result').first().textContent()}`),
  page.locator('.try-progress[data-state="error"]').waitFor({ timeout: 60000 }).then(() => 'load error'),
]).catch((error) => `timeout: ${error.message.split('\n')[0]}`);
const calculatorModule = await page.evaluate(async () => {
  const manifest = await (await fetch('/try/calculator.json')).json();
  const response = await fetch(`/try/calculator/${manifest.file}`);
  const bytes = new Uint8Array(await response.arrayBuffer());
  return { status: response.status, encoding: response.headers.get('content-encoding'), first: Array.from(bytes.slice(0, 4)), length: bytes.length, expected: manifest.bytes };
});
console.log(JSON.stringify({ outcome, module: calculatorModule, problems }, null, 1));
await browser.close();
