import Foundation

/// A deliberately small WASI Preview 1 command profile, not a general WASI runtime.
/// Descriptors are in-memory streams, never OS descriptors. No environment, paths,
/// sockets, randomness or clipboard is exposed; clocks are fixed at zero.
enum WASICommand {
    static let script = #"""
    (() => {
      let memory, consumed = 0, stderrBytes = 0, calls = 0;
      const output = [], closed = new Set();
      const exitSignal = {};
      let exitCode = 0, exited = false;
      const input = Uint8Array.from(inputBytes);
      function range(pointer, length) {
        pointer >>>= 0;
        if (!memory || !Number.isSafeInteger(length) || length < 0 || pointer > memory.buffer.byteLength || length > memory.buffer.byteLength - pointer)
          throw new Error('Invalid command memory range');
        return new Uint8Array(memory.buffer, pointer, length);
      }
      function view(pointer, length) { const bytes = range(pointer, length); return new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength); }
      function put32(pointer, value) { view(pointer, 4).setUint32(0, value, true); }
      function valid(fd) { return fd >= 0 && fd <= 2 && !closed.has(fd); }
      function vectors(pointer, count, result) {
        count >>>= 0;
        if (count > 1024) throw new Error('Too many command buffers');
        const table = view(pointer, count * 8), list = [];
        range(result, 4);
        for (let i = 0; i < count; i++) list.push(range(table.getUint32(i * 8, true), table.getUint32(i * 8 + 4, true)));
        return list;
      }
      const wasi = Object.create(null);
      Object.assign(wasi, {
        environ_sizes_get(count, size) { range(count, 4); range(size, 4); put32(count, 0); put32(size, 0); return 0; },
        environ_get(pointers, data) { range(pointers, 0); range(data, 0); return 0; },
        clock_time_get(id, precision, result) {
          if (id !== 0 && id !== 1) return 28;
          view(result, 8).setBigUint64(0, 0n, true); return 0;
        },
        fd_close(fd) { if (!valid(fd)) return 8; closed.add(fd); return 0; },
        fd_fdstat_get(fd, result) {
          if (!valid(fd)) return 8;
          range(result, 24).fill(0);
          const stat = view(result, 24);
          stat.setUint8(0, 2); // character-device stream
          stat.setBigUint64(8, fd === 0 ? 2n : 64n, true); return 0;
        },
        fd_seek(fd, offset, whence, result) { return valid(fd) ? 70 : 8; },
        fd_read(fd, pointer, count, result) {
          if (fd !== 0 || !valid(fd)) return 8;
          const list = vectors(pointer, count, result);
          let read = 0;
          for (const bytes of list) {
            const size = Math.min(bytes.length, input.length - consumed);
            bytes.set(input.subarray(consumed, consumed + size)); consumed += size; read += size;
          }
          put32(result, read); return 0;
        },
        fd_write(fd, pointer, count, result) {
          if ((fd !== 1 && fd !== 2) || !valid(fd)) return 8;
          const list = vectors(pointer, count, result);
          const size = list.reduce((total, bytes) => total + bytes.length, 0);
          if (fd === 1 && size > 65536 - output.length) throw new Error('Command output exceeds 64 KiB');
          if (fd === 2 && size > 4096 - stderrBytes) throw new Error('Command diagnostic limit exceeded');
          if (fd === 1) for (const bytes of list) for (const byte of bytes) output.push(byte);
          else stderrBytes += size; // Do not log or display extension stderr.
          put32(result, size); return 0;
        },
        proc_exit(code) { exitCode = code >>> 0; exited = true; throw exitSignal; }
      });
      for (const name of Object.keys(wasi)) {
        const implementation = wasi[name];
        wasi[name] = (...args) => {
          if (exited) throw exitSignal; // Even WASM that catches the exit cannot perform more I/O.
          if (++calls > 4096) throw new Error('Command host-call limit exceeded');
          return implementation(...args);
        };
      }
      const module = new WebAssembly.Module(Uint8Array.from(moduleBytes));
      for (const item of WebAssembly.Module.imports(module)) {
        if (item.kind !== 'function' || item.module !== 'wasi_snapshot_preview1' || !Object.hasOwn(wasi, item.name))
          throw new Error('Unsupported command import');
      }
      const instance = new WebAssembly.Instance(module, { wasi_snapshot_preview1: wasi });
      memory = instance.exports.memory;
      if (!(memory instanceof WebAssembly.Memory) || typeof instance.exports._start !== 'function')
        throw new Error('Command must export memory and _start');
      try { instance.exports._start(); }
      catch (error) { if (error !== exitSignal) throw error; }
      if (exitCode !== 0) throw new Error('Command exited unsuccessfully');
      return output;
    })()
    """#
}
