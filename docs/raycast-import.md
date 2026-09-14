# Raycast import

Settings → Import from Raycast reads a schema-3 `RAYCFG3` export. Choose the file, enter its password in the native secure field, review the report, select categories, and import. The password is used in process memory and never saved, logged, or passed to another process. The source archive is read-only; no decrypted temporary export is written.

Supported mappings: snippets, basic quicklinks, installed-application aliases and hotkeys, and notes with explicit Markdown or plain-text fields. Existing names, keywords, URLs, aliases and app bindings win collisions. App hotkeys start unchecked. They toggle activate/hide in Volant, and users must resolve bindings still owned by Raycast. Unrecognized snippet placeholders stay literal; supported date/time placeholders use Volant formatting. Quicklinks support a single `{Query}` → `{query}` parameter and default-app opening; unsupported parameters/schemes are skipped. Rich note representations are reported and skipped rather than guessed.

Clipboard history, extension runtimes/commands, AI sessions, global shortcuts, favorites, and other settings are not migrated in this version. Older encrypted formats are rejected explicitly. Input is capped at 64 MB, expanded payload at 128 MB. Compatibility with the owner's actual decrypted export remains unverified until they enter the password locally.

Before any mutation, a unique `Raycast-Import-<UUID>` recovery folder stores the exact original config and lists planned note additions. Config is revalidated against preview bytes, unknown fields are preserved, note names derive from imported content, and no existing note is overwritten. Failed note/config writes remove only newly created notes. Process termination or a rollback failure requires following Recovery.txt; this is not a multi-file atomic transaction. Recovery backups contain the same local settings/snippet data as the original config and remain until removed by the user.

Implementation is independent; Tinycast's public format documentation was consulted for interoperability, but its AGPL source was not copied. Key derivation follows RFC 7914 using system PBKDF2; CryptoKit handles authenticated decryption and system zlib handles bounded decompression.

## Evidence and follow-up

- `tools/check-raycast.sh`: synthetic Python cryptography archive + Swift reader, RFC vector, wrong password/tampering, framing, duplicate/unsupported mappings, unknown settings, stale preview, selection, recovery, and partial-write rollback. Requires Python cryptography. No personal fixture is committed.
- `tools/render-raycast.sh`: actual AppKit controller under Aqua/Dark Aqua, empty and selected states, 660-point and compact 560-point widths; secure-field presence and isolated import button action. Inspected renders. This does not prove the installed NSOpenPanel/security-scoped URL or password keyboard path.
- Release build passed. Computer Use could not initialize because its runtime still references the old workspace location.
- Next: verify a real archive locally, add the actual rich-note representation if necessary, then add clipboard migration as a separate bounded feature.

Recurring lesson: transparent native content captures can hide a missing semantic background. Draw the window background using the effective appearance, invalidate it on appearance changes, and inspect both themes; a compile is insufficient evidence.

Review follow-up: the decoder now rejects non-ASCII hexadecimal headers without indexing by grapheme count. Imported aliases normalize case and store exact app paths, reserved launcher names are reported, and appending to raw existing JSON arrays preserves nested unknown fields. The focused suite now has 30 checks with expected-error matching. The signed release is installed; the native importer window was verified open, but no personal archive has been decrypted during development.
