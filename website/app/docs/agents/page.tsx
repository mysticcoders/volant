// oxlint-disable next/no-html-link-for-pages -- vinext 1.0.0-beta.5's next/link throws in the
// production build, leaving internal navigation dead. Plain anchors until fixed upstream.
import type { Metadata } from 'next';

import { adjacentDocs } from '../docs-nav';
import { DocFooterNav } from '@/components/doc-footer-nav';

export const metadata: Metadata = {
  title: 'Agents — Volant docs',
  description:
    'Find and focus Herdr panes, and hold native ACP conversations with OpenCode, Claude Code, and Codex from the launcher.',
  alternates: { canonical: 'https://usevolant.com/docs/agents' },
};

export default function Agents() {
  return (
    <>
      <p className="docs-breadcrumb">
        <a href="/docs">Docs</a> / Agents
      </p>
      <h1>Agents</h1>
      <p className="docs-lede">
        A native place to find the session that needs you, return to its pane,
        and start a conversation. This area is in active development, and the
        limits below are real.
      </p>

      <h2>Herdr panes</h2>
      <p>
        Type <code>agents</code> or <code>herdr</code> in the launcher, or
        choose Agents from the menu, then connect explicitly. You can search by
        project, provider, or status, refresh, disconnect, and press Return to
        focus a pane.
      </p>
      <p>
        Hiding the launcher disconnects and stops polling — nothing runs in the
        background watching your agents.
      </p>

      <h3>Pinning a harness</h3>
      <p>
        Use the pin menu, a pane&rsquo;s context menu, or Settings &rsaquo;
        Pinned harness to promote All Herdr agents, OpenCode, Cursor, Claude
        Code, or Codex to a summary strip below the search field. The summary
        stays put while you search for other things, and opens its filtered pane
        list when you select it.
      </p>

      <div className="docs-note">
        <p>
          Focusing a pane changes the selection inside Herdr. It does not bring
          the owning terminal application forward.
        </p>
      </div>

      <h2>ACP conversations</h2>
      <p>
        Type <code>acp</code>, choose a project, and start a conversation with
        OpenCode, Claude Code, or Codex. You get streamed text, tool activity,
        explicit permission requests with operation details, Cancel, and End.
        An activity row keeps the conversation reachable while you search for
        something else, and a hidden window keeps its conversation.
      </p>
      <p>
        This starts a <strong>new Volant-owned session</strong>. It does not
        attach to an existing terminal session, and no existing Herdr pane
        receives prompt input.
      </p>

      <h3>Provider status</h3>
      <div className="docs-table-scroll">
        <table className="docs-table">
          <thead>
            <tr>
              <th>Provider</th>
              <th>Status</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td>OpenCode</td>
              <td>ACP over stdio, verified end to end.</td>
            </tr>
            <tr>
              <td>Claude Code</td>
              <td>Verified through a pinned ACP adapter.</td>
            </tr>
            <tr>
              <td>Codex</td>
              <td>Verified through a pinned ACP adapter.</td>
            </tr>
            <tr>
              <td>Cursor</td>
              <td>The launch path is included but <strong>not verified</strong>.</td>
            </tr>
          </tbody>
        </table>
      </div>

      <h3>Adapters</h3>
      <p>
        Claude Code and Codex connect through maintained adapters from the Agent
        Client Protocol project, pinned to specific versions.{' '}
        <code>Scripts/install-acp-adapters.sh</code> installs them into{' '}
        <code>~/.local/share/volant/acp</code>. A Node 22+ runtime is required.
        The helper executes Node by absolute path with only the known adapter
        entrypoint — no shell, and no package downloads at startup.
      </p>

      <h2>What this means for your data</h2>
      <p>
        The main Volant app stays sandboxed with no network entitlement. Agent
        support runs through a separately signed helper that is intentionally
        <em>not</em> sandboxed, because it needs to discover Herdr and launch
        agent processes. It authenticates the calling app against Volant&rsquo;s
        bundle identifier and team, and exposes a narrow interface that cannot
        accept arbitrary commands, filenames, or clipboard content.
      </p>
      <ul>
        <li>
          Providers use <strong>their own</strong> credentials, configuration,
          network access, and tool permissions.
        </li>
        <li>
          Volant sends only the prompt text you explicitly submit. Notes and
          clipboard history are never attached automatically.
        </li>
        <li>
          Volant displays and answers the permission requests a provider emits.
          A provider configured to authorize its own tools may never emit one,
          so Volant is not a replacement security boundary.
        </li>
        <li>
          Selecting a project sets working context. It is not enforced
          filesystem confinement.
        </li>
      </ul>

      <h2>Not yet</h2>
      <p>
        Reviewed note and snippet handoff, model and mode selection, session
        resume, and provider-specific extensions are still ahead. Context is
        never sent automatically, and that will not change quietly.
      </p>

      <DocFooterNav {...adjacentDocs('agents')} />
    </>
  );
}
