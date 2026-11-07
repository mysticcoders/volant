// Checks the browser extension host (website/public/try/host.js) under Node against the real
// modules the spike ships: ABI 1 text and list replies, an ABI 2 command, a plan, and the refusals.
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { runModule, runCommand, validateModule } from '../../website/public/try/host.js';

const dir = 'website/public/try/extensions';
const bytes = (name, file) => new Uint8Array(fs.readFileSync(`${dir}/${name}/${file}`));

assert.equal(runModule(bytes('hello', 'hello.wasm'), [], 'Andrew'), 'Hello, Andrew!');

const cased = JSON.parse(runModule(bytes('case', 'case.wasm'), [], JSON.stringify({ phase: 'render', query: 'try volant', now: 0, units: 'us' })));
assert.ok(cased.items.some((item) => item.title === 'tryVolant'));

const plan = JSON.parse(runModule(bytes('hackernews', 'hackernews.wasm'), [], JSON.stringify({ phase: 'plan', query: '', now: 0, units: 'us' })));
assert.ok(plan.fetch[0].startsWith('https://hn.algolia.com/'));

const wiki = JSON.parse(runCommand(bytes('wikipedia', 'wikipedia.wasm'), JSON.stringify({ phase: 'plan', query: 'WebAssembly', now: 0, units: 'us' })));
assert.ok(wiki.fetch[0].startsWith('https://en.wikipedia.org/'));
console.log('wikipedia plan', wiki.fetch[0]);

assert.throws(() => validateModule(new Uint8Array([0, 97, 115, 109, 1, 0, 0, 0])), /Invalid module memory/);
assert.throws(() => runModule(bytes('hello', 'hello.wasm'), [], 'x'.repeat(1024 * 1024 + 1)), /Invalid extension request/);
console.log('host checks passed');
