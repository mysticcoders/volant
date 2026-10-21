// oxlint-disable next/no-html-link-for-pages -- vinext 1.0.0-beta.5's next/link throws in the
// production build, leaving internal navigation dead. Plain anchors until fixed upstream.
import type { Metadata } from 'next';

import { adjacentDocs } from '../docs-nav';
import { DocFooterNav } from '@/components/doc-footer-nav';

export const metadata: Metadata = {
  title: 'Agents — Volant docs',
  description:
    'Find Herdr agents and Rex panes, respond to supported questions, and choose coding agents, API models, local servers, or Apple Intelligence for AI Chat.',
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
        Find the session that needs you, respond to a supported question, or
        start AI Chat with the connection you choose. These features are in the
        current download; verification limits are listed below.
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

      <h3>Herdr in the footer</h3>
      <p>
        Turn on Herdr in Settings and the launcher footer shows how many panes
        are waiting on you, such as <strong>Herdr: 3 waiting</strong>. It says
        when machines are loading or one is unavailable. Click it, or type{' '}
        <code>herdr</code>, to see the panes with waiting ones first and answer
        supported questions. Its context menu hides it or limits it to one
        agent: OpenCode, Cursor, Claude Code, or Codex.
      </p>

      <div className="docs-note">
        <p>
          Focusing a pane changes the selection inside Herdr. It does not bring
          the owning terminal application forward.
        </p>
      </div>

      <h3>Questions, approvals, and saved machines</h3>
      <p>
        Waiting cards show supported Claude Code and Codex questions and
        approvals. Choose an explicit response from the card, or open the pane
        in Herdr when Volant cannot answer it. Responses are tied to the
        displayed session and question; uncertain delivery is never
        automatically resent.
      </p>
      <p>
        Volant discovers Local and enabled saved Herdr machines. Type{' '}
        <code>herdr machine</code> to enable or disable a saved destination.
        Remote forwarding requires Herdr 0.9.1 or later on both machines and a
        compatible running server. Configure hosts and SSH access in Herdr
        first.
      </p>
      <div className="docs-note">
        <p>
          Remote discovery and response routing have isolated fixture coverage.
          A successful signed-app focus/answer check against a compatible remote
          machine remains pending.
        </p>
      </div>

      <h2>Rex panes</h2>
      <p>
        Type <code>rex</code> to see the terminal panes of{' '}
        <a href="https://www.superlogical.com/rex">Rex</a> on this Mac, with
        the ones waiting on you first, then failed, done, working, and idle.
        Each row shows the project, session, program, and the last thing it
        reported, such as a question from Claude Code. Add a word to filter,
        such as <code>rex deploy</code>, and press Return to switch Rex to that
        pane and bring it forward.
      </p>
      <p>
        Status comes from what programs report to Rex through its program
        status protocol, so a pane is only as current as its program&rsquo;s
        last report. The list never reads a pane&rsquo;s screen. Volant never
        types into a pane and never starts Rex. Hiding the launcher stops
        reading.
      </p>
      <div className="docs-note">
        <p>
          To switch Rex to a pane in another session, turn on{' '}
          <strong>Remote Control</strong> in Rex Settings → Rex Server. Without
          it, Rex focuses the pane but stays on the session it is showing, and
          Volant tells you so.
        </p>
      </div>

      <h3>Rex Overview</h3>
      <p>
        Choose <strong>Open Rex Overview</strong>, the first row of the{' '}
        <code>rex</code> list, or type <code>rex overview</code>. A separate
        window shows every session, with each tab drawn as its panes are laid
        out in Rex, colored by status, and counts of what&rsquo;s waiting. Click
        a pane to switch Rex to it.
      </p>
      <p>
        Each pane shows the last 12 lines of its screen, so the overview needs{' '}
        <strong>pane previews</strong>. They are off until you turn them on,
        in the overview itself or in Settings → Status Bar → Pane previews in
        Rex Overview. While the window is open, Volant reads every Rex
        pane&rsquo;s screen text every two seconds and keeps only those last
        lines, in memory. It never saves, logs, or sends them anywhere, and
        stops reading when you close the window or turn previews off.
      </p>
      <div className="docs-note">
        <p>
          Screen text can include commands, file contents, or anything else a
          program printed. The choice applies to this Mac only and is not
          synced with iCloud settings sync.
        </p>
      </div>

      <h3>Rex in the footer</h3>
      <p>
        Turn on Rex pane activity in Settings → Status Bar and the launcher
        footer shows how many panes are waiting on you, such as{' '}
        <strong>Rex: 2 waiting</strong>. Click it to open the list; its context
        menu hides it.
      </p>

      <h2>Choose your AI connection</h2>
      <p>
        Open Settings → AI to choose a coding agent, bring your own API key,
        connect a local model server, or use Apple Intelligence. Type{' '}
        <code>ai</code> to open AI Chat. Changing Settings applies to the next
        conversation; active sessions and drafts keep their current connection.
      </p>
      <h3>Bring your own key</h3>
      <p>
        Connect an OpenAI or Anthropic API account, or a custom
        OpenAI-compatible endpoint. Keys stay in Keychain and are excluded from
        configuration and backups. The server receives your prompt, selected
        attachments, and completed conversation history. API chat does not have
        the coding agent’s tools.
      </p>
      <h3>Local models</h3>
      <p>
        Use an already-running compatible loopback server, including Ollama or
        LM Studio. Settings can look for servers and list their models; Volant
        does not start a server or download models. Test Connection checks model
        discovery, not a successful reply. Local connections never automatically
        fall back to a cloud model.
      </p>
      <h3>Apple Intelligence</h3>
      <p>
        On an eligible Mac with macOS 26 or later and Apple Intelligence
        enabled, chat with Apple’s on-device model without an endpoint or API
        key. Settings explains when the model is unavailable. Volant still runs
        on macOS 15; this connection needs the newer system.
      </p>
      <div className="docs-note">
        <p>
          HTTP streaming and signed-helper checks use fictional servers. Live
          authenticated replies for each API provider and an actual local server
          remain separate verification. Apple’s model returned a streamed reply
          in a signed sandboxed probe; live use through the installed app
          remains unverified.
        </p>
      </div>

      <h2>Attach only what you choose</h2>
      <p>
        Type <code>@</code> at the start of a word in chat, or use the @ button,
        to choose a note or recent clipboard text. Arrow keys select, Return
        attaches, and Escape closes the picker. Selecting an attachment does not
        send the message. Review or remove the chips before sending.
      </p>
      <p>
        Each attachment is a snapshot of the text when chosen, including unsaved
        note edits. Nothing is attached automatically. Up to eight items are
        allowed, with 32 KB per item and 48 KB per message; Apple Intelligence
        has a smaller 6 KB attachment budget. Oversized items are refused with a
        reason. Files, images, snippets, and Herdr pane output are not
        attachment sources.
      </p>
      <p>
        Attachment selection and transport have native and protocol fixture
        coverage. A live attachment prompt against a real provider remains
        unverified.
      </p>

      <h2>ACP conversations</h2>
      <p>
        Type <code>acp</code>, choose a provider and optionally a project, and
        start a conversation with OpenCode, Claude Code, or Codex. You get
        streamed text, tool activity, explicit permission requests with
        operation details, Cancel, and End. An activity row keeps the
        conversation reachable while you search for something else, and a hidden
        window keeps its conversation.
      </p>
      <p>
        This starts a <strong>new Volant-owned session</strong>. It does not
        attach to an existing terminal session, and no existing Herdr pane
        receives prompt input.
      </p>
      <p>
        <strong>Resume</strong> picks up where you left off. After you end a
        conversation or quit Volant, AI Chat offers Resume for your last
        conversation with the same provider and folder. It replays the history
        the provider kept and continues that same session; very long
        conversations show their most recent part. If a provider can&rsquo;t
        load earlier conversations, Resume says so and starts nothing.
      </p>
      <p>
        <strong>Several conversations</strong> can run at once, up to six.{' '}
        <strong>New</strong> in the chat header starts another while the first
        keeps working; buttons under the header switch between them and show a
        raised hand when one is waiting for your permission. The launcher&rsquo;s
        AI Chat row shows a badge for each conversation.
      </p>
      <p>
        <strong>Accounts.</strong> If you use more than one Claude Code or Codex
        login, add each as an account in AI Settings with a label and its
        configuration folder, and sign in once with the command shown there.
        A new conversation runs under the account you chose and keeps it until
        it ends; its label shows in the header. Volant passes only the
        folder&rsquo;s path to the provider (<code>CLAUDE_CONFIG_DIR</code> or{' '}
        <code>CODEX_HOME</code>) and never reads or copies what it holds.
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
              <td>
                The launch path is included but <strong>not verified</strong>.
              </td>
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
        <em>not</em> sandboxed, because it needs to discover Herdr and Rex and
        launch agent processes. It authenticates the calling app against Volant&rsquo;s
        bundle identifier and team, and exposes a narrow interface for agent
        operations and explicitly submitted prompts and context.
      </p>
      <ul>
        <li>
          Providers use <strong>their own</strong> credentials, configuration,
          network access, and tool permissions.
        </li>
        <li>
          Volant sends the prompt and attachment snapshots you explicitly
          submit. Notes and clipboard history are never attached automatically.
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
        Snippet and file attachments, ACP model and mode selection, choosing
        among older conversations, and provider-specific extensions are still
        ahead. Context is
        never sent automatically, and that will not change quietly.
      </p>

      <DocFooterNav {...adjacentDocs('agents')} />
    </>
  );
}
