import { build } from "esbuild";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { boundMemory } from "./bound-memory.mjs";
import { resolve } from "node:path";
import { execFileSync } from "node:child_process";
mkdirSync("out", { recursive: true });
await build({
  entryPoints: ["entry.ts"], bundle: true, format: "esm", platform: "neutral",
  mainFields: ["module", "main"], outfile: "out/encode.js",
  plugins: [{ name: "fictional-raycast-adapter", setup(builder) {
    builder.onResolve({ filter: /^(@raycast\/api|\.\/util)$/ }, () => ({ path: resolve("adapter.ts") }));
  } }],
});
execFileSync(process.env.JAVY ?? "javy", ["build", "out/encode.js", "-C", "dynamic=n", "-C", "source=omitted", "-J", "event-loop=y", "-J", "text-encoding=y", "-J", "javy-stream-io=y", "-o", "out/encode.wasm"], { stdio: "inherit" });
const module = boundMemory(readFileSync("out/encode.wasm"));
writeFileSync("out/encode.wasm", module);
mkdirSync("../../extensions/raycast-base64", { recursive: true });
writeFileSync("../../extensions/raycast-base64/encode.wasm", module);
writeFileSync("../../extensions/raycast-base64/manifest.json", JSON.stringify({
  abiVersion: 2, id: "community.raycast.base64", name: "Base64 Encode", version: "1.0.0",
  module: "encode.wasm", capabilities: [], timeoutSeconds: 2,
  sha256: createHash("sha256").update(module).digest("hex"),
}, null, 2) + "\n");
