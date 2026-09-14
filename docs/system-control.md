# Volume controls

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
2. A bounded Raycast-compatible UI-only extension prototype with enforced capabilities, following the saved research. No promise of catalog compatibility yet.
3. Optional privileged helper for window controls remains a separate feature; system-wide text expansion stays declined. Clipboard search must remain in memory with encrypted storage.

Sources: Apple's [default output device](https://developer.apple.com/documentation/coreaudio/kaudiohardwarepropertydefaultoutputdevice), [scalar volume](https://developer.apple.com/documentation/coreaudio/kaudiodevicepropertyvolumescalar), and [mute](https://developer.apple.com/documentation/coreaudio/kaudiodevicepropertymute) properties, plus the installed SDK's AudioHardware headers. Research context: [system control and extensions](system-control-and-extensions-research.md).
