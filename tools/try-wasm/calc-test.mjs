// Runs the browser calculator shim under Node against the built module and prints each query's
// answers and timing. Usage: node tools/try-wasm/calc-test.mjs <VolantAnswers.wasm> [query ...]
import fs from 'node:fs';
import { answer } from '../../website/public/try/calculator.js';

const [file, ...extra] = process.argv.slice(2);
let started = performance.now();
const compiled = new WebAssembly.Module(fs.readFileSync(file));
console.log(`compile ${Math.round(performance.now() - started)} ms`);
const fromFile = extra[0] === '--file' ? fs.readFileSync(extra[1], 'utf8').split('\n').filter(Boolean) : null;
const plain = extra.includes('--plain');
const queries = fromFile ?? (extra.length ? extra : ['2+2', '15% of 80', '5 km in miles', '3pm tokyo in new york', 'now in london', '100 usd in eur',
  'sqrt(2)', '0xff in decimal', '#ff8800 in rgb', 'days until christmas', '3 cups flour in grams', '1/3 + 1/6', '72f in c', '1000 days from today']);
const now = Math.floor(Date.parse('2026-11-07T08:30:00Z') / 1000);
for (const query of queries) {
  started = performance.now();
  const diagnostics = [];
  try {
    const reply = answer(compiled, JSON.stringify({ query, now, zone: 'America/Los_Angeles', locale: 'en_US' }), diagnostics);
    const answers = JSON.parse(reply);
    const text = answers.length ? answers.map((a) => `${a.result}${a.resultDetail ? ` [${a.resultDetail}]` : ''}`).join(' | ') : '(no answer)';
    console.log(plain ? `${query}: ${text}` : `${query} (${Math.round(performance.now() - started)} ms): ${text}`);
  } catch (error) {
    console.log(`${query}: ERROR ${error.message} ${diagnostics.join('').slice(0, 600)}`);
  }
}
