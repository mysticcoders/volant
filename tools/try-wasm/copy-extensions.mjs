// Copies the extension builds the "Try Volant" spike runs into website/public/try/extensions,
// checking each module and icon against the sha256 its manifest declares. Run from the repo root:
//   node tools/try-wasm/copy-extensions.mjs /path/to/volant-extensions
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';

const catalogRoot = process.argv[2];
const out = 'website/public/try/extensions';
const sources = [
  ['hello', 'Volant/Resources/HelloWorld'],
  ['case', path.join(catalogRoot, 'case')],
  ['characters', path.join(catalogRoot, 'characters')],
  ['encode', path.join(catalogRoot, 'encode')],
  ['fancytext', path.join(catalogRoot, 'fancytext')],
  ['wordcount', path.join(catalogRoot, 'wordcount')],
  ['hackernews', path.join(catalogRoot, 'hackernews')],
  ['lobsters', path.join(catalogRoot, 'lobsters')],
  ['wikipedia', path.join(catalogRoot, 'wikipedia')],
];

/** Returns the lowercase hex sha256 of a file's bytes. */
function sha256(file) {
  return crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}

/** Copies one extension's manifest, module and icon after checking their hashes. */
function copy(name, from) {
  const manifest = JSON.parse(fs.readFileSync(path.join(from, 'manifest.json'), 'utf8'));
  const moduleFile = path.join(from, manifest.module);
  const moduleHash = sha256(moduleFile);
  if (moduleHash !== manifest.sha256) throw new Error(`${name}: module hash ${moduleHash} does not match manifest`);
  const target = path.join(out, name);
  fs.mkdirSync(target, { recursive: true });
  fs.copyFileSync(path.join(from, 'manifest.json'), path.join(target, 'manifest.json'));
  fs.copyFileSync(moduleFile, path.join(target, manifest.module));
  if (manifest.icon) {
    const iconFile = path.join(from, manifest.icon);
    if (manifest.iconSha256 && sha256(iconFile) !== manifest.iconSha256) throw new Error(`${name}: icon hash mismatch`);
    fs.copyFileSync(iconFile, path.join(target, manifest.icon));
  }
  console.log(`${name}\t${manifest.id}\t${manifest.version}\tabi ${manifest.abiVersion ?? 1}\t${moduleHash}\t${fs.statSync(moduleFile).size} bytes`);
}

for (const [name, from] of sources) copy(name, from);
