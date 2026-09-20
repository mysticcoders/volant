// oxlint-disable next/no-html-link-for-pages -- vinext 1.0.0-beta.5's next/link throws in the
// production build, leaving internal navigation dead. Plain anchors until fixed upstream.
import type { Metadata } from 'next';

import { adjacentDocs } from '../docs-nav';
import { DocFooterNav } from '@/components/doc-footer-nav';

export const metadata: Metadata = {
  title: 'Apple Shortcuts — Volant docs',
  description:
    'Run a saved Apple Shortcut from a Volant quicklink, optionally passing typed text as input.',
  alternates: { canonical: 'https://usevolant.com/docs/shortcuts' },
};

const withInput = `{
  "name": "capture",
  "url": "shortcuts://run-shortcut?name=Capture%20Text&input=text&text={query}"
}`;

export default function Shortcuts() {
  return (
    <>
      <p className="docs-breadcrumb">
        <a href="/docs">Docs</a> / Apple Shortcuts
      </p>
      <h1>Apple Shortcuts</h1>
      <p className="docs-lede">
        Volant can launch a saved shortcut through Apple&rsquo;s documented URL
        scheme. Because a shortcut can contain actions provided by other apps,
        this is how you reach another app&rsquo;s capabilities from the
        launcher.
      </p>

      <h2>How it works</h2>
      <p>
        Build the workflow in Shortcuts first. Then add a quicklink to your{' '}
        <a href="/docs/configuration">configuration</a> and choose{' '}
        <strong>Reload Config</strong>.
      </p>

      <h3>Passing typed text</h3>
      <p>
        For a shortcut named <code>Capture Text</code> that accepts text input,
        add this to your <code>quicklinks</code> array:
      </p>
      <pre>
        <code>{withInput}</code>
      </pre>
      <p>
        Now type <code>capture buy coffee</code> and press Return. Shortcuts
        opens with <code>buy coffee</code> as its input. Your typed text is
        percent-encoded as a single value, so ampersands, plus signs, percent
        signs, and Unicode all survive intact. The shortcut name in the
        configured URL must be URL-encoded too — note the <code>%20</code>{' '}
        above.
      </p>

      <h3>Other forms</h3>
      <div className="docs-table-scroll">
        <table className="docs-table">
          <thead>
            <tr>
              <th>URL</th>
              <th>Behavior</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td><code>shortcuts://run-shortcut?name=Example</code></td>
              <td>Runs a workflow that takes no input.</td>
            </tr>
            <tr>
              <td><code>...?name=Example&amp;input=clipboard</code></td>
              <td>Passes the clipboard. Opt-in per quicklink.</td>
            </tr>
          </tbody>
        </table>
      </div>
      <div className="docs-note">
        <p>
          Clipboard input is never attached automatically. You choose it, per
          quicklink, by writing it into the URL.
        </p>
      </div>

      <h2>What this does not do</h2>
      <ul>
        <li>
          It runs shortcuts already saved in your collection. It does not
          install them.
        </li>
        <li>
          It does not enumerate every third-party app&rsquo;s available actions.
          You set each one up explicitly.
        </li>
        <li>
          It does not return a workflow&rsquo;s result back into Volant.
        </li>
      </ul>
      <p>
        Shortcuts itself handles action permissions, prompts, and execution
        errors, including a missing or renamed shortcut. Volant reports an
        invalid URL or a failure to hand the URL to an application — but a
        successful handoff does not prove the workflow finished successfully.
      </p>

      <h2>A note on scope</h2>
      <p>
        Volant&rsquo;s sandbox entitlements are unchanged by this feature.
        Workflows run inside Shortcuts and may use the network, run scripts, or
        modify data through their own actions and permissions. The capability
        restrictions that apply to{' '}
        <a href="/docs/extensions">Volant extensions</a> do not apply to
        Shortcuts.
      </p>

      <DocFooterNav {...adjacentDocs('shortcuts')} />
    </>
  );
}
