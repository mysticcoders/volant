# Claude responses through Herdr

The Claude adapter recognizes observed single-select AskUserQuestion screens, Create file approvals with a complete displayed diff, and Bash command approvals. It preserves the provider's labels and full approval scopes. It does not turn “switch to accept edits for this session” into a vague “Always”. Free text, notes, multi-select/multiple-question forms, unrecognized approval layouts, and clipped requests retain Open in Herdr. Existing-file edit dialogs are not yet verified.

Approval context is displayed as literal selectable text above the choices in a scrollable card. The full context participates in the response fingerprint; cosmetic separator lines alone are omitted from display. Long labels wrap, including the complete session-wide scope. Native answer buttons and the explicitly focused ⌥⌘number shortcuts use the same single-use token path as Codex. Nothing is approved merely by opening the card or pressing Return in launcher search.

The controller revalidates pane, terminal, provider/session, blocked-state sequence and screen fingerprint, navigates separately, confirms the selected row, then sends Enter. Claude-specific parsing does not add a generic input API. Herdr still lacks atomic conditional input: a last read/send race remains. Custom keybindings, unrecognized screens and uncertain delivery need manual pane review; no automatic resend is attempted.

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
