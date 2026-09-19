import { build } from "esbuild";
import { mkdirSync } from "node:fs";
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
