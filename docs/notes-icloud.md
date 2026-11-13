# Notes in iCloud Drive

Notes sync rides on the existing per-Mac switch, now labeled "Sync settings and notes with iCloud".
It stays off by default, and Volant has no telemetry, so nothing about who turns it on leaves the Mac.

## Where notes live

- Off: `Application Support/Volant/Notes`, as before.
- On: `Documents/Notes` in the iCloud container `iCloud.com.mysticcoders.volant`. The container is
  public (`NSUbiquitousContainers` in project.yml), so Finder shows it as iCloud Drive › Volant ›
  Notes. Volant for iPhone (the `volant-ios` repo) uses the same container and folder.

Notes stay plain Markdown files with the same names, so pins and the remembered note carry over by
copying their per-folder UserDefaults keys.

## Turning it on and off

`NotesICloudSync` follows the switch on launch and on every configuration reload.

- On: copy local notes into iCloud (an existing iCloud note wins unless the local one is newer), move
  the store, copy again after flushing so an edit made during the move is kept, then rename the local
  folder to `Notes before iCloud <timestamp>`. The local folder is set aside only when every note
  copied; otherwise it stays and Settings says how many did not.
- Off: only on a Mac whose notes were in iCloud. Copy the iCloud notes (coordinated reads download any
  that are not on this Mac) back into the local folder and move the store there. iCloud keeps its
  copies for other devices. If iCloud cannot be reached, the store returns to the local folder and
  Settings explains that the iCloud notes were not copied.
- Either move refuses while a note's save is failing, so an unsaved edit is never stranded.

Notes whose contents are not on this Mac yet (an iCloud placeholder, or a dataless file under
Optimize Mac Storage) are listed as "Downloading…" from their directory entry and are never read: a
plain read would block until iCloud delivers the file. Opening one shows "Downloading from iCloud…"
instead of an editor, edits are refused until it arrives, and full-text search skips it. Volant for
iPhone does the same; the phone stalled at launch before it did.

Writes and copies go through `NSFileCoordinator`. A metadata query watches the iCloud folder, asks
for notes from other devices to download, and reloads the list. Backup export/import and the Raycast
import read `NotesLocation.current`, so they use whichever folder is active.

## Signing

Release builds need the iCloud Documents container on the `com.mysticcoders.volant` App ID and a
regenerated "Volant Developer ID" profile before this ships. Debug ("Volant Dev") builds carry no
iCloud entitlements, so they keep notes local; `tools/check-dev-entitlements.py` strips the container
entitlements along with the key-value one.

## Evidence and limits

- `NotesICloudSyncTests` covers copy precedence, the backup rename, on/off moves with pins, the
  unavailable-iCloud path, refusal during failing saves, and a note still in iCloud being listed but
  never read, edited or searched until it arrives, against temporary folders.
- Real iCloud, November 8, 2026: a Developer ID export of this branch moved the owner's 149 notes into
  iCloud Drive › Volant › Notes on launch with the switch already on, and Volant for iPhone listed
  them. The dataless-file path itself has not been exercised on a Mac with Optimize Mac Storage.
- Not yet verified against real iCloud: a signed Release build with the container, two-device sync
  with the iPhone app, conflicting edits made on two devices at once (the last writer wins; iCloud's
  conflict versions are not surfaced), and Optimize Mac Storage evicting notes.
