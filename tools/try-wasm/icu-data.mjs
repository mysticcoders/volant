// Trims the ICU common data package (icudt76l) inside the calculator's WebAssembly module to the
// items listed in icu-keep.txt. Foundation for WASI links ICU's full data (about 34 MB) into one
// data segment; the calculator uses a small part of it.
//
//   node icu-data.mjs list <module.wasm> [items.tsv]     item sizes by category
//   node icu-data.mjs trim <module.wasm> <icu-keep.txt> <out.wasm>
//
// ICU finds its data through a pointer to the package start and the package's own table of
// contents, so the trimmed package can be shorter. Other read-only data follows the package in the
// same segment and is addressed directly, so it stays at its original address: the segment is split
// in two, and the data count section is updated.
import fs from 'node:fs';

/** Reads an unsigned LEB128 number at `state.at`. */
function leb(bytes, state) {
  let value = 0, shift = 0, byte;
  do {
    byte = bytes[state.at++];
    value += (byte & 0x7f) * 2 ** shift;
    shift += 7;
  } while (byte & 0x80);
  return value;
}

/** Reads a signed LEB128 number (an i32.const operand) at `state.at`. */
function sleb(bytes, state) {
  let value = 0, shift = 0, byte;
  do {
    byte = bytes[state.at++];
    value |= (byte & 0x7f) << shift;
    shift += 7;
  } while (byte & 0x80);
  if (shift < 32 && byte & 0x40) value |= -1 << shift;
  return value;
}

/** Encodes an unsigned LEB128 number. */
function encodeLeb(value) {
  const out = [];
  do {
    let byte = value % 128;
    value = Math.floor(value / 128);
    if (value) byte |= 0x80;
    out.push(byte);
  } while (value);
  return Buffer.from(out);
}

/** Encodes a signed LEB128 number. */
function encodeSleb(value) {
  const out = [];
  for (;;) {
    const byte = value & 0x7f;
    value >>= 7;
    const done = (value === 0 && !(byte & 0x40)) || (value === -1 && byte & 0x40);
    out.push(done ? byte : byte | 0x80);
    if (done) return Buffer.from(out);
  }
}

/** Lists the module's sections and the data section's segments with their memory offsets. */
function parse(bytes) {
  const state = { at: 8 };
  const sections = [];
  while (state.at < bytes.length) {
    const start = state.at;
    const id = bytes[state.at++];
    const size = leb(bytes, state);
    sections.push({ id, start, body: state.at, end: state.at + size });
    state.at += size;
  }
  const data = sections.find((s) => s.id === 11);
  const segments = [];
  const cursor = { at: data.body };
  const count = leb(bytes, cursor);
  for (let i = 0; i < count; i++) {
    const head = cursor.at;
    const flags = leb(bytes, cursor);
    let offset = null;
    if (flags === 0 && bytes[cursor.at] === 0x41) {
      cursor.at++;
      offset = sleb(bytes, cursor);
      if (bytes[cursor.at++] !== 0x0b) throw new Error('Unexpected data segment offset');
    } else if (flags !== 1) {
      throw new Error('Unsupported data segment');
    }
    const length = leb(bytes, cursor);
    segments.push({ head, flags, offset, payload: cursor.at, length, end: cursor.at + length });
    cursor.at += length;
  }
  return { sections, data, segments };
}

/** The real size of a resource bundle item: its header plus indexes[URES_INDEX_BUNDLE_TOP]
 * (32-bit units after the header). Used for the package's last item, whose end the table of
 * contents doesn't give. */
function resourceBundleSize(item) {
  const headerSize = item.readUInt16LE(0);
  if (item.toString('latin1', 12, 16) !== 'ResB') throw new Error('Last ICU item is not a resource bundle');
  const indexes = headerSize + 4;
  const bundleTop = item.readUInt32LE(indexes + 3 * 4);
  return headerSize + bundleTop * 4;
}

/** Finds the ICU package: the segment holding it, its start, table of contents and items. ICU common
 * data begins with a header (magic 0xda27) whose data format is "CmnD". */
function locate(bytes) {
  const parsed = parse(bytes);
  for (const segment of parsed.segments) {
    const payload = bytes.subarray(segment.payload, segment.end);
    const at = payload.indexOf(Buffer.from('CmnD'));
    if (at < 12 || payload[at - 10] !== 0xda || payload[at - 9] !== 0x27) continue;
    const start = at - 12;
    const headerSize = payload.readUInt16LE(start);
    const toc = start + headerSize;
    const count = payload.readUInt32LE(toc);
    const list = [];
    for (let i = 0; i < count; i++) {
      const nameOffset = payload.readUInt32LE(toc + 4 + i * 8);
      const dataOffset = payload.readUInt32LE(toc + 8 + i * 8);
      list.push({ name: payload.toString('latin1', toc + nameOffset, payload.indexOf(0, toc + nameOffset)), offset: dataOffset });
    }
    list.forEach((item, i) => { if (i + 1 < list.length) item.size = list[i + 1].offset - item.offset; });
    const last = list.at(-1);
    last.size = resourceBundleSize(payload.subarray(toc + last.offset));
    const end = toc + last.offset + last.size;
    return { ...parsed, segment, payload, start, headerSize, toc, list, end };
  }
  throw new Error('ICU common data not found');
}

/** Builds a common data package of the kept items: the original header, a rewritten table of
 * contents and each item 16-byte aligned, as ICU's own packages are. */
function build(found, keep) {
  const { payload, start, headerSize, toc, list } = found;
  const kept = list.filter((item) => keep(item.name));
  const names = Buffer.concat(kept.map((item) => Buffer.from(`${item.name}\0`, 'latin1')));
  const tableSize = 4 + kept.length * 8;
  const align = (n) => Math.ceil(n / 16) * 16;
  const table = Buffer.alloc(tableSize);
  table.writeUInt32LE(kept.length, 0);
  let nameCursor = tableSize;
  let dataCursor = align(tableSize + names.length);
  const chunks = [];
  kept.forEach((item, i) => {
    table.writeUInt32LE(nameCursor, 4 + i * 8);
    table.writeUInt32LE(dataCursor, 8 + i * 8);
    nameCursor += Buffer.byteLength(item.name, 'latin1') + 1;
    const data = payload.subarray(toc + item.offset, toc + item.offset + item.size);
    chunks.push(data, Buffer.alloc(align(data.length) - data.length));
    dataCursor += align(data.length);
  });
  const padding = Buffer.alloc(align(tableSize + names.length) - tableSize - names.length);
  return { bytes: Buffer.concat([payload.subarray(start, start + headerSize), table, names, padding, ...chunks]), kept };
}

/** Reads icu-keep.txt: one glob per line over item names without the icudt76l/ prefix; '#' starts a comment. */
function keepList(file) {
  const globs = fs.readFileSync(file, 'utf8').split('\n').map((line) => line.replace(/#.*/, '').trim()).filter(Boolean);
  const patterns = globs.map((glob) => new RegExp(`^${glob.replace(/[.+^${}()|[\]\\]/g, '\\$&').replace(/\*/g, '.*')}$`));
  return (name) => patterns.some((pattern) => pattern.test(name.replace(/^icudt\d+l\//, '')));
}

/** Rewrites the module with the ICU segment split into the trimmed package (at its old address)
 * and the data that followed the package (at its old address). */
function rewrite(bytes, found, packageBytes) {
  const { sections, data, segments, segment, payload, start, end } = found;
  if (segment.offset === null) throw new Error('The ICU segment is passive');
  const active = (offset, body) => Buffer.concat([Buffer.from([0, 0x41]), encodeSleb(offset), Buffer.from([0x0b]), encodeLeb(body.length), body]);
  const first = active(segment.offset, Buffer.concat([payload.subarray(0, start), packageBytes]));
  const second = active(segment.offset + end, payload.subarray(end));
  const pieces = [encodeLeb(segments.length + 1)];
  for (const s of segments) pieces.push(s === segment ? Buffer.concat([first, second]) : bytes.subarray(s.head, s.end));
  const body = Buffer.concat(pieces);
  const parts = [];
  let at = 0;
  for (const section of sections) {
    if (section.id === 11) {
      parts.push(bytes.subarray(at, section.start), Buffer.from([11]), encodeLeb(body.length), body);
      at = section.end;
    } else if (section.id === 12) {
      const count = encodeLeb(segments.length + 1);
      parts.push(bytes.subarray(at, section.start), Buffer.from([12]), encodeLeb(count.length), count);
      at = section.end;
    }
  }
  parts.push(bytes.subarray(at));
  return Buffer.concat(parts);
}

const [command, file, second, third] = process.argv.slice(2);
const bytes = fs.readFileSync(file);
const found = locate(bytes);
if (command === 'list') {
  const byCategory = {};
  for (const item of found.list) {
    const short = item.name.replace(/^icudt\d+l\//, '');
    const category = short.includes('/') ? short.split('/')[0] : '(root)';
    byCategory[category] = (byCategory[category] ?? 0) + item.size;
  }
  console.log(JSON.stringify({ items: found.list.length, packageBytes: found.end - found.start, trailingBytes: found.payload.length - found.end, categories: Object.entries(byCategory).sort((a, b) => b[1] - a[1]).map(([k, v]) => `${k} ${(v / 1e6).toFixed(2)} MB`) }, null, 1));
  if (second) fs.writeFileSync(second, found.list.map((item) => `${item.size}\t${item.name}`).join('\n'));
} else if (command === 'trim') {
  const built = build(found, keepList(second));
  const out = rewrite(bytes, found, built.bytes);
  fs.writeFileSync(third, out);
  console.log(`kept ${built.kept.length} of ${found.list.length} ICU items (${found.end - found.start} -> ${built.bytes.length} bytes); module ${bytes.length} -> ${out.length} bytes`);
} else {
  throw new Error('usage: list <module.wasm> [items.tsv] | trim <module.wasm> <icu-keep.txt> <out.wasm>');
}
