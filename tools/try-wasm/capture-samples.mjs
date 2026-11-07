// Records the sample data the "Try Volant" spike serves to network extensions. Each extension
// plans its own URLs with a pinned clock; this fetches exactly those URLs once, at most 512 KB
// each and without redirects, and saves the responses with the capture time. The browser then
// replays them for the same plans, labeled as sample data. Run from the repo root.
import fs from 'node:fs';
import { runModule, runCommand } from '../../website/public/try/host.js';

const dir = 'website/public/try/extensions';
const now = Math.floor(Date.now() / 1000);
const cases = [
  { name: 'hackernews', abi: 1, runs: [null, 'top', 'new', 'ask', 'show'].map((filter) => ({ query: '', filter })) },
  { name: 'lobsters', abi: 1, runs: [{ query: '' }] },
  { name: 'wikipedia', abi: 2, runs: ['WebAssembly', 'Swift (programming language)', 'macOS', 'Raycast'].map((query) => ({ query })) },
];

/** Calls a module's plan phase with the pinned clock and returns the URLs it asks for. */
function plan(name, abi, run) {
  const manifest = JSON.parse(fs.readFileSync(`${dir}/${name}/manifest.json`, 'utf8'));
  const bytes = new Uint8Array(fs.readFileSync(`${dir}/${name}/${manifest.module}`));
  const request = JSON.stringify({ phase: 'plan', query: run.query, now, units: 'us', ...(run.filter ? { filter: run.filter } : {}) });
  const reply = JSON.parse(abi === 2 ? runCommand(bytes, request) : runModule(bytes, [], request));
  return reply.fetch ?? [];
}

/** Fetches one URL without following redirects, keeping at most 512 KB of its body. */
async function fetchOnce(url) {
  const response = await fetch(url, { redirect: 'manual', headers: { 'User-Agent': 'Volant try-spike sample capture' } });
  const body = (await response.text()).slice(0, 512 * 1024);
  return { status: response.status, body };
}

const samples = { capturedAt: new Date(now * 1000).toISOString(), now, responses: {} };
for (const { name, abi, runs } of cases) {
  for (const run of runs) {
    for (const url of plan(name, abi, run)) {
      if (samples.responses[url]) continue;
      samples.responses[url] = await fetchOnce(url);
      console.log(samples.responses[url].status, samples.responses[url].body.length, url);
    }
  }
}
fs.writeFileSync('website/public/try/samples.json', JSON.stringify(samples));
console.log('captured at', samples.capturedAt);
