# Claude responses through Herdr

The Claude adapter recognizes observed single-select AskUserQuestion screens, Create file approvals with a complete displayed diff, and Bash command approvals. It preserves the provider's labels and full approval scopes. It does not turn “switch to accept edits for this session” into a vague “Always”. Free text, notes, multi-select/multiple-question forms, unrecognized approval layouts, and clipped requests retain Open in Herdr. Existing-file edit dialogs are not yet verified.

Approval context is displayed as literal selectable text above the choices in a scrollable card. The full context participates in the response fingerprint; cosmetic separator lines alone are omitted from display. Long labels wrap, including the complete session-wide scope. Native answer buttons and the explicitly focused ⌥⌘number shortcuts use the same single-use token path as Codex. Nothing is approved merely by opening the card or pressing Return in launcher search.

The controller revalidates pane, terminal, provider/session, blocked-state sequence and screen fingerprint, navigates separately, confirms the selected row, then sends Enter. Claude-specific parsing does not add a generic input API. Herdr still lacks atomic conditional input: a last read/send race remains. Custom keybindings, unrecognized screens and uncertain delivery need manual pane review; no automatic resend is attempted.

## Footer recognition follows Herdr's rules

Volant reads the pane through `herdr agent read --source detection`, so the region it parses is
already the one Herdr's detection engine selected. What it then does with that region used to pin
the exact footer strings the agents print:

```swift
lines[footer] == "Enter to select · ↑/↓ to navigate · Esc to cancel"
```

Those are UI strings and they change between agent releases. Herdr tracks that in versioned
manifests under `~/.local/state/herdr/agent-detection/`, which it updates; an equality check here
silently stops matching at the same moment, so a real question becomes unparseable while Herdr
still correctly reports the pane blocked. That is a false negative with no signal attached to it.

The checks now mirror Herdr's own rules, case-insensitively:

- Claude select forms follow `live_blocked_form` in `claude.toml`: "esc to cancel" together with
  "enter to confirm", or with "enter to select" and any of five navigation spellings.
- Claude approval screens are recognized separately by "esc to cancel" with "tab to amend", since
  that path decides whether a screen is a file or command approval rather than a question.
- Codex follows `live_strong_blocker` in `codex.toml`: "enter to submit answer", "enter to submit
  all", or "press enter to confirm or esc to cancel".

This is a guard that the region is an interactive form, not the detector. Herdr has already
reported the pane blocked before Volant reads it, and answering remains gated by the choice
structure, the fingerprint, the pending token and the answerable-choice filter, none of which
were loosened.

Not adopted: reading Herdr's manifest files directly. They are versioned and would track upstream
changes automatically, but their path and TOML shape are Herdr internals rather than a published
interface. Herdr does not expose a parsed question over its API either — the schema carries agent
state and the detection region, not choices — so the structure has to be derived here.

## Codex asks two different kinds of question

The numbered survey form has a `Question 1/1 (1 unanswered)` header and two-column options. The
approval form has neither: it asks "Would you like to run the following command?", lists options in
a single column, and ends with "Press enter to confirm or esc to cancel". Only the survey form was
ever parsed, so an approval screen was detected as blocked, showed its excerpt, and then offered
nothing to answer — the reported symptom of seeing a question but not being able to reply to it.

`parseCodexApproval` handles the approval form and is tried first, falling back to the survey
parser. Prompt wording is matched by substring against what Herdr's `codex.toml` recognizes
("allow command?", "do you want to") plus the observed run-command phrasing, for the same reason
the footers are: these are UI strings that get reworded.

Approving one of these runs a command, so the guards match the Claude approval path rather than
being relaxed for convenience. The prompt must be present, the command block must not contain an
ellipsis, exactly one option may carry a selection marker, the numbering must be contiguous, and a
wrapped option is only joined when its continuation is indented. Anything unrecognized is refused
rather than guessed at.

Verified against a real blocked pane as well as fixtures: the live screen parsed to three
answerable options with the first selected.

## Evidence

Claude Code 2.1.274 was tested in a disposable directory with customizations disabled and explicit ask rules for the test tools. A real single-select fictional Amber/Violet question accepted Violet. In standalone terminal tests, No rejected a fictional file creation and left the file absent; Yes created only the fictional file and Claude returned `ACK: written`.

An explicitly approved disposable Herdr workspace then hosted Claude. The production controller approved only the observed harmless `printf 'VOLANT_CLAUDE_OK\n'` command and observed Claude resume; Claude returned `ACK: command completed.` The controller selected Violet in a real Herdr question; Claude returned `ACK: Violet`.

That question revealed a confirmation race: after Enter, the agent could leave blocked state between the list/read checks, causing a pre-submission-style “question changed” error despite successful delivery. Confirmation now retries observation only, never input. A regression test covers that transition. The model preserves the delivery result during a racing failed preview refresh and clears it when a new question arrives.

Builds/unit tests, headless Tart native interaction fixtures, visual inspection and installed signed-app smoke are separate evidence. Final check and installation results are recorded in the implementation PR. The broader session-mode option is shown with its exact label; the real tests intentionally exercised per-request Yes/No rather than changing the owner's permission defaults.

## Follow-up

- Verify existing-file edit, plan approval and multiple-question/multi-select layouts independently.
- Obtain Herdr conditional response delivery tied to an expected request/revision.
- Verify custom keybindings and wider terminal-layout variants; unsupported forms must continue to fall back.

References: [Claude keybindings](https://code.claude.com/docs/en/keybindings), [permission modes](https://code.claude.com/docs/en/permission-modes), [AskUserQuestion behavior](https://code.claude.com/docs/en/tools-reference#askuserquestion-tool-behavior), checked 2026-09-17.
