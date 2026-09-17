# Chat presentation

Assistant responses use the shared native Markdown block renderer inside the transcript's single scroll view. Headings, emphasis, links, lists, quotes and fenced code are formatted; unfinished code fences render during streaming. User prompts and tool summaries remain literal. No remote images or web content are loaded. Code blocks retain explicit copy controls. This is the existing lightweight Markdown subset, not full CommonMark tables or nested lists.

The native composer sends on Return or keypad Enter; Shift-Return inserts a newline. Command-Return remains compatible. Only the focused editor handles these keys. Marked text is passed to AppKit so input-method confirmation cannot submit a prompt, and repeating Return does not submit again. The model continues to reject empty drafts and submissions while a turn is pending.

Symptom: provider Markdown appeared as raw punctuation, and Return unexpectedly inserted a line break. Cause: plain transcript Text and a multiline editor with only Command-Return interception. Prevention: reuse the existing block renderer without nesting scroll views, and keep submission handling in the native editor rather than attaching a global default button.

Automated evidence lives in the branded native Actions fixture: multiline editing and undo, Return submission, empty drafts, marked-text confirmation, streamed unfinished/completed Markdown and draft preservation. It runs in headless Tart in both appearances and three sizes; rendered images require separate visual inspection. Existing Markdown parser tests cover fences, lists, headings and copy text. These fixtures do not establish a real provider login or signed installed-provider response.

Next gap: richer Markdown tables and nested list formatting, if provider responses make them necessary.

## Tab and summon navigation

Plain Tab in the main search editor opens AI Chat; a visible AI Chat ⇥ button exposes the same action. If its draft is empty, search text becomes an unsent prompt. Existing drafts are never overwritten. Tab in specialized search surfaces, Actions, forms or chat retains native focus behavior; Shift-Tab and marked text are not intercepted. Unconfigured chat opens AI Settings through the existing route.

Summoning a hidden chat, or a still-visible chat after focus loss, returns to an empty launcher. The ACP model is not reset: its session, transcript, draft, active turn and permissions remain in memory. Tab or the conversation strip resumes it. This does not introduce persistence across app restarts.

Regression prevention: distinguish presentation reset from provider disconnect. The native fixture checks both hidden and visible-inactive summons, search focus, draft preservation and a working turn. UI tests run in Tart, not on the owner's desktop.
