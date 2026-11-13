// Runs VolantCore's calculator (tools/try-wasm, built for wasm32-unknown-wasip1) in the browser.
// It is not a Volant extension: Foundation for WASI needs more of WASI than the extension profile
// allows and the module is far over the extension size limit. So it gets its own small WASI shim:
// stdin is the request, stdout the answers, stderr is counted and discarded, there are no files,
// directories, sockets or environment, and the only argument is the program name. The clock is
// real (the request also carries the visitor's time) and random_get uses the browser's generator.

const ERRNO = { success: 0, badf: 8, inval: 28, nosys: 52 };
const limits = { inputBytes: 64 * 1024, outputBytes: 256 * 1024, diagnosticBytes: 64 * 1024 };

/** Answers one request (`{query, now, zone, locale}` as JSON) with a fresh instance of `compiled`,
 * returning the module's JSON reply text. */
export function answer(compiled, request, diagnostics = null) {
  const input = new TextEncoder().encode(request);
  if (input.length > limits.inputBytes) throw new Error('Request too large');
  const program = new TextEncoder().encode('VolantAnswers\0');
  const box = { memory: null };
  let consumed = 0, stderrBytes = 0, exitCode = 0;
  const output = [];
  const exitSignal = {};
  const bytes = (pointer, length) => new Uint8Array(box.memory.buffer, pointer >>> 0, length >>> 0);
  const view = () => new DataView(box.memory.buffer);
  const vectors = (pointer, count) => {
    const list = [];
    for (let i = 0; i < count; i++) list.push(bytes(view().getUint32(pointer + i * 8, true), view().getUint32(pointer + i * 8 + 4, true)));
    return list;
  };
  const nosys = () => ERRNO.nosys;
  const wasi = {
    args_sizes_get(count, size) { view().setUint32(count, 1, true); view().setUint32(size, program.length, true); return 0; },
    args_get(pointers, data) { view().setUint32(pointers, data, true); bytes(data, program.length).set(program); return 0; },
    environ_sizes_get(count, size) { view().setUint32(count, 0, true); view().setUint32(size, 0, true); return 0; },
    environ_get() { return 0; },
    clock_res_get(id, result) { view().setBigUint64(result, 1000n, true); return 0; },
    clock_time_get(id, precision, result) {
      const nanos = id === 0 ? BigInt(Date.now()) * 1000000n : BigInt(Math.round(performance.now() * 1e6));
      view().setBigUint64(result, nanos, true); return 0;
    },
    random_get(pointer, length) { crypto.getRandomValues(bytes(pointer, length)); return 0; },
    fd_fdstat_get(fd, result) {
      if (fd > 2) return ERRNO.badf;
      bytes(result, 24).fill(0);
      view().setUint8(result, 2);
      view().setBigUint64(result + 8, fd === 0 ? 2n : 64n, true);
      return 0;
    },
    fd_read(fd, pointer, count, result) {
      if (fd !== 0) return ERRNO.badf;
      let read = 0;
      for (const target of vectors(pointer, count)) {
        const size = Math.min(target.length, input.length - consumed);
        target.set(input.subarray(consumed, consumed + size)); consumed += size; read += size;
      }
      view().setUint32(result, read, true); return 0;
    },
    fd_write(fd, pointer, count, result) {
      if (fd !== 1 && fd !== 2) return ERRNO.badf;
      let size = 0;
      for (const source of vectors(pointer, count)) {
        size += source.length;
        if (fd === 1) {
          if (output.length + source.length > limits.outputBytes) throw new Error('Calculator output too large');
          for (const byte of source) output.push(byte);
        } else {
          if ((stderrBytes += source.length) > limits.diagnosticBytes) throw new Error('Calculator diagnostics too large');
          diagnostics?.push(new TextDecoder().decode(source));
        }
      }
      view().setUint32(result, size, true); return 0;
    },
    fd_close(fd) { return fd <= 2 ? 0 : ERRNO.badf; },
    fd_prestat_get() { return ERRNO.badf; },
    fd_prestat_dir_name() { return ERRNO.badf; },
    proc_exit(code) { exitCode = code >>> 0; throw exitSignal; },
  };
  for (const name of ['fd_fdstat_set_flags', 'fd_filestat_get', 'fd_filestat_set_size', 'fd_filestat_set_times', 'fd_pread',
    'fd_readdir', 'fd_seek', 'fd_sync', 'fd_tell', 'path_create_directory', 'path_filestat_get', 'path_filestat_set_times',
    'path_link', 'path_open', 'path_readlink', 'path_remove_directory', 'path_rename', 'path_symlink', 'path_unlink_file',
    'poll_oneoff']) wasi[name] = nosys;
  for (const item of WebAssembly.Module.imports(compiled)) {
    if (item.module !== 'wasi_snapshot_preview1' || !(item.name in wasi)) throw new Error(`Unsupported calculator import ${item.module}.${item.name}`);
  }
  const instance = new WebAssembly.Instance(compiled, { wasi_snapshot_preview1: wasi });
  box.memory = instance.exports.memory;
  try {
    instance.exports._start();
  } catch (error) {
    if (error !== exitSignal) {
      error.partialOutput = new TextDecoder().decode(new Uint8Array(output));
      throw error;
    }
  }
  if (exitCode !== 0) throw new Error('Calculator exited unsuccessfully');
  return new TextDecoder('utf-8', { fatal: true }).decode(new Uint8Array(output));
}
