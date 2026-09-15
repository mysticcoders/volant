# Native Focus sessions: feasibility and next steps

Raycast's [Focus feature](https://www.raycast.com/core-features/focus) combines a goal and duration, app/site block lists, pause and per-item snooze, editable sessions, and a floating timer. It advertises browser support without an extension and restoration of tabs. This is a behavioral reference, not evidence of how Raycast implements blocking. No implementation was copied.

Volant can own goal/timer state, reusable preferences, pause/resume/end commands, and a movable compact status panel. Focus and Caffeinate should remain independent; a Focus session must not silently keep a computer awake. A timer alone must not be marketed as distraction blocking or as macOS Focus/Do Not Disturb integration.

## Implementation sequence

1. Session engine and launcher controls: one goal, bounded duration, pause/resume/end, explicit completion, optional compact timer, and state recovery that asks before restoring a session. Fake-clock tests cover sleep/wake, expiration, cancellation and stale callbacks. No browsing history in saved state.
2. Opt-in app deterrence: investigate workspace activation observation and a non-destructive reminder for selected app bundle IDs. Never terminate apps, discard documents, or promise launch prevention from observing an app after activation. Validate signed sandbox behavior before claiming support. Use fictional apps for automated tests.
3. Browser blocking spike: prove one supported browser before shipping a broad browser-support claim. Evaluate a browser extension for precise tab/domain matching and per-site snooze against a macOS Network Extension system extension for network filtering. Safari content blockers are another browser-specific option, with declarative rules but no browsing history visibility. Existing loaded pages and network requests are different concerns.

Apple's [Network Extension deployment guide](https://developer.apple.com/documentation/technotes/tn3134-network-extension-provider-deployment) supports content-filter system extensions on macOS 10.15+. Direct Developer ID distribution is supported; packaging, signing, entitlements, activation and user approval need separate verification. The newer URL filter provider requires macOS 26, so it cannot be the only implementation for Volant's macOS 15 baseline. Do not assume iOS Screen Time APIs are a drop-in Mac blocker.

[Safari content blockers](https://developer.apple.com/documentation/safariservices/creating-a-content-blocker) supply compiled blocking rules rather than observing browsing history. They alone don't provide cross-browser tab restoration. An Accessibility/browser-automation alternative would need permission and per-browser adapters; investigate it only with explicit supported-browser tests. Do not add wide Accessibility or Automation privileges merely to deliver a timer.

## Acceptance criteria before a blocking release

- Exact domain/subdomain rules and internationalized host handling; no substring matching such as `example.com.evil.test`.
- Pause, snooze, end, timeout, permission revocation and crash/relaunch restore access predictably; filter cleanup never leaves the owner locked out.
- Preserve tabs, unsaved forms and app documents. Avoid changing hosts files, killing applications, or rewriting browser tabs for a prototype.
- Store chosen block rules locally, not a browsing history. No telemetry of visited URLs.
- Test supported browsers, existing/new tabs, private mode, multiple windows, multiple profiles and offline states separately. Clearly label unsupported browsers.
- Verify light/dark controls, keyboard and accessible names; installed signed/notarized verification is separate from fixture rendering.

Next concrete gap: a bounded signed sandbox spike for app reminders and one browser's temporary domain blocks. No Focus session or blocker is implemented by the Caffeinate/emoji change.
