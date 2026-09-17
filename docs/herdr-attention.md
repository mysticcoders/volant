# Herdr attention and provider answers

A pinned Herdr status shows one waiting agent below the status strip, with previous/next controls. Unsupported prompts retain a bounded, literal terminal preview and Open in Herdr. Hidden launchers release the preview; question text is never persisted or logged.

Verified Codex and Claude single-choice questions show the question and the provider's actual option labels/descriptions. Click an option to answer. Answer with keyboard explicitly focuses the card; ⌥⌘ plus its option number answers only while that area has focus. Return in launcher search is not an approval shortcut. Notes and None of the above require Open in Herdr. Claude Create file and Bash approval screens also expose their exact choices and request context; see [Claude evidence and limits](herdr-claude.md). Unrecognized screens and other providers retain pane handoff. This is not a generic Yes/Always/No mapping.

The signed helper exposes read and token-plus-choice methods, not arbitrary keys or shell input. It reads up to 80 detection lines, validates pane/terminal/provider/session identity and blocked-state sequence before and after reading, and issues a 30-second single-use token. The question fingerprint includes progress, title and every choice. Answering consumes the token, revalidates the current question, moves the selection, rereads to confirm the selected row, then sends Enter separately. Changed questions or occupants stop submission. A consumed question cannot be submitted again through a newly refreshed token in the same helper session. Display excerpts remain limited to 30 lines/4,000 characters.

After Enter the helper checks whether Codex resumed, acknowledged the answer, or advanced to another question. Key delivery alone is not reported as acknowledgement. Timeouts/errors produce an uncertain-delivery message and no automatic retry. The helper's serial queue prevents overlapping response operations; the UI also disables responses while sending.

## Remaining transport limitation

Herdr 0.9.0 / protocol 22 has no conditional send operation accepting an expected terminal/session and prompt revision. Separate reads and sends cannot eliminate the final read/send race, including changes made directly in the terminal. Provider session identity is absent in the tested Codex metadata; terminal identity plus state sequence and fingerprint provide the available guards. A future conditional response API is needed for an atomic guarantee. Claude approvals require the complete supported request layout and context fingerprint; matching Yes or Always alone is never sufficient.

## Evidence and next work

On 2026-09-17, Codex CLI 0.154.0 in a disposable empty-directory Plan session asked a real `request_user_input` question about fictional Amber/Violet themes. Explicit agent key delivery selected Violet; Codex showed `answer: Violet` and returned `ACK: Violet`. The production response controller then independently read and answered a second real question and observed Codex resume. This establishes the terminal/controller path separately from the installed-app test below.

Automated unit checks cover the observed screen, unsupported/truncated forms, changed pane/state/question, changes after navigation, token expiry, unsupported notes answers and duplicate submission. Branded headless UI fixtures cover loading, choices, pending/acknowledged delivery, fallback errors and resolution in light/dark at three sizes. Native mouse focus plus ⌥⌘2 submission and duplicate prevention passed in all six Tart variants. Compact/default/large captures and error/resolution states were visually inspected.

Installed evidence: PR #48 merged as `797fb1f` after scope/native/UI/PR gate passed. The signed Release app was installed fresh at `/Applications/Volant.app` and restarted during an explicitly approved desktop test window. The real fictional question appeared in the pinned card; clicking Violet through the installed UI produced “Codex acknowledged your answer.” Codex independently showed `answer: Violet` and `ACK: Violet`; the status then changed from one waiting agent to zero and removed the card. The executable SHA-256 was `3617f436373496630d92b96fbd2986510b9a63cfea2657eccd4efffe271541eb`. Deep signature verification passed. This was a local signed build, not a newly notarized public release.

The post-answer transition issue discovered in the installed Codex test is addressed by the Claude adapter change: confirmation tolerates a disappearing question screen, and a racing preview failure cannot replace delivery feedback. See the Claude document for the regression and verification record.

Next: obtain Herdr conditional delivery; independently verify additional provider layouts and exact approval scopes. Persistent question history is out of scope.

References: https://herdr.dev/docs/agent-automation/ and https://herdr.dev/docs/socket-api/ (checked 2026-09-16).

## Layout lesson

The first compact render clipped the answer rows even though logic and build checks passed. A scroll region constrained only by maximum height compressed to almost zero beside launcher results. Give the answer viewport a content-based fixed height and prioritize the attention card; keep results scrollable. Inspect compact as well as default/large captures after adding content above the result list. Rendering is automated by the Actions fixtures; inspection remains manual.
