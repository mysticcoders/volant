// oxlint-disable next/no-html-link-for-pages -- vinext 1.0.0-beta.5's next/link throws in the
// production build, leaving internal navigation dead. Plain anchors until fixed upstream.
import type { Metadata } from 'next';

import { adjacentDocs } from '../docs-nav';
import { DocFooterNav } from '@/components/doc-footer-nav';
import { appVersion, downloadURL } from '@/components/site-chrome';

export const metadata: Metadata = {
  title: 'Getting started — Volant docs',
  description:
    'Install Volant on macOS 15 or later, summon the launcher, and find your configuration folder.',
  alternates: { canonical: 'https://usevolant.com/docs/getting-started' },
};

export default function GettingStarted() {
  return (
    <>
      <p className="docs-breadcrumb">
        <a href="/docs">Docs</a> / Getting started
      </p>
      <h1>Getting started</h1>
      <p className="docs-lede">
        Volant is a single Mac app with no account and no setup server. Download
        it, drag it to Applications, and press your summon hotkey.
      </p>

      <h2>What you need</h2>
      <ul>
        <li>macOS 15 or later.</li>
        <li>
          Any Mac. The download is universal and includes both Apple silicon and
          Intel builds.
        </li>
      </ul>

      <h2>Install</h2>
      <p>
        Download the disk image, open it, and drag Volant into Applications. The
        release is signed with a Developer ID and notarized by Apple, so
        Gatekeeper opens it without a warning.
      </p>
      <p>
        <a className="button" href={downloadURL} download>
          Download Volant {appVersion}
        </a>
      </p>

      <h2>Summon the launcher</h2>
      <p>
        The bundled example configuration uses <code>cmd+space</code>. If no
        summon hotkey is set at all, Volant falls back to{' '}
        <code>option+space</code>. Either way, you can change it — see{' '}
        <a href="/docs/configuration">Configuration</a>.
      </p>
      <div className="docs-note">
        <p>
          <code>cmd+space</code> is Spotlight&rsquo;s default. To give it to
          Volant, turn off the Spotlight shortcut in System Settings under
          Keyboard &rsaquo; Keyboard Shortcuts &rsaquo; Spotlight, or pick a
          different hotkey for Volant.
        </p>
      </div>
      <p>
        Type to fuzzy-search your apps and press Return to launch. That is the
        whole first interaction; everything else builds on it.
      </p>

      <h2>Try these first</h2>
      <div className="docs-table-scroll">
        <table className="docs-table">
          <thead>
            <tr>
              <th>Type this</th>
              <th>What happens</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td><code>sa</code></td>
              <td>Fuzzy-matches Safari. After you pick it once, that exact query pins Safari first next time.</td>
            </tr>
            <tr>
              <td><code>2^10 / 3</code></td>
              <td>Shows the result. Return copies it.</td>
            </tr>
            <tr>
              <td><code>5 km in mi</code></td>
              <td>Converts offline. Return copies the number.</td>
            </tr>
            <tr>
              <td><code>cal</code></td>
              <td>Today and tomorrow&rsquo;s agenda. Return joins the meeting link.</td>
            </tr>
            <tr>
              <td><code>clip</code></td>
              <td>Your encrypted clipboard history.</td>
            </tr>
            <tr>
              <td><code>:rocket</code></td>
              <td>Emoji search. Return copies the character.</td>
            </tr>
          </tbody>
        </table>
      </div>

      <h2>Notes and settings</h2>
      <p>
        Press <code>option+n</code> for the notes window. Open Settings from the
        menu bar or with <code>Command-comma</code>; it controls whether Volant
        appears in the Dock, whether the launcher opens at start, and it can
        reveal your configuration file.
      </p>

      <h2>Where your files live</h2>
      <p>
        Choose <strong>Reveal Config Folder</strong> from the menu bar to open
        the folder holding <code>config.json</code>. Notes are ordinary{' '}
        <code>.md</code> files in the app container. Clipboard history is a
        separate encrypted database — see{' '}
        <a href="/docs/privacy-and-security">Privacy and security</a>.
      </p>

      <h2>Updates</h2>
      <p>
        Volant includes <strong>Check for Updates</strong> in its menu. Updates
        are delivered through Sparkle, which uses its own helper process for
        network access; the main app has no network entitlement at all.
      </p>

      <DocFooterNav {...adjacentDocs('getting-started')} />
    </>
  );
}
