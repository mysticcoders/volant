// oxlint-disable next/no-html-link-for-pages -- vinext 1.0.0-beta.5's next/link throws in the
// production build, leaving internal navigation dead. Plain anchors until fixed upstream.
import type { Metadata } from 'next';

import { adjacentDocs } from '../docs-nav';
import { DocFooterNav } from '@/components/doc-footer-nav';

export const metadata: Metadata = {
  title: 'Volant vs Alfred: an open-source Alfred alternative — Volant docs',
  description:
    'How Volant, a free and MIT-licensed launcher for macOS, compares with Alfred: price, clipboard history and snippets, workflows, agents, and where Alfred is ahead.',
  alternates: {
    canonical: 'https://usevolant.com/docs/volant-vs-alfred',
  },
};

export default function VolantVsAlfred() {
  return (
    <>
      <p className="docs-breadcrumb">
        <a href="/docs">Docs</a> / Volant vs Alfred
      </p>
      <h1>Volant vs Alfred</h1>
      <p className="docs-lede">
        Alfred has been a favorite Mac launcher for years, with a deep library
        of community workflows. Volant is a newer, free and MIT-licensed
        launcher that includes clipboard history and snippets at no cost and
        adds coding-agent workflows. Here is where each one is the better fit.
      </p>

      <div className="docs-table-scroll">
        <table className="docs-table">
          <thead>
            <tr>
              <th><span className="sr-only">Feature</span></th>
              <th>Volant</th>
              <th>Alfred</th>
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
                Free core app, plus the paid Powerpack license (
                <a href="https://www.alfredapp.com/powerpack/">current pricing</a>)
              </td>
            </tr>
            <tr>
              <td>Clipboard, snippets</td>
              <td>Included; clipboard history is encrypted at rest</td>
              <td>Part of the Powerpack</td>
            </tr>
            <tr>
              <td>Extending it</td>
              <td>A small signed catalog of sandboxed WebAssembly extensions</td>
              <td>A large library of community workflows</td>
            </tr>
            <tr>
              <td>Coding agents</td>
              <td>
                Herdr sessions waiting on you, Rex panes, and ACP conversations
                with Claude Code and Codex
              </td>
              <td>Not built in</td>
            </tr>
            <tr>
              <td>Requirements</td>
              <td>macOS 15 or later on Apple silicon</td>
              <td>See alfredapp.com</td>
            </tr>
          </tbody>
        </table>
      </div>

      <h2>Where Alfred is ahead</h2>
      <ul>
        <li>
          <strong>Workflows.</strong> Years of community workflows cover
          almost any service or script. Volant’s extension catalog is new and
          small.
        </li>
        <li>
          <strong>File navigation.</strong> Alfred’s file browsing and file
          actions go further than Volant’s file search.
        </li>
        <li>
          <strong>Maturity.</strong> A long-established app with a large,
          loyal user base.
        </li>
      </ul>

      <h2>Where Volant is different</h2>
      <ul>
        <li>
          <strong>Free and open.</strong> Clipboard history, snippets and notes
          are included, and the source is on{' '}
          <a href="https://github.com/mysticcoders/volant">GitHub</a>.
        </li>
        <li>
          <strong>Answers inline.</strong> Currency conversion, time zones and
          dates in the calculator, plus plain Markdown notes in a floating
          window. See <a href="/docs/calculator">The calculator</a> and{' '}
          <a href="/docs/notes">Notes</a>.
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

      <DocFooterNav {...adjacentDocs('volant-vs-alfred')} />
    </>
  );
}
