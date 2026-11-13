// Records the homepage hero's typing examples keystroke by keystroke from the code /try runs:
// VolantCore's calculator module, the demo's extension command list (lib/try-extensions.json) and
// the Hacker News extension with /try's recorded sample data. For every prefix the hero types it
// stores what /try shows for that text: the calculator's answers, then the matching extension
// commands, first row selected, or nothing when nothing matches. It writes
// lib/try-hero-examples.json with the capture date. It runs in every website build (prebuild), so
// the frames refresh whenever the site is published; the hero itself computes nothing.
//
// Text that depends on the day it was captured ("Sunday, November 8", "Tomorrow", "19h ago") is
// left out, so a recorded frame never shows a stale date. No result text is written by hand.
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
const shipped = JSON.parse(fs.readFileSync(new URL('lib/try-extensions.json', site), 'utf8'));
const samples = JSON.parse(fs.readFileSync(new URL('public/try/samples.json', site), 'utf8'));
const scopedRows = 4;

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
  return parts.flatMap((part) => (part ?? '').split(' · ')).filter((part) => part && !dated.test(part)).join(' · ');
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
const manifests = Object.fromEntries(shipped.map(({ folder }) =>
  [folder, JSON.parse(fs.readFileSync(new URL(`public/try/extensions/${folder}/manifest.json`, site), 'utf8'))]));

const rows = [];
const rowIndex = new Map();
const used = new Set();

/** The index of a row in the shared row table, adding it the first time it is seen. */
function intern(row) {
  const key = JSON.stringify(row);
  if (!rowIndex.has(key)) { rowIndex.set(key, rows.length); rows.push(row); }
  if (row.e) used.add(row.e);
  return rowIndex.get(key);
}

/** The calculator's answers for typed text, as /try lists them: at most five, result, input line
 * and tag, without date-relative detail. */
function answers(typed) {
  const list = JSON.parse(answer(compiled, JSON.stringify({ query: typed, now, zone, locale: 'en_US' }))).slice(0, 5);
  return list.map((a) => ({ r: a.result, s: undated([a.input, a.inputDetail]), k: undated([a.resultDetail]) }));
}

/** The extension commands /try lists for typed text, in its order and with its match rule. */
function commands(typed) {
  const words = typed.toLowerCase();
  return shipped.filter(({ folder, keywords }) => manifests[folder].name.toLowerCase().includes(words)
    || keywords.some((k) => k.startsWith(words) || words.startsWith(`${k} `))).map(({ folder }) => ({ e: folder }));
}

/** What /try shows at the top level for this field text: row indexes, first one selected. */
function topLevel(text) {
  const typed = text.trim();
  if (!typed) return [];
  return [...answers(typed), ...commands(typed)].map(intern);
}

/** Runs a list extension the way /try does on entering it (first filter, default preferences,
 * empty query), replaying /try's recorded responses, and returns its first rows. */
function enterExtension(folder) {
  const manifest = manifests[folder];
  const bytes = new Uint8Array(fs.readFileSync(new URL(`public/try/extensions/${folder}/${manifest.module}`, site)));
  const hosts = manifest.hosts ?? [];
  const preferences = Object.fromEntries((manifest.preferences ?? []).filter((p) => p.default !== undefined).map((p) => [p.id, p.default]));
  const base = {
    query: '', now: hosts.length ? samples.now : now, units: 'us',
    ...(manifest.filters?.[0] ? { filter: manifest.filters[0].id } : {}),
    ...(Object.keys(preferences).length ? { preferences } : {}),
  };
  let reply = JSON.parse(runModule(bytes, [], JSON.stringify({ phase: hosts.length ? 'plan' : 'render', ...base })));
  for (let round = 0; hosts.length && !reply.items && reply.fetch && round < 3; round++) {
    const responses = reply.fetch.slice(0, 4).map((url) => {
      const recorded = samples.responses[url];
      if (!recorded) throw new Error(`Sample data lacks ${url}`);
      return { url, status: recorded.status, body: recorded.body };
    });
    reply = JSON.parse(runModule(bytes, [], JSON.stringify({ phase: 'render', ...base, responses, ...(reply.state ? { state: reply.state } : {}) })));
  }
  if (!Array.isArray(reply.items) || !reply.items.length) throw new Error(`${manifest.name} returned no rows`);
  return reply.items.filter((item) => item && typeof item.title === 'string' && item.title.trim()).slice(0, scopedRows).map((item) => {
    const badges = Array.isArray(item.badges) ? item.badges.slice(0, 3).map((b) => b?.text).filter((t) => typeof t === 'string' && t.trim() && !dated.test(t)) : [];
    return intern({ e: folder, t: item.title.replace(/\s+/g, ' ').slice(0, 200), s: undated([item.subtitle]), ...(badges.length ? { b: badges } : {}) });
  });
}

/** One example: a frame per typed prefix, `[text, rows]`, then for an extension the frame after
 * Return, `['', rows, folder]`. A prefix inside a word whose rows differ from both neighbors while
 * those match each other (a one-keystroke flicker) is typed together with the next character. */
function record(query, enter) {
  const typed = [];
  for (let i = 1; i <= query.length; i++) typed.push([query.slice(0, i), topLevel(query.slice(0, i))]);
  const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
  const frames = typed.filter(([text, shown], i) => {
    if (i === 0 || i === typed.length - 1 || text.endsWith(' ') || query[i + 1] === ' ') return true;
    return !(same(typed[i - 1][1], typed[i + 1][1]) && !same(shown, typed[i - 1][1]));
  });
  if (enter) frames.push(['', enterExtension(enter), enter]);
  return { query, frames };
}

const examples = [record('hn', 'hackernews'), record('3pm tokyo in new york'), record('15% of 80'), record('5 km in miles')];
const extensions = Object.fromEntries([...used].map((folder) => {
  const manifest = manifests[folder];
  return [folder, {
    name: manifest.name,
    placeholder: manifest.placeholder ?? 'Extension',
    kind: (manifest.hosts ?? []).length ? 'Extension · sample data' : 'Extension',
    ...(manifest.icon ? { icon: `/try/extensions/${folder}/${manifest.icon}` } : {}),
  }];
}));
const fixture = { capturedAt: new Date(now * 1000).toISOString(), zone, sampleDate: samples.capturedAt, extensions, rows, examples };
fs.writeFileSync(fixtureFile, `${JSON.stringify(fixture)}\n`);
console.log(`try-hero-capture: ${examples.map((e) => `${e.query} (${e.frames.length} frames)`).join(', ')}; ${rows.length} distinct rows`);
