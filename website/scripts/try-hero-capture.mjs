// Captures the homepage hero's example answers from the code /try runs: VolantCore's calculator
// module and the Hacker News extension with /try's recorded sample data, and writes
// lib/try-hero-examples.json with the capture date. It runs in every website build (prebuild), so
// the examples refresh whenever the site is published; the hero itself computes nothing.
//
// Text that depends on the day it was captured ("Saturday, November 7 · Today", "19h ago") is left
// out, so a saved example never shows a stale date.
//
// The module is the one public/try/calculator.json names: tools/try-wasm/out/<file> when it was
// built here, otherwise its gzip copy from the volant-try R2 bucket. If neither is reachable, the
// existing fixture is kept and the build continues.
// Usage: node scripts/try-hero-capture.mjs [VolantAnswers-….wasm]
import { execFileSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import zlib from 'node:zlib';
import { answer } from '../public/try/calculator.js';
import { runModule } from '../public/try/host.js';

const site = new URL('../', import.meta.url);
const fixtureFile = new URL('lib/try-hero-examples.json', site);

/** The calculator module's bytes: an explicit file, a local build, or the published copy in R2. */
function moduleBytes() {
  if (process.argv[2]) return fs.readFileSync(process.argv[2]);
  const { file } = JSON.parse(fs.readFileSync(new URL('public/try/calculator.json', site), 'utf8'));
  const local = new URL(`../tools/try-wasm/out/${file}`, site);
  if (fs.existsSync(local)) return fs.readFileSync(local);
  const download = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'try-hero-')), `${file}.gz`);
  execFileSync('npx', ['--no-install', 'wrangler', 'r2', 'object', 'get', `volant-try/${file}.gz`, '--file', download, '--remote'],
    { cwd: new URL('.', site), stdio: 'ignore', timeout: 120000 });
  return zlib.gunzipSync(fs.readFileSync(download));
}

const dated = /\b(Today|Tomorrow|Yesterday|Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday|January|February|March|April|May|June|July|August|September|October|November|December|ago|from now)\b/;

/** Joins detail parts, leaving out any that depend on the capture date. */
function undated(parts) {
  return parts.filter((part) => part && !dated.test(part)).join(' · ');
}

let compiled;
try {
  compiled = new WebAssembly.Module(moduleBytes());
} catch (error) {
  console.warn(`try-hero-capture: calculator module unavailable (${error.message.split('\n')[0]}); keeping the existing hero examples.`);
  process.exit(0);
}
const now = Math.floor(Date.now() / 1000);
const zone = 'America/New_York';

/** The calculator's first answer for a query, as /try shows it, without date-relative detail. */
function calculate(query) {
  const [first] = JSON.parse(answer(compiled, JSON.stringify({ query, now, zone, locale: 'en_US' })));
  if (!first) throw new Error(`No answer for ${query}`);
  return { query, kind: 'answer', result: first.result, detail: undated([first.inputDetail, first.resultDetail]) };
}

/** The first rows of an extension's list from /try's recorded sample data, without relative times. */
function extensionRows(query, folder, count) {
  const manifest = JSON.parse(fs.readFileSync(new URL(`public/try/extensions/${folder}/manifest.json`, site), 'utf8'));
  const bytes = new Uint8Array(fs.readFileSync(new URL(`public/try/extensions/${folder}/${manifest.module}`, site)));
  const samples = JSON.parse(fs.readFileSync(new URL('public/try/samples.json', site), 'utf8'));
  const base = { query: '', now: samples.now, units: 'us' };
  const plan = JSON.parse(runModule(bytes, [], JSON.stringify({ phase: 'plan', ...base })));
  const responses = plan.fetch.map((url) => ({ url, status: samples.responses[url]?.status ?? 0, body: samples.responses[url]?.body ?? '' }));
  const rendered = JSON.parse(runModule(bytes, [], JSON.stringify({ phase: 'render', ...base, responses })));
  return {
    query, kind: 'rows', extension: manifest.name, icon: `/try/extensions/${folder}/${manifest.icon}`, sampleDate: samples.capturedAt,
    rows: rendered.items.slice(0, count).map((row) => ({ title: row.title, subtitle: undated((row.subtitle ?? '').split(' · ')) })),
  };
}

const fixture = {
  capturedAt: new Date(now * 1000).toISOString(),
  zone,
  examples: [calculate('3pm tokyo in new york'), calculate('15% of 80'), extensionRows('hn', 'hackernews', 3)],
};
fs.writeFileSync(fixtureFile, `${JSON.stringify(fixture, null, 2)}\n`);
console.log(`try-hero-capture: ${fixture.examples.map((e) => e.result ?? `${e.rows.length} rows`).join(', ')}`);
