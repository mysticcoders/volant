// The "Try Volant" calculator worker: VolantCore's CalculationAnswer.answers built for WASI. The
// page asks it to load as soon as it is idle; it streams the module (served brotli- or gzip-encoded
// and named by its content hash, so the browser can cache it for good), reports download progress,
// compiles it once, and answers each request with a fresh instance. The page ends a request that
// runs too long by terminating this worker.
import { answer } from './calculator.js';

let loading = null;

/** Posts progress at most once per percent, so the page isn't flooded with messages. */
function reporter(total) {
  let last = -1;
  return (received) => {
    const percent = total ? Math.floor((received / total) * 100) : -1;
    if (percent !== last) {
      last = percent;
      self.postMessage({ progress: { received, total } });
    }
  };
}

/** Downloads, decompresses and compiles the calculator module once, reporting each phase. */
function load() {
  loading ??= (async () => {
    const started = performance.now();
    const manifest = await (await fetch('/try/calculator.json', { cache: 'no-cache' })).json();
    if (!/^VolantAnswers-[0-9a-f]{16}\.wasm$/.test(manifest.file)) throw new Error('Calculator unavailable');
    const response = await fetch(`/try/calculator/${manifest.file}`);
    if (!response.ok || !response.body) throw new Error('Calculator unavailable');
    // The module arrives brotli- or gzip-encoded and the browser decodes it, so the stream yields
    // decoded bytes: progress is measured against the module's raw size from calculator.json.
    const total = Number(manifest.bytes) > 0 ? Number(manifest.bytes) : 0;
    const report = reporter(total);
    let received = 0;
    const counted = response.body.pipeThrough(new TransformStream({
      transform(chunk, controller) {
        received += chunk.byteLength;
        report(received);
        controller.enqueue(chunk);
      },
      flush() { self.postMessage({ preparing: true }); },
    }));
    const bytes = await new Response(counted).arrayBuffer();
    const downloadedMs = performance.now() - started;
    const compiled = await WebAssembly.compile(bytes);
    // Resource Timing reports a transfer size of 0 when the browser's cache answered.
    const timing = performance.getEntriesByName(new URL(`/try/calculator/${manifest.file}`, self.location.href).href).at(-1);
    const cached = timing ? timing.transferSize === 0 && timing.decodedBodySize > 0 : false;
    self.postMessage({ loaded: true, cached, downloadedMs, compiledMs: performance.now() - started - downloadedMs, bytes: received });
    return compiled;
  })();
  loading.catch(() => { loading = null; self.postMessage({ loadError: true }); });
  return loading;
}

/** Starts loading on `{preload: true}`; answers `{id, request}` with the module's JSON reply text or an error. */
self.onmessage = async (event) => {
  if (event.data.preload) { load().catch(() => {}); return; }
  const { id, request } = event.data;
  try {
    const calculator = await load();
    const started = performance.now();
    const output = answer(calculator, request);
    self.postMessage({ id, output, ms: performance.now() - started });
  } catch (error) {
    self.postMessage({ id, error: String(error?.message ?? error) });
  }
};
