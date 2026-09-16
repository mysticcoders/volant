# Local opening-speed benchmark

Opt-in: `tools/profile-opening.sh /tmp/volant-opening-NEW` while the installed Volant is running. It performs 20 hide/reopen trials, then five clean quit/start trials, leaving the app running. Complete active work first: clean quit flushes notes but ends Caffeinate and disconnects native sessions. The tool never force-quits, edits configuration, posts keys, captures pixels or logs app content. It is not run in CI.

The optimized helper timestamps `NSWorkspace.openApplication` with the monotonic system clock and polls WindowServer at nominal 2 ms intervals. A visible target must match Volant’s PID, floating window level, launcher aspect ratio, minimum size and nonzero alpha. Ordinary Settings and auxiliary windows must not count. Each trial starts with the panel hidden or the previous process confirmed terminated. Open errors, unmet preconditions and visibility timeouts fail the run.

The end condition is **window-server-visible**, not a presented screen frame, completed search/indexing or proven keyboard readiness. This is an application open/reopen request, not the global hotkey path. Results cannot be compared directly with shortcut-to-first-visible-frame measurements from other machines or apps. The startup trials create a fresh process with warm filesystem/OS caches, not a post-reboot cold launch. Normal show-on-launch must be enabled.

The helper initializes AppKit without taking activation. It samples only the target process’s window metadata; it does not capture the screen or inspect other applications’ window contents. Polling and normal host load add measurement overhead/jitter. A callback does not gate detection: the known process is observed immediately for reopens, and fresh processes are discovered while the launch callback is pending.

Output: raw CSV, nearest-rank p95/median/range summary, exact installed executable SHA-256, benchmark source SHA-256, version and hardware/OS metadata. `python3 tools/launch-speed/summarize.py OUTPUT_DIRECTORY` validates complete trials and regenerates summaries. Five startup samples are too few for a robust tail estimate. Never discard first-trial outliers without stating it; repeat complete runs before making performance claims.

Validation is opt-in compile/run plus CSV completeness checks. `Scripts/test.sh --base origin/main` remains the normal repository check; profiling tools select native checks but no UI jobs because product UI is unchanged.
