// Attributes a WebAssembly module's code size to libraries by function name (from the name section
// of an unstripped build): Swift stdlib, FoundationEssentials, FoundationInternationalization,
// Foundation, FoundationNetworking, FoundationXML/libxml2, CoreFoundation, ICU, the calculator.
// Usage: node tools/try-wasm/code-size.mjs <unstripped.wasm>
import fs from 'node:fs';

const bytes = fs.readFileSync(process.argv[2]);

/** Reads an unsigned LEB128 number at `state.at`. */
function leb(state) {
  let value = 0, shift = 0, byte;
  do {
    byte = bytes[state.at++];
    value += (byte & 0x7f) * 2 ** shift;
    shift += 7;
  } while (byte & 0x80);
  return value;
}

const state = { at: 8 };
let imports = 0;
const bodies = [];
const names = new Map();
while (state.at < bytes.length) {
  const id = bytes[state.at++];
  const size = leb(state);
  const end = state.at + size;
  if (id === 2) {
    const count = leb(state);
    for (let i = 0; i < count; i++) {
      for (let s = 0; s < 2; s++) state.at += leb(state);
      const kind = bytes[state.at++];
      if (kind === 0) { leb(state); imports++; } else if (kind === 1) { state.at++; const f = leb(state); leb(state); if (f & 1) leb(state); } else if (kind === 2) { const f = leb(state); leb(state); if (f & 1) leb(state); } else { state.at += 2; }
    }
  } else if (id === 10) {
    const count = leb(state);
    for (let i = 0; i < count; i++) { const length = leb(state); bodies.push(length); state.at += length; }
  } else if (id === 0) {
    const nameLength = leb(state);
    const name = bytes.toString('utf8', state.at, state.at + nameLength);
    state.at += nameLength;
    if (name === 'name') {
      while (state.at < end) {
        const sub = bytes[state.at++];
        const subSize = leb(state);
        const subEnd = state.at + subSize;
        if (sub === 1) {
          const count = leb(state);
          for (let i = 0; i < count; i++) { const index = leb(state); const len = leb(state); names.set(index, bytes.toString('utf8', state.at, state.at + len)); state.at += len; }
        }
        state.at = subEnd;
      }
    }
  }
  state.at = end;
}

/** The library a function name belongs to. */
function library(name = '') {
  const rules = [
    [/^\$s20FoundationNetworking|^\$s\d*FoundationNetworking|URLSession|_CFURLSession|curl_/, 'FoundationNetworking'],
    [/^\$s13FoundationXML|^xml|^html|^xsl|^__xml/, 'FoundationXML + libxml2'],
    [/^\$s28FoundationInternationalization/, 'FoundationInternationalization'],
    [/^\$s20FoundationEssentials/, 'FoundationEssentials'],
    [/^\$s10Foundation/, 'Foundation'],
    [/^\$s10VolantCalc|^\$s13VolantAnswers/, 'VolantCalc (calculator)'],
    [/^\$s(s|S)|^swift_|^\$ss/, 'Swift stdlib/runtime'],
    [/icu_?\d*|^u_|^ucol|^ubrk|^unum|^udat|^ucal|^ures|^uloc|^ucnv|^utrans|^uregex|^usearch|^unorm/, 'ICU'],
    [/^_?CF|^__CF/, 'CoreFoundation'],
    [/^\$s/, 'Swift (other modules)'],
  ];
  for (const [pattern, label] of rules) if (pattern.test(name)) return label;
  return 'C/libc/other';
}

const totals = {};
bodies.forEach((size, i) => { const label = library(names.get(imports + i)); totals[label] = (totals[label] ?? 0) + size; });
const sum = bodies.reduce((a, b) => a + b, 0);
console.log(`code ${(sum / 1e6).toFixed(2)} MB in ${bodies.length} functions (${names.size} named)`);
const detail = process.argv[3];
if (detail) {
  const groups = {};
  bodies.forEach((size, i) => {
    const name = names.get(imports + i) ?? '';
    if (library(name) !== detail) return;
    const key = name.startsWith('$s') ? (name.match(/^\$s(\d+)/) ? name.slice(2).replace(/^(\d+)(.*)/, (m, n, rest) => rest.slice(0, Number(n))) : name.slice(0, 12)) : name.replace(/[^A-Za-z].*/, '').slice(0, 12) || name.slice(0, 8);
    groups[key] = (groups[key] ?? 0) + size;
  });
  for (const [key, size] of Object.entries(groups).sort((a, b) => b[1] - a[1]).slice(0, 15)) console.log(`  ${(size / 1e3).toFixed(0).padStart(6)} KB  ${key}`);
}
for (const [label, size] of Object.entries(totals).sort((a, b) => b[1] - a[1])) console.log(`${(size / 1e6).toFixed(2).padStart(6)} MB  ${label}`);
