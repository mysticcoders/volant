import AppKit

let app = NSApplication.shared
// A count-only installed-artifact check: never prints clipboard contents or key material.
if CommandLine.arguments.contains("--storage-check") {
    let store = ClipboardStore(retention: Preferences.load().clipboardRetention)
    print("Readable clipboard entries: \(store.recent(limit: Int(Int32.max)).count)")
    exit(0)
}
if CommandLine.arguments.contains("--volume-check") {
    do {
        let hardware = CoreAudioHardware()
        let state = try hardware.output()
        print("Volume: \(state.level.map { Int(($0 * 100).rounded()) } ?? -1); writable: \(state.canSetVolume); mute writable: \(state.canSetMute)")
        if CommandLine.arguments.contains("--volume-write-check") {
            // Exercise signed sandbox writes without changing the user's audio level or mute state.
            guard state.canSetVolume else { throw VolumeFailure(message: "No writable software volume on this output.") }
            for volume in state.volumes { try hardware.setVolume(volume.value, channel: volume.channel, device: state.device) }
            if state.canSetMute, let muted = state.muted { try hardware.setMute(muted, device: state.device) }
            print("Same-value volume writes passed")
        }
        exit(0)
    } catch { print("Volume check: " + error.localizedDescription); exit(1) }
}
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
