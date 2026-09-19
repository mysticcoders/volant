// Development-only fixture generation; checked-in binaries need no assembler in app CI.
import wabtFactory from "wabt";
import { mkdirSync, writeFileSync } from "node:fs";
const wabt = await wabtFactory();
const directory = "../extensions/wasi-fixtures";
mkdirSync(directory, { recursive: true });
const imports = `
(import "wasi_snapshot_preview1" "fd_read" (func $read (param i32 i32 i32 i32) (result i32)))
(import "wasi_snapshot_preview1" "fd_write" (func $write (param i32 i32 i32 i32) (result i32)))
(import "wasi_snapshot_preview1" "fd_close" (func $close (param i32) (result i32)))
(import "wasi_snapshot_preview1" "fd_fdstat_get" (func $stat (param i32 i32) (result i32)))
(import "wasi_snapshot_preview1" "fd_seek" (func $seek (param i32 i64 i32 i32) (result i32)))
(import "wasi_snapshot_preview1" "environ_sizes_get" (func $envsize (param i32 i32) (result i32)))
(import "wasi_snapshot_preview1" "environ_get" (func $env (param i32 i32) (result i32)))
(import "wasi_snapshot_preview1" "clock_time_get" (func $clock (param i32 i64 i32) (result i32)))
(import "wasi_snapshot_preview1" "proc_exit" (func $exit (param i32)))`;
const setup = `(i32.store (i32.const 0) (i32.const 128)) (i32.store (i32.const 4) (i32.const 2))`;
const write = `(drop (call $write (i32.const 1) (i32.const 0) (i32.const 1) (i32.const 8)))`;
const cases = {
  streams: `
    (call $assert (i32.eqz (call $envsize (i32.const 16) (i32.const 20))))
    (call $assert (i32.eqz (i32.load (i32.const 16))))
    (call $assert (i32.eqz (i32.load (i32.const 20))))
    (call $assert (i32.eqz (call $env (i32.const 24) (i32.const 24))))
    (call $assert (i32.eqz (call $clock (i32.const 0) (i64.const 0) (i32.const 24))))
    (call $assert (i64.eqz (i64.load (i32.const 24))))
    (call $assert (i32.eq (call $clock (i32.const 9) (i64.const 0) (i32.const 24)) (i32.const 28)))
    (call $assert (i32.eqz (call $stat (i32.const 1) (i32.const 32))))
    (call $assert (i64.eq (i64.load (i32.const 40)) (i64.const 64)))
    (call $assert (i32.eqz (call $stat (i32.const 0) (i32.const 32))))
    (call $assert (i64.eq (i64.load (i32.const 40)) (i64.const 2)))
    (call $assert (i32.eq (call $seek (i32.const 1) (i64.const 0) (i32.const 0) (i32.const 24)) (i32.const 70)))
    ${setup}
    (call $assert (i32.eq (call $read (i32.const 9) (i32.const 0) (i32.const 1) (i32.const 8)) (i32.const 8)))
    (call $assert (i32.eqz (call $read (i32.const 0) (i32.const 0) (i32.const 1) (i32.const 8))))
    (call $assert (i32.eq (i32.load (i32.const 8)) (i32.const 2))) ${write}
    (call $assert (i32.eqz (call $read (i32.const 0) (i32.const 0) (i32.const 1) (i32.const 8))))
    (call $assert (i32.eqz (i32.load (i32.const 8))))
    (call $assert (i32.eqz (call $close (i32.const 0))))
    (call $assert (i32.eq (call $read (i32.const 0) (i32.const 0) (i32.const 1) (i32.const 8)) (i32.const 8)))
    (call $assert (i32.eq (memory.grow (i32.const 1)) (i32.const -1)))`,
  zeroExit: `${setup} ${write} (call $exit (i32.const 0)) unreachable`,
  caughtExit: `${setup} ${write} (try (do (call $exit (i32.const 0))) (catch_all)) ${write}`,
  failedExit: `${setup} ${write} (call $exit (i32.const 1))`,
  bounds: `(drop (call $read (i32.const 0) (i32.const -1) (i32.const 1) (i32.const 8)))`,
  vectorLimit: `(drop (call $read (i32.const 0) (i32.const 0) (i32.const 1025) (i32.const 8)))`,
  outputLimit: `(i32.store (i32.const 0) (i32.const 0)) (i32.store (i32.const 4) (i32.const 65536)) ${write} ${setup} ${write}`,
  stderrLimit: `(i32.store (i32.const 0) (i32.const 128)) (i32.store (i32.const 4) (i32.const 4097)) (drop (call $write (i32.const 2) (i32.const 0) (i32.const 1) (i32.const 8)))`,
  invalidUTF8: `${setup} (i32.store8 (i32.const 128) (i32.const 255)) ${write}`,
  callLimit: `(loop $again (drop (call $envsize (i32.const 16) (i32.const 20))) (br $again))`,
  spin: `(loop $again (br $again))`,
};
for (const [name, body] of Object.entries(cases)) {
  const wat = `(module ${imports} (memory (export "memory") 1 1) (data (i32.const 128) "OK")
    (func $assert (param i32) local.get 0 i32.eqz if unreachable end)
    (func (export "_start") ${body}))`;
  const module = wabt.parseWat(name, wat, { exceptions: true }); module.resolveNames(); module.validate({ exceptions: true });
  writeFileSync(`${directory}/${name}.wat`, wat + "\n");
  writeFileSync(`${directory}/${name}.wasm`, module.toBinary({}).buffer); module.destroy();
}
for (const [name, imported] of [["filesystem", "path_open"], ["network", "sock_open"], ["prototype", "toString"]]) {
  const wat = `(module (import "wasi_snapshot_preview1" "${imported}" (func)) (memory (export "memory") 1 1) (func (export "_start")))`;
  const module = wabt.parseWat(name, wat);
  writeFileSync(`${directory}/${name}.wat`, wat + "\n");
  writeFileSync(`${directory}/${name}.wasm`, module.toBinary({}).buffer); module.destroy();
}
