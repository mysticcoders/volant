// oxlint-disable next/no-html-link-for-pages -- vinext 1.0.0-beta.5's next/link throws in the
// production build, leaving internal navigation dead. Plain anchors until fixed upstream.
import type { Metadata } from 'next';

import { adjacentDocs } from '../docs-nav';
import { DocFooterNav } from '@/components/doc-footer-nav';

export const metadata: Metadata = {
  title: 'Volant vs Raycast: an open-source Raycast alternative — Volant docs',
  description:
    'How Volant, a free and MIT-licensed launcher for macOS, compares with Raycast: price, accounts, sandboxing, extensions, agents, and where Raycast is ahead.',
  alternates: {
    canonical: 'https://usevolant.com/docs/volant-vs-raycast',
  },
};

export default function VolantVsRaycast() {
  return (
    <>
      <p className="docs-breadcrumb">
        <a href="/docs">Docs</a> / Volant vs Raycast
      </p>
      <h1>Volant vs Raycast</h1>
      <p className="docs-lede">
        Both are keyboard launchers for the Mac. Raycast is the reference
        product, with a far larger extension store. Volant is free, MIT
        licensed, needs no account, and keeps its main app sandboxed with no
        network access. Here is where each one is the better fit.
      </p>

      <div className="docs-table-scroll">
        <table className="docs-table">
          <thead>
            <tr>
              <th><span className="sr-only">Feature</span></th>
              <th>Volant</th>
              <th>Raycast</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td>Source</td>
              <td>Open source, MIT licensed</td>
              <td>Closed source</td>
            </tr>
            <tr>
              <td>Price</td>
              <td>Free, with nothing behind a paywall</td>
              <td>
                Free tier, plus a paid Pro subscription for features such as
                unlimited clipboard history and sync (
                <a href="https://www.raycast.com/pricing">current pricing</a>)
              </td>
            </tr>
            <tr>
              <td>Account</td>
              <td>None</td>
              <td>Required for sync and AI</td>
            </tr>
            <tr>
              <td>Extensions</td>
              <td>A small signed catalog of WebAssembly extensions</td>
              <td>A large extension store</td>
            </tr>
            <tr>
              <td>Coding agents</td>
              <td>
                Herdr sessions waiting on you, Rex panes, and ACP conversations
                with Claude Code and Codex
              </td>
              <td>AI chat and AI extensions</td>
            </tr>
            <tr>
              <td>Requirements</td>
              <td>macOS 15 or later on Apple silicon</td>
              <td>See raycast.com</td>
            </tr>
          </tbody>
        </table>
      </div>

      <h2>Where Raycast is ahead</h2>
      <ul>
        <li>
          <strong>Extensions.</strong> Raycast’s store is much larger, with
          managed sign-in for many services. Volant’s catalog is new and small.
        </li>
        <li>
          <strong>Breadth.</strong> Window management, Focus sessions and script
          commands are built in. Volant has none of these.
        </li>
        <li>
          <strong>Opening speed.</strong> In our own matched measurement,
          Raycast reopened faster than Volant, so we don’t claim otherwise.
        </li>
        <li>
          <strong>Maturity.</strong> A company-backed product with a long
          release history.
        </li>
      </ul>

      <h2>Where Volant is different</h2>
      <ul>
        <li>
          <strong>Free and open.</strong> Clipboard history, notes and every
          other feature are free, and the source is on{' '}
          <a href="https://github.com/mysticcoders/volant">GitHub</a>.
        </li>
        <li>
          <strong>No account, no telemetry.</strong> Your notes are plain{' '}
          <code>.md</code> files and your clipboard history is encrypted on your
          Mac.
        </li>
        <li>
          <strong>Sandboxed by design.</strong> The main app has no network
          access. See <a href="/docs/privacy-and-security">Privacy and
          security</a> for which helpers do what.
        </li>
        <li>
          <strong>Built for agent workflows.</strong> See which Claude Code and
          Codex sessions are waiting on you and answer them from the launcher.
          See <a href="/docs/agents">Agents</a>.
        </li>
      </ul>

      <h2>Switching from Raycast</h2>
      <p>
        Volant can import snippets, quicklinks, app aliases and hotkeys, and
        plain-text notes from a Raycast export. See{' '}
        <a href="/docs/importing-from-raycast">Importing from Raycast</a>.
      </p>

      <DocFooterNav {...adjacentDocs('volant-vs-raycast')} />
    </>
  );
}
