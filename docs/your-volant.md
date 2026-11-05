# Your Volant (local usage stats)

Prototype, November 5, 2026. Settings › Your Volant shows the owner their own launcher use, built
only from data on this Mac. Volant still has no telemetry: these numbers live in the `usage.sqlite` file that already held the
launcher ranking, and are never sent anywhere, logged, synced or included in backups.

## What it shows

- **Last 30 days:** launcher choices, active days, the current day streak (counted from today, or
  from yesterday when today has no choices yet) and the busiest day, over one bar per day.
- **Most used lately:** up to five apps, commands and extensions by the launcher's own frecency
  ranking, which halves every seven days. These are recent favorites, not lifetime counts.
- When daily counting began, and **Clear Activity History…**, which forgets the daily counts and
  keeps the ranking.

## What it reads

| Source | Holds | New? |
| --- | --- | --- |
| `usage` table | Ranking key, frecency score, last use | Existing |
| `daily_use` table | Local day (`yyyy-MM-dd`) and a count | New in this change |

`daily_use` is incremented in `UsageStore.record`, the same call that updates the ranking, so it
counts the same choices the ranking learns from: apps, commands, files, notes, clips, snippets,
quicklinks and extension runs. Calculator answers, extension results, Apple Shortcuts, servers,
connectivity rows and new notes are not recorded by the ranking and are not counted either. The
table stores no key, query or item: only a day and a number. Days older than 400 are dropped when
the store opens.

Lists show only apps, commands (`core:`, `system-action:`, `command:`) and extensions. Files,
contacts, events, clips, notes and snippets are left out, since their keys carry paths or content.
An app that no longer exists or an extension that is no longer installed is skipped.

Settings reads the file through a read-only SQLite connection each time the section appears and
holds no live connection. The aggregation is `VolantCore.UsageStats`.

## Evidence and limits

- `UsageStatsTests` (Core): day keys in a fixed time zone, the 30-day window, busiest day, streaks,
  per-kind filtering that leaves private kinds out, extension runs merged by extension, decay and
  limits.
- `UsageActivityTests` (app): counting through `UsageStore.record`, the read-only snapshot, clearing
  daily counts while the ranking stays, and a missing store reading as empty without creating it.
- The Settings preview (`tools/settings/main.swift`) seeds fictional usage and renders the section
  and its scrolled bottom in light and dark through `tools/render-vm.py`; the Actions fixture's
  Settings walk reads an empty isolated store and shows the empty state.
- The extra sidebar row made the section list taller than the 680×500 fixture window, so the sidebar
  now scrolls to a section chosen from code (the launcher's What's New item, the fixture), and the
  fixture's bottom capture scrolls only the detail pane.
- Daily counts start with this build, so existing owners see one day of history at first while the
  ranking lists are already full.
- Day keys use the Mac's current calendar and time zone when a choice is recorded; travel across
  time zones can put a late choice on a different day.
