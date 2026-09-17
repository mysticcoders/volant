# Herdr attention and Codex answers

A pinned Herdr status shows one waiting agent below the status strip, with previous/next controls. Unsupported prompts retain a bounded, literal terminal preview and Open in Herdr. Hidden launchers release the preview; question text is never persisted or logged.

Verified Codex single-choice questions show the question and the provider's actual option labels/descriptions. Click an option to answer. Answer with keyboard explicitly focuses the card; ⌥⌘ plus its option number answers only while that area has focus. Return in launcher search is not an approval shortcut. Notes and None of the above require Open in Herdr. Permission dialogs, wrapped/unrecognized screens, and other providers have no response buttons. This is not a general Yes/Always/No adapter.

The signed helper exposes read and token-plus-choice methods, not arbitrary keys or shell input. It reads up to 80 detection lines, validates pane/terminal/provider/session identity and blocked-state sequence before and after reading, and issues a 30-second single-use token. The question fingerprint includes progress, title and every choice. Answering consumes the token, revalidates the current question, moves the selection, rereads to confirm the selected row, then sends Enter separately. Changed questions or occupants stop submission. A consumed question cannot be submitted again through a newly refreshed token in the same helper session. Display excerpts remain limited to 30 lines/4,000 characters.

After Enter the helper checks whether Codex resumed, acknowledged the answer, or advanced to another question. Key delivery alone is not reported as acknowledgement. Timeouts/errors produce an uncertain-delivery message and no automatic retry. The helper's serial queue prevents overlapping response operations; the UI also disables responses while sending.

## Remaining transport limitation

Herdr 0.9.0 / protocol 22 has no conditional send operation accepting an expected terminal/session and prompt revision. Separate reads and sends cannot eliminate the final read/send race, including changes made directly in the terminal. Provider session identity is absent in the tested Codex metadata; terminal identity plus state sequence and fingerprint provide the available guards. A future conditional response API is needed for an atomic guarantee. Do not expand this adapter to permission approvals based only on matching words such as Yes or Always.

## Evidence and next work

On 2026-09-17, Codex CLI 0.154.0 in a disposable empty-directory Plan session asked a real `request_user_input` question about fictional Amber/Violet themes. Explicit agent key delivery selected Violet; Codex showed `answer: Violet` and returned `ACK: Violet`. The production response controller then independently read and answered a second real question and observed Codex resume. This establishes the terminal/controller path, not installed-app XPC or mouse/keyboard behavior.

Automated unit checks cover the observed screen, unsupported/truncated forms, changed pane/state/question, changes after navigation, token expiry, unsupported notes answers and duplicate submission. Branded headless UI fixtures cover loading, choices, pending/acknowledged delivery, fallback errors and resolution in light/dark at three sizes. Installed signed-app delivery and focused card shortcuts require separate smoke evidence.

Next: verify the signed installed UI/helper path and scoped shortcuts; obtain Herdr conditional delivery; independently verify additional Codex formats and Claude permissions while preserving the exact provider scopes. Persistent question history is out of scope.

References: https://herdr.dev/docs/agent-automation/ and https://herdr.dev/docs/socket-api/ (checked 2026-09-16).

## Layout lesson

The first compact render clipped the answer rows even though logic and build checks passed. A scroll region constrained only by maximum height compressed to almost zero beside launcher results. Give the answer viewport a content-based fixed height and prioritize the attention card; keep results scrollable. Inspect compact as well as default/large captures after adding content above the result list. Rendering is automated by the Actions fixtures; inspection remains manual.
