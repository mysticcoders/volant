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
        files, no interface. Extensions that read the web get pages through a
        different helper, described below. A crash, a runaway loop, or a memory blow-up ends
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

      <h2>Extensions that read the web</h2>
      <p>
        A list extension can show live data, such as the{' '}
        <a href="https://github.com/mysticcoders/volant-extensions">
          Hacker News and Lobsters readers
        </a>
        . Its manifest adds <code>&quot;output&quot;: &quot;items&quot;</code>{' '}
        and the exact <code>hosts</code> it reads, such as{' '}
        <code>[&quot;lobste.rs&quot;]</code>. The extension still has no
        network access. Volant runs it in rounds: first it returns the URLs it
        wants, then it receives the pages and returns rows, or asks for more
        pages, up to three rounds. Each request also says whether you use US
        or metric units. Return opens a
        row&rsquo;s link and Command-Return opens its second link, typically
        the discussion. An extension may also open its own app, such as a
        task in Todoist, if it says so before you approve it; if that app
        is not installed, the web link opens instead. Rows can show one of
        Volant&rsquo;s weather icons, such as sun, rain or snow, which
        Volant draws itself.
      </p>
      <ul>
        <li>
          <strong>You approve hosts first.</strong> The first run, or turning
          the extension on in Settings, lists the hosts it needs. Allow enables
          it and allows them together.
        </li>
        <li>
          <strong>Only approved https hosts.</strong> A separate sandboxed
          fetch helper requests each URL only if its host is in the manifest
          and allowed by you: https, no redirects, no cookies, and at most
          512&nbsp;KB per page. The only credential is a token you gave the
          extension for that host, which Volant adds itself.
        </li>
        <li>
          <strong>Changes need an action.</strong> Listing only reads. An
          extension can send a change, such as completing a task, only from
          an action you choose in Command-K or with Return, and asks first.
        </li>
        <li>
          <strong>Location only if you allow it.</strong> An extension that
          asks for your location gets it rounded to about 11&nbsp;km, only
          after you allow that extension, and can pass it to the sites it
          reads. Settings → Extensions → Location removes it.
        </li>
        <li>
          <strong>Hosts are shared and removable.</strong> Settings →
          Extensions → Network Access lists every allowed host and the
          extensions that use it. Remove takes it away from all of them.
        </li>
        <li>
          <strong>Uninstall cleans up.</strong> Uninstalling a community
          extension moves it to the Trash and removes hosts no other extension
          needs.
        </li>
      </ul>

      <h2>Install from the catalog</h2>
      <p>
        The catalog lists extensions reviewed for Volant, with each one&rsquo;s
        publisher, license, the hosts it reads and a link to the exact source
        it was built from. In the launcher, type <code>catalog</code> (or
        choose Extension Catalog) to search it and read about an extension
        before you install it; in Settings → Extensions, choose Refresh. Turn
        on Allow Community Extensions, then Install, then Turn On. Volant
        contacts the catalog only when you check it or choose Refresh.
      </p>
      <ul>
        <li>
          <strong>Signed and checked.</strong> The catalog is signed, and Volant
          refuses one whose signature fails or that is older than one it has
          already seen. Every downloaded file must match the size and hash the
          signed catalog lists before anything is installed.
        </li>
        <li>
          <strong>Installing runs nothing.</strong> An installed extension
          starts off. Its first use asks as usual, including for any hosts.
        </li>
        <li>
          <strong>Updates ask again when they change.</strong> Update replaces
          the extension in one step and puts the old version back if that
          fails. An update with changed code, permissions or hosts stays off
          until you turn it on again.
        </li>
      </ul>
      <p>
        Extensions that are off stay out of everyday search; type{' '}
        <code>ext</code> and a name to find one. You can still install an
        extension by hand: choose Open Folder, copy its folder in, and choose
        Refresh. An extension can include its own icon, which Volant shows in
        the launcher and Settings.
      </p>

      <h2>Extensions that remember</h2>
      <p>
        A list extension can keep a small amount of data on your Mac, such as
        the Hacker News and Lobsters readers&rsquo; pinned and hidden stories
        and the stories you have read. It asks to &ldquo;Remember settings and
        lists on this Mac&rdquo; before you turn it on. Its rows can offer
        actions in Command-K, such as Pin Story or Hide Stories from a site.
      </p>
      <ul>
        <li>
          <strong>Small and local.</strong> At most 256&nbsp;KB per extension,
          kept only on this Mac: never synced through iCloud and never part of
          Volant&rsquo;s backups.
        </li>
        <li>
          <strong>Yours to clear.</strong> Settings → Extensions → Clear Data
          forgets it; uninstalling the extension deletes it; turning it off or
          updating it keeps it.
        </li>
        <li>
          <strong>Still no network or files.</strong> The extension gets its
          own data with each request and nothing else. An action never fetches;
          Volant runs the list again to show the change.
        </li>
      </ul>

      <h2>Not yet</h2>
      <p>
        Background update checks, revoking a published extension, preferences
        forms, storage for text commands, async or streaming results, and a
        stable ABI. Each will be added deliberately.
      </p>

      <DocFooterNav {...adjacentDocs('extensions')} />
    </>
  );
}
