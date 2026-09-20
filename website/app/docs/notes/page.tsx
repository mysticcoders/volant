// oxlint-disable next/no-html-link-for-pages -- vinext 1.0.0-beta.5's next/link throws in the
// production build, leaving internal navigation dead. Plain anchors until fixed upstream.
import type { Metadata } from 'next';

import { adjacentDocs } from '../docs-nav';
import { DocFooterNav } from '@/components/doc-footer-nav';

export const metadata: Metadata = {
  title: 'Notes — Volant docs',
  description:
    'A floating Markdown window with live styling, code-fence language detection, and ordinary .md files on disk.',
  alternates: { canonical: 'https://usevolant.com/docs/notes' },
};

export default function Notes() {
  return (
    <>
      <p className="docs-breadcrumb">
        <a href="/docs">Docs</a> / Notes
      </p>
      <h1>Notes</h1>
      <p className="docs-lede">
        Press <code>option+n</code> for a floating single-note window that
        remembers where you left off. A note shouldn&rsquo;t become another
        project.
      </p>

      <h2>Live Markdown</h2>
      <p>
        Live mode styles your Markdown as you type and recognizes a code fence
        immediately — type <code>```python</code> and keep writing. Markdown
        markers stay visible in Live mode, so you always see the actual
        characters in your file.
      </p>
      <p>
        The footer switches between <strong>Live</strong>,{' '}
        <strong>Markdown Source</strong>, and <strong>Preview</strong>.
      </p>

      <h3>Code blocks</h3>
      <p>
        Move the cursor into a code block to choose its language, or leave it on
        Auto for a local heuristic guess. Nothing is sent anywhere to identify
        the language.
      </p>
      <p>
        In Preview, code blocks and bare URLs copy <em>their contents, never
        the fences</em>, by double-click or the Copy button. When you do want
        the raw Markdown, <code>⇧⌘C</code> copies it.
      </p>

      <h2>Keyboard</h2>
      <div className="docs-table-scroll">
        <table className="docs-table">
          <thead>
            <tr>
              <th>Keys</th>
              <th>Action</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td><code>⌘P</code></td>
              <td>Browse and search your notes, pinned ones first.</td>
            </tr>
            <tr>
              <td><code>⌘K</code></td>
              <td>Search actions.</td>
            </tr>
            <tr>
              <td><code>⌘N</code></td>
              <td>New note.</td>
            </tr>
            <tr>
              <td><code>⌘E</code></td>
              <td>Toggle edit and preview.</td>
            </tr>
            <tr>
              <td><code>⌘D</code></td>
              <td>Duplicate the current note.</td>
            </tr>
            <tr>
              <td><code>⇧⌘P</code></td>
              <td>Toggle pinning.</td>
            </tr>
            <tr>
              <td><code>⇧⌘C</code></td>
              <td>Copy the raw Markdown.</td>
            </tr>
            <tr>
              <td><code>⌘⌫</code></td>
              <td>Trash the note.</td>
            </tr>
          </tbody>
        </table>
      </div>

      <h2>From the launcher</h2>
      <p>
        <code>note</code> lists recent notes. <code>note term</code> searches
        note contents and offers to create one if nothing matches.
      </p>

      <h2>Your words, your files</h2>
      <p>
        Each note is an ordinary <code>.md</code> file in the app container.
        Open them in another editor whenever you like.
      </p>
      <p>
        Pinning and your last selection are local interface preferences, so they
        are excluded from backups — the Markdown is the durable part.
      </p>

      <div className="docs-note">
        <p>
          If a save fails, the failure stays on screen with a{' '}
          <strong>Retry Save</strong> action rather than disappearing, and
          closing the window waits for unsaved text to reach disk.
        </p>
      </div>

      <DocFooterNav {...adjacentDocs('notes')} />
    </>
  );
}
