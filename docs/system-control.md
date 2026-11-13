# Audio and connectivity controls

Type `volume` or `vol` to show volume commands and the current default audio output. `volume up` and `volume down` change the level by five percentage points; `volume 40` or `volume 40%` sets an exact level. `mute` and `unmute` are explicit actions. Return applies the selected action and keeps the launcher open for repeated adjustments. Invalid percentages never create an actionable row.

This first system-control feature uses public CoreAudio APIs inside the existing App Sandbox, with no new entitlement, helper, network request, Accessibility grant, or Input Monitoring grant. Queries inspect the output; only activation writes. Volume queries reserve `vol`, `volume`, `mute`, and `unmute` before app aliases/quicklinks, and Raycast import recognizes those reserved names.

The output is resolved again at activation. A device's main scalar is preferred, with a fallback to its preferred stereo channels. Channel changes scale together to preserve balance; if all channels are at zero, raising volume starts them equally. Volume changes retain the existing mute state. Unsupported controls (common on digital outputs) are labelled and produce an explanation. There is no emulated mute that loses the user's prior volume. Failed channel writes attempt to restore completed channels and report if restoration fails.

The displayed level is read back from hardware. It refreshes on a volume query or action, not continuously when another app changes volume. Devices with asynchronous setters may report their preceding value briefly. Multichannel devices without a main scalar or preferred stereo controls are not handled by this first pass.

## Evidence

- `tools/check-volume.sh`: parsing and reserved commands, out-of-range input, bounds, stereo balance, explicit mute behavior, device changes, rollback, and unsupported controls using fictional hardware.
- `tools/check-launcher.sh`: actual native panel Return handling, discovery, exact percentages, mute/unmute, unsupported controls, and missing output in light/dark appearances. Rendered success/error states inspected at the launcher's fixed size. The existing selection-highlight regressions still pass. Visual inspection caught stale row subtitles when capabilities changed; row content now resolves the current value by stable identity from its observed model.
- Signed Release sandbox probe on the owner's current output: read 50%, writable volume and mute; writing the same existing channel levels and mute state passed without changing audio. This establishes sandbox access on that device, not Bluetooth/HDMI/multichannel coverage.
- Both checks run from `Scripts/test.sh`. No new hosted CI runner has been added.

## Next work

1. Hardware coverage for headphones, HDMI, and device switching during an action; property listeners if continuous status is needed.
2. Audio input/output switching, connected Bluetooth inventory, and Wi‑Fi visibility/switching now take priority. Raycast extension compatibility is explicitly deferred by the owner.
3. Optional privileged helper for window controls remains a separate feature; system-wide text expansion stays declined. Clipboard search must remain in memory with encrypted storage.

Sources: Apple's [default output device](https://developer.apple.com/documentation/coreaudio/kaudiohardwarepropertydefaultoutputdevice), [scalar volume](https://developer.apple.com/documentation/coreaudio/kaudiodevicepropertyvolumescalar), and [mute](https://developer.apple.com/documentation/coreaudio/kaudiodevicepropertymute) properties, plus the installed SDK's AudioHardware headers. Research context: [system control and extensions](system-control-and-extensions-research.md).


## Audio devices and connectivity (2026-09-14)

`audio`, `output`, and `input` list eligible audio routes. Filter by name, for example `output airpods` or `audio input mac`. The current input and output are marked independently. Switching resolves the stable device UID again to avoid recycled CoreAudio IDs, then confirms the current route. It does not connect disconnected Bluetooth headphones or change the other audio direction. No microphone recording is performed.

`bluetooth` / `bt` lists connected paired devices reported by IOBluetooth. This is not a complete inventory of every nearby or unpaired BLE peripheral. Refresh explicitly updates the list; selecting a device opens Bluetooth Settings for management. No Bluetooth connection/disconnection operation is implemented.

`wifi` / `wi-fi` scans visible networks and filters by name. The current SSID is marked, duplicate access points with the same SSID/security collapse to the strongest signal, and scans/cache live only in memory (15-second freshness). CoreWLAN scanning and association run on a serial background queue. A selected network is rescanned with the same security category before joining. Open and WPA/WPA2/WPA3 Personal networks are supported; hidden, enterprise, and other security configurations go to System Settings.

Personal networks open a native secure field in the launcher. The Join button and Return share a guarded submit action. Use Saved Password explicitly requests that selected SSID's password from the user Keychain, falling back to the system domain only when not found. Keychain or network association may prompt for authorization. Passwords are not stored in Volant config, history, or logs; manually entered passwords are not explicitly saved to Keychain. Cancelling before submission clears the field. A submitted OS association is not cancellable; duplicate joins are blocked until it returns.

The owner approved first-use permission prompts. Bluetooth uses its sandbox entitlement and system consent. Wi-Fi names require the Location entitlement and authorization; Volant requests authorization but never requests coordinates or starts location updates for Wi-Fi. Separately, list extensions the owner allows (see network-extensions.md) receive one rounded fix per run. No network-client/server, Accessibility, Input Monitoring, or audio-recording entitlement was added. Permission denial produces guidance and a System Settings action.

Validation: native fixtures cover audio listing/direction independence/current markers/disconnected selection, Bluetooth and Wi-Fi lists, secure-field focus/cancellation/Return, duplicate joins, denied states, and stale scans after query changes. Light/dark rendered screens were inspected. A signed sandbox probe enumerated 5 outputs and 4 inputs and wrote the existing current input/output IDs successfully without changing devices. Real Wi-Fi association, saved-password retrieval, and physical AirPods handoff are separate manual checks, not established by fixtures. Permission dialogs and actual Bluetooth/Wi-Fi inventory still require installed first-use verification.

Sources: Apple [CoreWLAN sandbox guidance](https://developer.apple.com/documentation/corewlan), [Wi-Fi association](https://developer.apple.com/documentation/corewlan/cwinterface/associate(to:password:)), [Location gating](https://developer.apple.com/forums/thread/759044), [paired Bluetooth devices](https://developer.apple.com/documentation/iobluetooth/iobluetoothdevice/paireddevices()), and [connection status](https://developer.apple.com/documentation/iobluetooth/iobluetoothdevice/isconnected()).

Next: verify first-use permissions and the owner's actual device/network inventory; then physical handoff and a deliberate Wi-Fi switch. Continuous device/route change listeners and Bluetooth battery information can follow. The Raycast compatibility prototype is deferred, not part of this work.

Delivery: installed at `/Applications/Volant.app`; deep/strict signature validation and executable byte comparison passed. The installed audio inventory check again found 5 outputs and 4 inputs. Bluetooth/Location consent was deliberately left for first use. Wi-Fi scan loading has no actionable rows, so a pending Settings row cannot turn into a network-join action when scan results arrive.


## Installed Wi-Fi discovery repair (2026-09-14)

Symptom: Location was granted, but the installed app initially reported no Wi-Fi interface, then an empty network list. Two separate OS boundaries were involved:

- Sandbox logs showed `mach-lookup com.apple.airportd` denied. The main app now declares only that local Mach-service exception. Sandbox, Location consent, and the absence of network-client/server entitlements remain intact.
- After that fix, airportd still identified the overwritten `/Applications/Volant.app` bundle as `com.mysticcoders.vey`, despite its corrected plist and signing identifier. It stripped SSIDs as unauthorized. Refreshing Launch Services alone did not resolve this. Installing a fresh bundle directory did; the installed diagnostic then returned 10 named networks. No connection was changed.

Prevention: `Scripts/install.sh` stages and verifies a fresh signed bundle, replaces the old bundle with rollback if the destination move fails, and refreshes only Volant's Launch Services registration. It does not reset privacy grants or the global registry. Scans whose results contain no readable names now explain that macOS returned unnamed networks, instead of implying there are no nearby networks.

Evidence: Release build, native launcher regressions in both appearances, strict focused SwiftLint, installer shell syntax, and diff whitespace checks passed. The installed executable matched the Release build and its signature passed deep/strict verification. Installed Bluetooth permission succeeded, with zero connected paired devices; the unsandboxed IOBluetooth check also reported zero (23 paired). This does not establish BLE-only peripheral coverage. Real association, saved-password retrieval, and physical AirPods handoff remain manual checks. Permission prompts remain first-use only.

Next: use the installed `wifi` command to choose a network deliberately when the owner wants to test joining, and verify a connected Bluetooth headset against `bt` plus `output`. Do not perform either connection change automatically.


## Lowering volume while dictating (2026-10-10)

When dictation starts listening, `DictationVolumeDuck` lowers the current default output to 20% of its level, scaling every channel by the same factor so stereo balance is kept. It reuses `AudioHardwareAccess`, the reads and writes behind the `volume` commands; there is no second CoreAudio path. It never raises a level and never writes mute. A muted output, an output without settable software volume (common on HDMI, AirPlay, and other digital routes), a missing output, or one already within two percentage points of silence is skipped without a message. A partial lowering is rolled back; only a rollback that also fails is reported, because then the output may be left quieter.

Listening ends when dictation finishes (restoration happens when the key is released or Return is pressed, before transcription completes), is cancelled, or fails, and on app quit. Each path restores the captured device by ID and UID, so a recycled CoreAudio ID is not mistaken for the original. The prior level is written back only if every channel still reads as the level written or as the hardware's readback after writing, since some devices round scalar volume to their own steps. A different reading means the owner adjusted the volume during dictation, and that level is kept. Muting during dictation leaves the device muted; the prior level is restored underneath it.

While lowered, a CoreAudio listener on the default output device watches for route changes. If sound moves to another output, the original device is restored at once if it is still connected, the new output is never lowered or written, and the listener is removed. If the original disconnected, or a restore write fails, the launcher reports it in the same message area as other volume failures (or, for hotkey dictation, the floating dictation indicator does), appended to the dictation's final message so it is not overwritten by "Copied …".

The behavior is on by default and is controlled by Settings → General → Dictation → Lower volume while dictating (`dictationLowersVolume`). It is per Mac, is not in `SettingsSync.keys`, and is patched narrowly through `Preferences.updateBoolean`.

Evidence: `VolantTests/DictationVolumeTests` uses fictional devices for lowering and exact restore, balance, repeated lowering, hardware rounding, volume changed during dictation, muted and muting-during outputs, unsupported and nearly silent outputs, a missing output, a device switch that restores the original immediately without touching the new output, a disconnected original, a recycled device ID, failed restores, and partial lowering with and without a successful rollback. `tools/check-volume.sh` compiles the duck with `VolumeControl.swift` and checks lowering, restore, device loss, and muted outputs. `PreferencesTests` covers the default and narrow patch.

Not verified: real lowering and restoring on the owner's hardware, Bluetooth or AirPlay outputs with asynchronous setters, route changes delivered by the real CoreAudio listener, and the Settings toggle rendering. A crash or force quit while listening leaves the output lowered, because only a normal quit runs the restore.


## Pick Color, Open Camera, appearance and menu bar (2026-11-06)

**Pick Color** (`color picker`, `pick color`, `eyedropper`): Return hides the launcher and shows macOS's own magnifying loupe (`NSColorSampler`). Clicking a pixel reopens the launcher on the same phrase with a Picked Color section: HEX, RGB, HSL and OKLCH rows with a swatch, HEX selected, then Pick Another Color, which opens the loupe again and stands in for the Pick Color command while a color is shown. Return copies the selected row's text and closes the launcher. Escape in the loupe reopens the launcher without a color and copies nothing. The sampled color is converted to sRGB and formatted by the calculator's `ColorCalculator`, so a picked color reads exactly like a typed one. The last picked color is kept in memory for the session, shown only under the Pick Color phrases, and never saved. `NSColorSampler` needs no permission: macOS draws the loupe and hands back one color, never a screenshot.

**Open Camera** (`camera`, `open camera`, `webcam`): a small floating, resizable window with a mirrored live preview of the built-in camera (or the system default video device). Escape or the close button closes it. The `AVCaptureSession` stops whenever the window closes or is hidden, and there is no output besides the on-screen preview layer: nothing is recorded, saved or sent. The camera permission is requested only the first time Open Camera is chosen, never at launch. No camera, a refusal, a denied grant and a restricted grant (profile or Screen Time) each produce a launcher message; denied and restricted also show an Open Camera Privacy Settings row that opens Privacy & Security › Camera.

**Toggle System Appearance** (`dark mode`, `light mode`, `toggle appearance`) and **Toggle Menu Bar Hiding** (`menu bar`, `hide menu bar`, `show menu bar`) appear in the System section. Each row's description shows the current state, read from the global preferences (`AppleInterfaceStyle`, `_HIHideMenuBar`) without any Apple Event. Return flips the setting through System Events and keeps the launcher open, with the row and footer showing the new state. The toggle reads the System Events property (`dark mode` of `appearance preferences`, `autohide menu bar` of `dock preferences`), writes the opposite and reads it back; a write macOS ignores is reported as not applied rather than shown as done. The events are built directly (`core/getd`, `core/setd` with property specifiers) and sent from a background queue, so the launcher never blocks; System Events is started without activation if it isn't running.

None of these words is reserved in `LauncherRouting`: they are ordinary search results, not routes, so an alias named `camera` still works.

### Entitlements and consent

- `com.apple.security.device.camera`: lets the sandboxed app open a capture session after the owner grants Camera access. It allows nothing until that consent, and Volant uses it only in Open Camera.
- `com.apple.security.temporary-exception.apple-events` now lists `com.apple.systemevents` beside `com.apple.loginwindow`. The existing `com.apple.security.automation.apple-events` entitlement covers sending under the hardened runtime. System Events' scripting dictionary declares no access groups for these properties, so `com.apple.security.scripting-targets` cannot be used; the temporary exception is the narrowest entitlement that works. It names exactly one more app, and Volant sends it only the read and write of these two properties. No other app is automated.
- macOS asks for Automation consent ("Volant wants access to control System Events") the first time either toggle is chosen, using the updated `NSAppleEventsUsageDescription`. A refusal (`errAEEventNotPermitted`, -1743) shows an Open Automation Privacy Settings row for Privacy & Security › Automation; later attempts are refused at once without another prompt until the owner turns it on there. A consent prompt or reply that times out, and a System Events that can't be started, have their own messages.
- No Accessibility, Screen Recording or Input Monitoring is used. `NSCameraUsageDescription` is new; both prompts are translated (beta) in `InfoPlist.xcstrings`.
- `Scripts/release.sh` now also checks that the Apple Events exception names only loginwindow and System Events, alongside its existing sandbox, network and debugger checks.

### Evidence

- macOS 27.0 (26A428) guest, a disposable clone of `volant-render-27`: `tools/spike-system-events.sh` built the shipped `Volant/SystemControl/SystemEvents.swift` into a Developer ID signed, sandboxed probe carrying only the sandbox, Apple Events and Apple Events exception entitlements from `Volant.entitlements`. Launched through Launch Services in the console session, it raised the real Automation prompt with the probe's usage text; after Allow it read both properties, switched Light → Dark → Light and shown → hidden → shown, each confirmed by System Events read-back, by the global preferences read inside the sandbox, and by guest screenshots (widgets turning dark, the menu bar disappearing). After `tccutil reset AppleEvents`, Don't Allow produced `.denied` with no change, and the next run was refused at once without a new prompt. `autohide menu bar` writes `_HIHideMenuBar` as 1 or 0 and leaves `AppleMenuBarVisibleInFullscreen` alone, so it switches between macOS 27's "Always" and "Never" menu bar choices only, not "On Desktop Only" or "In Full Screen Only".
- `DesignToolCommandsTests` (app) and `DesignToolCommandTests` (Core) cover the sampler flow, cancellation, the camera's four authorization states and no camera, the toggles with a fake System Events, read-back, error mapping and the event specifiers, with no real loupe, camera, consent prompt or Apple Event.
- Launcher fixtures in the Tart UI VM drive Pick Color, the color card, Return copying, loupe cancellation, the denied camera and refused Automation states, and the toggle rows with fakes, rendered light and dark.

Not verified: the signed Volant app itself raising the Automation and Camera prompts, a real camera preview and its indicator light turning off, `NSColorSampler` on real displays (including wide-gamut and multi-display setups), and the menu bar toggle while a full-screen app is in front.
