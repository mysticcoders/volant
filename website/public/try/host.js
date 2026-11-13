// Volant's extension host, ported to the browser for the "Try Volant" spike. It mirrors
// VolantExtensionHost/ExtensionHost.swift (ABI 1), WASICommand.swift (ABI 2) and
// ExtensionMemory.validate in VolantCore, with the same limits. It runs inside a dedicated
// Worker, so the page can terminate a module that runs past its time limit.

export const limits = {
  moduleBytes: 2 * 1024 * 1024,
  inputBytes: 1024 * 1024,
  outputBytes: 256 * 1024,
  memoryPages: 256,
  callbacks: 64,
  commandCalls: 4096,
  commandDiagnosticBytes: 4096,
};

/** Reads one unsigned LEB128 number from `bytes` at `state.offset`, refusing anything past `end`. */
function leb(bytes, state, end) {
  let value = 0;
  for (let shift = 0; shift <= 28; shift += 7) {
    if (state.offset >= end) throw new Error('Invalid module memory');
    const byte = bytes[state.offset++];
    if (shift === 28 && byte > 15) throw new Error('Invalid module memory');
    value |= (byte & 127) << shift;
    if (byte < 128) return value >>> 0;
  }
  throw new Error('Invalid module memory');
}

/** Accepts only a WebAssembly module of at most 2 MiB that declares exactly one non-shared memory
 * with an explicit maximum of 16 MiB, as ExtensionMemory.validate does. */
export function validateModule(bytes) {
  const magic = [0, 97, 115, 109, 1, 0, 0, 0];
  if (bytes.length > limits.moduleBytes || magic.some((b, i) => bytes[i] !== b)) throw new Error('Invalid module memory');
  const state = { offset: 8 };
  let found = false;
  while (state.offset < bytes.length) {
    const section = bytes[state.offset++];
    const count = leb(bytes, state, bytes.length);
    if (count > bytes.length - state.offset) throw new Error('Invalid module memory');
    const end = state.offset + count;
    if (section === 5) {
      if (found || leb(bytes, state, end) !== 1 || leb(bytes, state, end) !== 1) throw new Error('Invalid module memory');
      const initial = leb(bytes, state, end), maximum = leb(bytes, state, end);
      if (initial > maximum || maximum > limits.memoryPages || state.offset !== end) throw new Error('Invalid module memory');
      found = true;
    }
    state.offset = end;
  }
  if (!found) throw new Error('Invalid module memory');
}

/** Runs an ABI 1 module once: grants only the `volant` imports in `capabilities`, writes the input
 * through `alloc`, calls `run`, and reads the u32 length-prefixed UTF-8 reply. Host callbacks are
 * capped at 64 per invocation; `clipboard.write` text is returned, never written by the host itself. */
export function runModule(moduleBytes, capabilities, input, sink = {}) {
  validateModule(moduleBytes);
  const inputBytes = new TextEncoder().encode(input);
  if (inputBytes.length > limits.inputBytes) throw new Error('Invalid extension request.');
  const box = { memory: null };
  let remaining = limits.callbacks;
  const read = (ptr, len) => {
    if (ptr < 0 || len < 0 || len > 65536) return null;
    return new TextDecoder().decode(new Uint8Array(box.memory.buffer, ptr, len));
  };
  const granted = {};
  if (capabilities.includes('log')) granted.log = (ptr, len) => { if (remaining-- > 0) sink.log?.(read(ptr, len)); };
  if (capabilities.includes('clipboard.write')) granted.clipboard_write = (ptr, len) => { if (remaining-- > 0) sink.clipboard?.(read(ptr, len)); };
  const compiled = new WebAssembly.Module(moduleBytes);
  for (const imp of WebAssembly.Module.imports(compiled)) {
    if (imp.kind !== 'function' || imp.module !== 'volant' || !(imp.name in granted))
      throw new Error('module wants import ' + imp.module + '.' + imp.name + ' which is not granted');
  }
  const instance = new WebAssembly.Instance(compiled, { volant: granted });
  box.memory = instance.exports.memory;
  const memory = box.memory;
  const ptr = instance.exports.alloc(inputBytes.length);
  new Uint8Array(memory.buffer, ptr, inputBytes.length).set(inputBytes);
  const out = instance.exports.run(ptr, inputBytes.length);
  const len = new DataView(memory.buffer).getUint32(out, true);
  if (len > limits.outputBytes) throw new Error('Extension output exceeds 256 KiB');
  return new TextDecoder('utf-8', { fatal: true }).decode(new Uint8Array(memory.buffer, out + 4, len));
}

/** Runs an ABI 2 module as a deliberately small WASI Preview 1 command: stdin is the request,
 * stdout the reply, stderr is counted and discarded. No environment, paths, sockets or randomness;
 * clocks read zero; at most 4096 host calls. */
export function runCommand(moduleBytes, input) {
  validateModule(moduleBytes);
  const data = new TextEncoder().encode(input);
  if (data.length > limits.inputBytes) throw new Error('Invalid extension request.');
  const box = { memory: null };
  let consumed = 0, stderrBytes = 0, calls = 0, exitCode = 0, exited = false;
  const output = [], closed = new Set(), exitSignal = {};
  const range = (pointer, length) => {
    pointer >>>= 0;
    const memory = box.memory;
    if (!memory || !Number.isSafeInteger(length) || length < 0 || pointer > memory.buffer.byteLength || length > memory.buffer.byteLength - pointer)
      throw new Error('Invalid command memory range');
    return new Uint8Array(memory.buffer, pointer, length);
  };
  const view = (pointer, length) => { const b = range(pointer, length); return new DataView(b.buffer, b.byteOffset, b.byteLength); };
  const put32 = (pointer, value) => view(pointer, 4).setUint32(0, value, true);
  const valid = (fd) => fd >= 0 && fd <= 2 && !closed.has(fd);
  const vectors = (pointer, count, result) => {
    count >>>= 0;
    if (count > 1024) throw new Error('Too many command buffers');
    const table = view(pointer, count * 8), list = [];
    range(result, 4);
    for (let i = 0; i < count; i++) list.push(range(table.getUint32(i * 8, true), table.getUint32(i * 8 + 4, true)));
    return list;
  };
  const wasi = Object.create(null);
  Object.assign(wasi, {
    environ_sizes_get(count, size) { range(count, 4); range(size, 4); put32(count, 0); put32(size, 0); return 0; },
    environ_get(pointers, data) { range(pointers, 0); range(data, 0); return 0; },
    clock_time_get(id, precision, result) { if (id !== 0 && id !== 1) return 28; view(result, 8).setBigUint64(0, 0n, true); return 0; },
    fd_close(fd) { if (!valid(fd)) return 8; closed.add(fd); return 0; },
    fd_fdstat_get(fd, result) {
      if (!valid(fd)) return 8;
      range(result, 24).fill(0);
      const stat = view(result, 24);
      stat.setUint8(0, 2);
      stat.setBigUint64(8, fd === 0 ? 2n : 64n, true);
      return 0;
    },
    fd_seek(fd) { return valid(fd) ? 70 : 8; },
    fd_read(fd, pointer, count, result) {
      if (fd !== 0 || !valid(fd)) return 8;
      let read = 0;
      for (const bytes of vectors(pointer, count, result)) {
        const size = Math.min(bytes.length, data.length - consumed);
        bytes.set(data.subarray(consumed, consumed + size)); consumed += size; read += size;
      }
      put32(result, read); return 0;
    },
    fd_write(fd, pointer, count, result) {
      if ((fd !== 1 && fd !== 2) || !valid(fd)) return 8;
      const list = vectors(pointer, count, result);
      const size = list.reduce((total, bytes) => total + bytes.length, 0);
      if (fd === 1 && size > limits.outputBytes - output.length) throw new Error('Command output exceeds 256 KiB');
      if (fd === 2 && size > limits.commandDiagnosticBytes - stderrBytes) throw new Error('Command diagnostic limit exceeded');
      if (fd === 1) for (const bytes of list) for (const byte of bytes) output.push(byte);
      else stderrBytes += size;
      put32(result, size); return 0;
    },
    proc_exit(code) { exitCode = code >>> 0; exited = true; throw exitSignal; },
  });
  for (const name of Object.keys(wasi)) {
    const implementation = wasi[name];
    wasi[name] = (...args) => {
      if (exited) throw exitSignal;
      if (++calls > limits.commandCalls) throw new Error('Command host-call limit exceeded');
      return implementation(...args);
    };
  }
  const compiled = new WebAssembly.Module(moduleBytes);
  for (const item of WebAssembly.Module.imports(compiled)) {
    if (item.kind !== 'function' || item.module !== 'wasi_snapshot_preview1' || !Object.hasOwn(wasi, item.name))
      throw new Error('Unsupported command import');
  }
  const instance = new WebAssembly.Instance(compiled, { wasi_snapshot_preview1: wasi });
  box.memory = instance.exports.memory;
  if (!(box.memory instanceof WebAssembly.Memory) || typeof instance.exports._start !== 'function')
    throw new Error('Command must export memory and _start');
  try { instance.exports._start(); } catch (error) { if (error !== exitSignal) throw error; }
  if (exitCode !== 0) throw new Error('Command exited unsuccessfully');
  return new TextDecoder('utf-8', { fatal: true }).decode(new Uint8Array(output));
}
