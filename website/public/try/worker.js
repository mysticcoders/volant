// The "Try Volant" extension worker. The page sends one module call at a time; a call that runs
// past the extension's time limit is ended by the page terminating this worker, as Volant's
// helper is terminated. Modules come only from this site's /try/extensions folder.
import { runModule, runCommand } from './host.js';

const modules = new Map();

/** Loads and caches an extension's module bytes by its folder name. */
async function moduleBytes(name, file) {
  if (!/^[a-z]+$/.test(name) || !/^[a-z]+\.wasm$/.test(file)) throw new Error('Unknown extension');
  const key = `${name}/${file}`;
  if (!modules.has(key)) {
    const response = await fetch(`/try/extensions/${key}`);
    if (!response.ok) throw new Error('Extension module unavailable');
    modules.set(key, new Uint8Array(await response.arrayBuffer()));
  }
  return modules.get(key);
}

/** Runs one module call and replies with its output, the clipboard text it asked to write, or an error. */
self.onmessage = async (event) => {
  const { id, name, file, abi, capabilities, input } = event.data;
  const clipboard = [];
  try {
    const bytes = await moduleBytes(name, file);
    const started = performance.now();
    const output = abi === 2 ? runCommand(bytes, input) : runModule(bytes, capabilities ?? [], input, { clipboard: (text) => clipboard.push(text) });
    self.postMessage({ id, output, clipboard, ms: performance.now() - started });
  } catch (error) {
    self.postMessage({ id, error: String(error?.message ?? error) });
  }
};
