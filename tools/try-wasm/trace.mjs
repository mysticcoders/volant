// Runs one calculator query (with the cached feeds from parity.mjs) and prints the WebAssembly
// stack and stderr if it traps, for diagnosing a build. Usage: node trace.mjs <module.wasm> "<query>"
import fs from 'node:fs';
import { answer } from '../../website/public/try/calculator.js';

const [file, query] = process.argv.slice(2);
const rates = JSON.parse(fs.readFileSync(new URL('out/feeds.json', import.meta.url), 'utf8'));
const compiled = new WebAssembly.Module(fs.readFileSync(file));
const diagnostics = [];
try {
  console.log(answer(compiled, JSON.stringify({ query, now: 1794040200, zone: 'America/Los_Angeles', locale: 'en_US', ecb: rates.ecb, world: rates.world, crypto: rates.crypto, cryptoFetchedAt: rates.fetchedAt }), diagnostics));
} catch (error) {
  console.log(diagnostics.join(''));
  console.log(error.stack.split('\n').filter((line) => line.includes('wasm-function')).slice(0, 14).map((line) => line.trim().slice(0, 170)).join('\n'));
}
