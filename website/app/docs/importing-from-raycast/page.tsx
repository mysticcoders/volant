// oxlint-disable next/no-html-link-for-pages -- vinext 1.0.0-beta.5's next/link throws in the
// production build, leaving internal navigation dead. Plain anchors until fixed upstream.
import type { Metadata } from 'next';

import { adjacentDocs } from '../docs-nav';
import { DocFooterNav } from '@/components/doc-footer-nav';

export const metadata: Metadata = {
  title: 'Importing from Raycast — Volant docs',
  description:
    'Import snippets, quicklinks, app aliases and hotkeys, and plain-text notes from an encrypted Raycast export.',
  alternates: {
    canonical: 'https://usevolant.com/docs/importing-from-raycast',
  },
};

export default function ImportingFromRaycast() {
  return (
    <>
      <p className="docs-breadcrumb">
        <a href="/docs">Docs</a> / Importing from Raycast
      </p>
      <h1>Importing from Raycast</h1>
      <p className="docs-lede">
        Choose Settings &rsaquo; Import from Raycast, pick your export file,
        enter its password, review exactly what would change, then select the
        categories you want.
      </p>

      <h2>Before you start</h2>
      <p>
        Volant reads a schema-3 Raycast export. Older encrypted formats are
        rejected explicitly rather than guessed at. The export is read
        read-only, and no decrypted copy is ever written to disk.
      </p>
      <div className="docs-note">
        <p>
          Your password is used in process memory only. It is never saved,
          logged, or passed to another process.
        </p>
      </div>

      <h2>What comes across</h2>
      <ul>
        <li><strong>Snippets.</strong> Supported date and time placeholders are converted to Volant&rsquo;s formatting. Placeholders Volant does not recognize are left as literal text rather than mangled.</li>
        <li><strong>Quicklinks.</strong> Basic links, including a single <code>{'{Query}'}</code> parameter mapped to <code>{'{query}'}</code>, and default-app opening. Unsupported parameters and URL schemes are skipped.</li>
        <li><strong>App aliases and hotkeys</strong> for applications you have installed.</li>
        <li><strong>Notes</strong> that carry an explicit Markdown or plain-text representation.</li>
      </ul>

      <h2>What does not</h2>
      <p>
        Clipboard history, extension runtimes and commands, AI sessions, global
        shortcuts, favorites, and other settings are not migrated in this
        version. Rich note representations are reported and skipped rather than
        converted into something approximate.
      </p>

      <h2>How conflicts resolve</h2>
      <p>
        What you already have wins. Existing names, keywords, URLs, aliases, and
        app bindings are kept, and no existing note is ever overwritten —
        imported note names derive from their content.
      </p>
      <p>
        Imported app hotkeys arrive <strong>unchecked</strong>. In Volant a
        per-app hotkey toggles activate and hide, and a binding Raycast still
        owns will keep winning until you resolve it there, so these are opt-in
        by design.
      </p>

      <h2>If something goes wrong</h2>
      <p>
        Before any change is written, Volant creates a uniquely named{' '}
        <code>Raycast-Import-&lt;UUID&gt;</code> recovery folder holding your
        exact original configuration and a list of the notes it plans to add. A
        failed write removes only the notes it just created.
      </p>
      <p>
        This is a guarded sequence, not a single atomic transaction across
        files. If the process is killed partway, follow the{' '}
        <code>Recovery.txt</code> in that folder. Recovery backups contain the
        same local settings and snippet data as your original configuration and
        stay until you remove them.
      </p>

      <DocFooterNav {...adjacentDocs('importing-from-raycast')} />
    </>
  );
}
