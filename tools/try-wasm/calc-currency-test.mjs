// Checks currency answers in the WASI calculator: asks VolantCore which feeds each query needs,
// fetches only those (from a running site's /try/rates routes when a base URL is given, otherwise
// once from the providers), and passes the raw bodies into the module.
// Usage: node tools/try-wasm/calc-currency-test.mjs <VolantAnswers.wasm> [site base URL]
import fs from 'node:fs';
import { answer } from '../../website/public/try/calculator.js';

const [file, site] = process.argv.slice(2);
const compiled = new WebAssembly.Module(fs.readFileSync(file));
const upstream = {
  ecb: 'https://www.ecb.europa.eu/stats/eurofxref/eurofxref-daily.xml',
  world: 'https://open.er-api.com/v6/latest/EUR',
  crypto: 'https://api.coingecko.com/api/v3/simple/price?ids=bitcoin,ethereum,solana,ripple,binancecoin,cardano,dogecoin,tether,usd-coin,litecoin,polkadot,tron&vs_currencies=eur',
};
const fetched = {};

/** Returns one feed's body and fetch time, fetching it at most once. */
async function feed(name) {
  if (!fetched[name]) {
    const response = await fetch(site ? `${site}/try/rates/${name}` : upstream[name], { redirect: 'manual' });
    if (response.status !== 200) throw new Error(`${name} ${response.status}`);
    fetched[name] = { body: await response.text(), at: Number(response.headers.get('x-volant-fetched-at')) || Math.floor(Date.now() / 1000) };
    console.log(`fetched ${name} (${fetched[name].body.length} bytes)`);
  }
  return fetched[name];
}

const now = Math.floor(Date.now() / 1000);
const base = { now, zone: 'America/Los_Angeles', locale: 'en_US' };
for (const query of ['100 usd in eur', '50 gbp to jpy', '1000 aed in usd', '0.5 btc in usd', '2+2', '5 km in miles']) {
  const needs = JSON.parse(answer(compiled, JSON.stringify({ ...base, mode: 'feeds', query })));
  const request = { ...base, query };
  if (needs.rates) request.ecb = (await feed('ecb')).body;
  if (needs.world) request.world = (await feed('world')).body;
  if (needs.crypto) { const c = await feed('crypto'); request.crypto = c.body; request.cryptoFetchedAt = c.at; }
  const answers = JSON.parse(answer(compiled, JSON.stringify(request)));
  console.log(`${query} needs ${JSON.stringify(needs)} →`, answers.map((a) => `${a.result} [${a.inputDetail ?? ''} · ${a.resultDetail ?? ''}]`).join(' | ') || '(no answer)');
}
