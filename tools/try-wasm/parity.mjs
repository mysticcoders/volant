// Compares two builds of the calculator module query by query: same clock, zone, locale and the same
// exchange-rate bodies, so any difference comes from the build (ICU data trimming, wasm-opt).
// Feeds are fetched once from the app's fixed URLs and cached in out/feeds.json.
// Usage: node tools/try-wasm/parity.mjs <reference.wasm> <candidate.wasm> <queries.txt>
import fs from 'node:fs';
import path from 'node:path';
import { answer } from '../../website/public/try/calculator.js';

const [referenceFile, candidateFile, queriesFile] = process.argv.slice(2);
const cache = path.join(path.dirname(new URL(import.meta.url).pathname), 'out', 'feeds.json');
const upstream = {
  ecb: 'https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml',
  world: 'https://open.er-api.com/v6/latest/EUR',
  crypto: 'https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum,solana,ripple,binancecoin,cardano,dogecoin,tether,usd-coin,litecoin,polkadot,tron&vs_currencies=eur',
};

/** The three feed bodies, fetched once and reused so both builds see identical rates. */
async function feeds() {
  if (fs.existsSync(cache)) return JSON.parse(fs.readFileSync(cache, 'utf8'));
  const out = { fetchedAt: Math.floor(Date.now() / 1000) };
  for (const [name, url] of Object.entries(upstream)) out[name] = await (await fetch(url, { redirect: 'manual' })).text();
  fs.mkdirSync(path.dirname(cache), { recursive: true });
  fs.writeFileSync(cache, JSON.stringify(out));
  return out;
}

/** Every answer a build gives for each query, with rates attached when the query needs them. */
function run(file, queries, rates) {
  const compiled = new WebAssembly.Module(fs.readFileSync(file));
  const base = { now: 1794040200, zone: 'America/Los_Angeles', locale: 'en_US' };
  return queries.map((query) => {
    try {
      const needs = JSON.parse(answer(compiled, JSON.stringify({ ...base, mode: 'feeds', query })));
      const request = { ...base, query };
      if (needs.rates) request.ecb = rates.ecb;
      if (needs.world) request.world = rates.world;
      if (needs.crypto) { request.crypto = rates.crypto; request.cryptoFetchedAt = rates.fetchedAt; }
      return JSON.parse(answer(compiled, JSON.stringify(request))).map((a) => [a.result, a.resultDetail, a.inputDetail].join(' | ')).join(' || ') || '(no answer)';
    } catch (error) {
      return `ERROR ${error.message}`;
    }
  });
}

const queries = fs.readFileSync(queriesFile, 'utf8').split('\n').map((q) => q.trim()).filter(Boolean);
const rates = await feeds();
const reference = run(referenceFile, queries, rates);
const candidate = run(candidateFile, queries, rates);
let same = 0;
queries.forEach((query, i) => {
  if (reference[i] === candidate[i]) same += 1;
  else console.log(`DIFF ${query}\n  reference: ${reference[i]}\n  candidate: ${candidate[i]}`);
});
const answered = reference.filter((r) => r !== '(no answer)' && !r.startsWith('ERROR')).length;
console.log(`${same}/${queries.length} identical (${answered} answered by the reference)`);
process.exitCode = same === queries.length ? 0 : 1;
