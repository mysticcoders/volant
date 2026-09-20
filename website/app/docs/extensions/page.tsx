// oxlint-disable next/no-html-link-for-pages -- vinext 1.0.0-beta.5's next/link throws in the
// production build, leaving internal navigation dead. Plain anchors until fixed upstream.
import type { Metadata } from 'next';

import { adjacentDocs } from '../docs-nav';
import { DocFooterNav } from '@/components/doc-footer-nav';

export const metadata: Metadata = {
  title: 'Extensions — Volant docs',
  description:
    'A working spike: WebAssembly extensions running in a separate sandboxed process with manifest-declared capabilities.',
  alternates: { canonical: 'https://usevolant.com/docs/extensions' },
};

const manifest = `{
  "id": "com.mysticcoders.vey.hello-rust",
  "name": "Hello (Rust)",
  "version": "0.1.0",
  "module": "hello.wasm",
  "capabilities": ["log", "clipboard.write"],
  "timeoutSeconds": 2,
  "sha256": "…"
}`;

export default function Extensions() {
  return (
    <>
      <p className="docs-breadcrumb">
        <a href="/docs">Docs</a> / Extensions
      </p>
      <h1>Extensions</h1>
      <div className="docs-note">
        <p>
          <strong>Status: a working spike, not a stable API.</strong> It runs
          end to end, but the ABI, the capability list, and the install flow
          will all change. Build against it only if you are willing to follow
          those changes.
        </p>
      </div>
      <p className="docs-lede">
        An extension is a folder holding a manifest and a WebAssembly module.
        The manifest pins the module&rsquo;s hash and lists the capabilities it
        may use — and that list is the complete set of host functions the module
        can call. Nothing else exists from its point of view.
      </p>

      <h2>The manifest</h2>
      <pre>
        <code>{manifest}</code>
      </pre>
      <p>
        Extensions can be written in any language that compiles to{' '}
        <code>wasm32-unknown-unknown</code>. The sample is Rust; C, Zig, Go via
        TinyGo, Swift via SwiftWasm, and AssemblyScript all produce the same
        kind of module.
      </p>

      <h2>Where it runs</h2>
      <p>
        Extension code never runs inside the Volant app. It runs in a separate
        XPC service that holds only the App Sandbox entitlement — no network, no
        files, no interface. A crash, a runaway loop, or a memory blow-up ends
        there.
      </p>
      <p>
        The service uses JavaScriptCore&rsquo;s built-in WebAssembly engine,
        which Apple maintains and ships with macOS, so Volant adds no
        third-party runtime. JavaScript is glue, not a runtime for extensions:
        the module never sees JavaScript globals, because a WebAssembly instance
        can only call the imports it is handed.
      </p>

      <h3>Four independent gates</h3>
      <ul>
        <li>
          <strong>Integrity.</strong> The app hashes the module and refuses to
          run it if the hash differs from the manifest&rsquo;s pin.
        </li>
        <li>
          <strong>Imports are built from the manifest.</strong> Before
          instantiation the service reads the module&rsquo;s declared imports
          and refuses any the manifest does not grant. A module compiled against{' '}
          <code>clipboard.write</code> fails to load under a manifest granting
          only <code>log</code>.
        </li>
        <li>
          <strong>The app re-checks every callback.</strong> Capabilities
          execute in the app, and the app checks the running manifest again
          before honoring each one.
        </li>
        <li>
          <strong>Watchdog.</strong> If <code>run</code> has not returned within{' '}
          <code>timeoutSeconds</code>, the service process exits and launchd
          restarts it for the next call.
        </li>
      </ul>

      <h2>The ABI</h2>
      <p>
        The module exports <code>memory</code>, <code>alloc(len) -&gt; ptr</code>,
        and <code>run(ptr, len) -&gt; ptr</code>. The host writes UTF-8 input
        into allocated memory, calls <code>run</code>, and reads a record at the
        returned pointer: a little-endian <code>u32</code> length followed by
        UTF-8 bytes. Host imports live in a module namespace still named{' '}
        <code>vey</code>, offering <code>log(ptr, len)</code> and{' '}
        <code>clipboard_write(ptr, len)</code>.
      </p>

      <h2>Running one</h2>
      <p>
        In the launcher, <code>ext hello some text</code> runs the extension
        with that text as input and shows the result. From the command line,{' '}
        <code>Volant --run-extension hello &quot;some text&quot;</code> does the
        same and prints the log.
      </p>

      <h2>Not yet</h2>
      <p>
        Per-module memory caps, a capability catalog beyond two functions, a
        permissions dialog at install time, signed manifests, an install flow,
        async or streaming results, and a stable ABI. Each will be added
        deliberately.
      </p>

      <DocFooterNav {...adjacentDocs('extensions')} />
    </>
  );
}
