import assert from "node:assert/strict";
import { WASI } from "node:wasi";
import { readFileSync, writeFileSync, openSync, closeSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
const bytes = readFileSync("out/encode.wasm");
const module = await WebAssembly.compile(bytes);
console.log(JSON.stringify({ bytes: bytes.length, imports: WebAssembly.Module.imports(module), exports: WebAssembly.Module.exports(module) }, null, 2));
const root = mkdtempSync(join(tmpdir(), "volant-base64-wasm-"));
try {
  for (const input of ["", "Hello, Volant!", "café ☕ 日本語", "a".repeat(4096)]) {
    writeFileSync(join(root, "input"), input);
    const stdin = openSync(join(root, "input"), "r");
    const stdout = openSync(join(root, "output"), "w+");
    try {
      const wasi = new WASI({ version: "preview1", args: [], env: {}, preopens: {}, stdin, stdout, returnOnExit: true });
      const instance = await WebAssembly.instantiate(module, { wasi_snapshot_preview1: wasi.wasiImport });
      assert.equal(wasi.start(instance), 0);
      assert.equal(readFileSync(join(root, "output"), "utf8"), Buffer.from(input).toString("base64"));
    } finally { closeSync(stdin); closeSync(stdout); }
  }
  console.log("PASS: upstream Raycast TypeScript command bundled into WASM; four fictional stdin/stdout cases match Base64.");
} finally { rmSync(root, { recursive: true, force: true }); }
