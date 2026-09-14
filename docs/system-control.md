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

The owner approved first-use permission prompts. Bluetooth uses its sandbox entitlement and system consent. Wi-Fi names require the Location entitlement and authorization; Volant requests authorization but never requests coordinates or starts location updates. No network-client/server, Accessibility, Input Monitoring, or audio-recording entitlement was added. Permission denial produces guidance and a System Settings action.

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
