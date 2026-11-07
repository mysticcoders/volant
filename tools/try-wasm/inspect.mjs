// Prints a WebAssembly module's size, imports, exports and memory limits.
// Usage: node tools/try-wasm/inspect.mjs <file.wasm>
import fs from 'node:fs';

const bytes = fs.readFileSync(process.argv[2]);
const module = new WebAssembly.Module(bytes);
console.log('bytes', bytes.length);
console.log('imports', WebAssembly.Module.imports(module).map((i) => `${i.module}.${i.name}`).join(' '));
console.log('exports', WebAssembly.Module.exports(module).map((e) => `${e.name}:${e.kind}`).join(' '));
