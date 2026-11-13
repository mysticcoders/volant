# Search Menu Items

November 7, 2026. Merged after 0.3.36; not in the current download. The owner approved this design,
including the change to the Accessibility promise: Volant asks for no Accessibility grant unless the
owner chooses Type at the cursor or Search Menu Items.

Search Menu Items lists the menu items of the app that was in front when the launcher appeared,
filters them as the owner types, and presses the chosen one. The main app never uses Accessibility;
the reads and the press happen in `VolantInputHost`, the same unsandboxed helper that types dictation
at the cursor (see [dictation at the cursor](dictation-at-cursor-design.md)).

## Turning it on

Settings › General › Menu Items has a **Search Menu Items** switch, off by default. It is stored as
`searchMenuItems` in config.json through a narrow patch that keeps other fields, per Mac, and is not
in `SettingsSync.keys`, because it depends on this Mac's Accessibility grant.

- While the switch is off, nothing talks to the helper for menus, and the launcher captures no target.
- Turning it on asks the helper for its status with the system prompt (`MenuItemsAccess.chose(true)`).
  macOS shows the prompt only if Volant isn't already allowed, for example through Type at the cursor.
  Both features use the one "Volant" entry in Privacy & Security › Accessibility.
- Later visits to Settings, and Volant becoming active again, check without prompting.
- Turning it off disconnects the helper unless Type at the cursor still uses it (dictation output is
  Type, or a dictation is typing). Settings then explains how to remove the grant, as Type at the
  cursor does. `AppDelegate.reloadConfig` also disconnects only when neither feature uses the helper.

## In the launcher

Typed phrases: `menus`, `menu items`, `search menus` and `search menu items`, each optionally followed
by a filter (`menus export pdf`). They are matched longest first (`MenuItemsQuery`) and reserved in
`LauncherRouting.isReserved`, so aliases and shortcuts cannot take them. `menu bar` is not one of them
and stays the Toggle Menu Bar Hiding command. The Search Menu Items command row (`CoreCommand.menuItems`)
fills in `menus`.

- **Switch off:** one row, Turn On Search Menu Items; Return opens Settings › General.
- **Target:** when the launcher panel appears, `LauncherPanel.toggle` captures
  `NSWorkspace.frontmostApplication` (pid, bundle identifier, name, bundle path), only while the switch
  is on. The panel is non-activating, so the owner's app stays in front while the launcher is open.
  Volant itself and apps without a bundle identifier are never targets; the launcher then explains
  that the command works on the app you were using.
- **Reading:** the first `menus` query of a launcher session asks the helper once. A failed read is
  not retried until the next summon, so a refusing helper is never asked in a loop.
- **Rows:** the item's title; the menus that lead to it as the subtitle, such as "File › Export"; the
  keyboard shortcut as a small badge (from `AXMenuItemCmdChar` and `AXMenuItemCmdModifiers` only, so
  items whose shortcut is a glyph-only key, such as arrows or function keys, show none); the target
  app's icon. Rows that have no shortcut have no badge.
- **Disabled items** are shown dimmed and ranked after enabled ones; Return on one says it isn't
  available instead of pressing. They stay visible so the owner can see why a command does nothing
  right now, rather than wondering whether it exists.
- **Filtering** (`MenuItemSearch`): `FuzzyMatcher` on the title with a 20-point bonus, and on the whole
  path for the rest, so `export` finds File › Export › PDF; ties keep menu order; at most 300 rows.
- **Notices:** reading, nothing matches, no items, a refusal's reason, or the helper not answering.
  When Accessibility is off, the list shows Open Accessibility Privacy Settings with the reason in the
  footer. A list cut short by a limit says how many items it shows.

### Pressing

Return on an enabled item hides the launcher, activates the captured app again (only if its pid still
runs the captured bundle), waits 0.2 seconds, and asks the helper to press the item by its title path.
If the helper refuses or doesn't answer, the launcher comes back on `menus` with the reason in the
footer. Nothing about the press is recorded in learned ranking.

## Helper API

Two calls were added to `VolantInputHostProtocol` (Core/Sources/VolantCore/Dictation/InputHostProtocol.swift),
making six:

```swift
func menuItems(pid: Int32, bundleID: String, reply: @escaping (Data) -> Void)          // MenuItemsReply
func pressMenuItem(pid: Int32, path: Data, bundleID: String, reply: @escaping (Data) -> Void) // MenuPressReply
```

`path` is a JSON array of strings, at most 4096 bytes, so no Objective-C collection crosses the
connection; anything else is refused before the menus are touched. Replies are JSON: `MenuItemsReply`
(`items` of `{path, shortcut?, enabled}`, `truncated`, `refusal?`) and `MenuPressReply` (`pressed`,
`refusal?`). The app decodes listing replies up to 4 MB and press replies up to 4 KB.

Neither call accepts attribute names, element references, key codes or modifier flags. The helper's
rules live in `MenuItemsController` (VolantCore), tested with fake trees; `SystemMenus` and
`AccessibilityMenuNode` (VolantInputHost/SystemMenus.swift) are the only Accessibility code. They read
the app's `AXMenuBar`, each element's `AXChildren` (to reach the submenu), and in one round trip
`AXTitle`, `AXEnabled`, `AXMenuItemCmdChar` and `AXMenuItemCmdModifiers`. The press is `AXPress` on the
resolved item. No values, descriptions, windows or other attributes are read. Each element gets the
same 1-second messaging timeout as typing.

Both calls re-check, at the moment of use, in this order: the request is well formed (pid above zero,
a plausible bundle identifier, for presses a path of 2 to 4 titles already in normalized form); the
target is not the caller and not an excluded bundle; Accessibility is trusted; the pid still runs the
same bundle identifier, which is not excluded; it is a regular app; and it is frontmost, confirmed by
its own `AXFrontmost` as typing does. A press then resolves the path by title from the menu bar down,
skipping the Apple menu, and refuses a path that no longer matches (`notFound`), leads to a submenu
(`notFound`), or ends at a disabled item (`disabled`).

Limits (`MenuItemPolicy`): paths of at most 4 titles from the menu bar down; 2000 items; titles cut to
100 UTF-16 units, the same way on both sides so a press by a cut title still resolves; a 3-second
budget per listing. A listing that hits the item count or time limit is marked `truncated`; menus
deeper than the limit are skipped. Separators (empty titles) and duplicate paths are dropped.

## What is refused, and why

- **The Apple menu** is never listed or pressed. Its items act on the whole Mac (Shut Down, Restart,
  Log Out, Force Quit, Sleep, Lock Screen, System Settings), not on the app, and a mistyped Return
  there costs far more than the convenience is worth. It is identified by position, the first menu bar
  item, not by its localized title; a press whose first title matches only the Apple menu is refused
  with `appleMenu`.
- **The app's own Quit** and other app menu items are allowed: pressing them is the same as the
  owner choosing them or pressing their shortcut, such as ⌘Q.
- **Volant and its helpers, loginwindow and SecurityAgent** are refused (`excludedApp`): Volant would
  be reading itself, and the login window and the security agent draw system and password prompts.
  So are processes that aren't regular apps.
- Status menus (menu extras) are a separate menu bar and are not read.

## Privacy

Menu titles can include document names (Open Recent, the Window menu). They are kept only in
`MenuItemsModel`, in memory, from the first `menus` query until the launcher is dismissed or summoned
again, when they are cleared along with the rows that show them, and a reply that arrives after
dismissal is dropped. They are never logged (the helper logs nothing about menus), persisted, written
to config or backups, synced, included in diagnostics or activity, or recorded in learned ranking.

## Validation

- `MenuItemsControllerTests` (VolantCore, fake Accessibility tree): listing with paths, shortcuts and
  enabled state without the Apple menu; presses by path; Apple menu refusal; changed, missing,
  submenu, disabled and failed presses; malformed paths never read the menus; trust, front app, pid
  reuse, gone and non-regular processes for both calls; Volant, loginwindow and SecurityAgent; no menu
  bar; item, depth and time limits; cut titles; duplicates; JSON round trip.
- `MenuItemsQueryTests`: phrases and filters, reservation, `menu bar` untouched, the command row,
  ranking, shortcut display, the switch off by default, outside `SettingsSync.keys` and patched without
  losing unknown fields.
- `LauncherMenuItemsTests` (fake helper): the row while off, listing and filtering, the press flow,
  refused and unanswered presses, disabled items, Accessibility off, refusals, no target, truncation,
  clearing on dismissal and dropping a late reply, nothing written to usage or other files, the
  command row, and the switch's prompt and disconnect rules.
- `tools/check-input-confinement.py` keeps Accessibility APIs, including the menu read and press
  calls, inside `VolantInputHost/`.

- Native fixture renders (`tools/render-vm.py`, macOS 27 guest, November 7, 2026), inspected in
  light and dark: the Actions fixture's `menu-items-off` (the Turn On row), `menu-items` (nine
  fictional items for an app called Quill, with paths, shortcut badges and the disabled Make Rich Text
  dimmed and last) and `menu-items-filtered`, plus Return hiding the launcher and pressing by path
  through a fake helper; the Settings preview's General section with the switch off, on without
  Accessibility and on with it. The first run showed "Checking…" for both on states: the preview's fake
  helper queued its reply on the main queue, which the render loop never drained. It now answers at
  once, the preview fails unless the expected state shows, and quiet re-checks keep the last answer
  so Settings doesn't flash "Checking…" when the section scrolls back into view.
- Real Accessibility, only in a disposable clone of `volant-ui-xcode` (macOS 15.7.7), with
  `tools/input-host-e2e/run-vm.py --only menus` and the Developer ID signed helper. Before the grant,
  listing TextEdit was refused as `notTrusted`. After it, TextEdit listed 171 items under TextEdit,
  File, Edit, Format, View, Window and Help in 264 ms, with no Apple menu, real shortcuts (⇧⌘T, ⌥⌘C,
  ⌘{) and disabled items reported as such. Pressing Format › Make Rich Text on a plain-text document
  returned `pressed`, and UI scripting read Format's item change to Make Plain Text. Pressing the old
  title again was refused as `notFound`, Apple › About This Mac as `appleMenu`, the Format › Font
  submenu as `notFound`, listing Volant itself as `excludedApp`, and both calls with Finder in front
  as `appChanged`. The helper exited after each connection ended, and the clone was deleted.

## Not verified

- The signed installed app's Accessibility attribution and prompt for this feature on the owner's Mac.
- Presses across arbitrary apps, including apps that build menus lazily (items appear only after a
  menu opens), apps with very large menus, and Electron or Catalyst apps.
- Behavior when the launcher is opened from Volant's own menu bar item or while Settings is in front,
  where Volant itself is the frontmost app and no target is captured.
