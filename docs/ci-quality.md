# Pull request checks and UI scope

All changes go through a branch and pull request, successful checks on the final commit, merge, then a fast-forward back to main. Deployment and release distribution remain separate actions.

The `PR checks` workflow always starts, including docs-only PRs. Its scope job uses `tools/test-scope.py`, shared with `Scripts/test.sh`, to decide which jobs to run. Docs-only changes skip native and UI work. Backend and test-infrastructure changes run build/logic checks. UI paths include views, panels, controllers, launcher/agent interaction models, routing, assets, startup and UI fixtures. New surfaces require a classifier update. Paths cover deletions and both sides of renames. CI compares the PR merge base to its head; local selection additionally includes staged, unstaged and untracked files. Missing base references fail rather than silently skip checks.

`PR gate` succeeds only when scope succeeds and every selected job succeeds. Unselected jobs must be skipped. It avoids path-filtered workflows leaving required checks pending. Workflow jobs have read-only tokens, concurrency cancellation and timeouts; they do not sign, notarize, publish or require owner secrets.

`Scripts/test.sh --ui never` runs non-UI logic/persistence tests and builds the host. Notes rendering and LiveMarkdown native editor tests are excluded from that run. `--ui only` runs the launcher native suite and the excluded UI tests. `--ui always` combines them. Fake ACP, Raycast import, volume and migration checks remain in the non-UI run. Test-host startup is isolated using the scheme's VOLANT_UNIT_TESTING environment, before AppDelegate constructs owner services. This infrastructure change touches startup, so its initial PR deliberately selects the UI job too.

Regression checks: `python3 tools/test-scope-tests.py` covers docs/backend/UI/mixed/deleted-path classification. Build/test logs and xcresults are uploaded by each macOS job. UI images prove rendering only; inspect changed surfaces locally and track signed installed-app/hardware verification separately. Preview automation is not warranted for unrelated docs/backend changes.

Next gaps: split mixed launcher model/UI tests into smaller suites to reduce UI-job cost; extend affected-surface selection within the UI job; add release signing/notarization automation separately. Feature tickets: Caffeinate #9 and native translation #5. /Applications held 0.1.0 build 1 at audit time; the latest development build was 0.1.2 build 4 in build/Build/Products/Release, not an updated installed/notarized distribution.
