import AppKit
import CoreAudio

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
if CommandLine.arguments.contains("--audio-check") {
    do {
        let routes = try CoreAudioRouting().routes()
        print("Audio outputs: \(routes.filter { $0.direction == .output }.count); inputs: \(routes.filter { $0.direction == .input }.count)")
        if CommandLine.arguments.contains("--audio-write-check") {
            for route in routes where route.current {
                var address = AudioObjectPropertyAddress(mSelector: route.direction.selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
                var device = route.device
                guard AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &device) == noErr else { throw VolumeFailure(message: "Current route write failed") }
                print("Same-device \(route.direction.rawValue) write passed")
            }
        }
        exit(0)
    } catch { print(error.localizedDescription); exit(1) }
}
if let index = CommandLine.arguments.firstIndex(of: "--connectivity-check"), CommandLine.arguments.indices.contains(index + 1) {
    let source = CommandLine.arguments[index + 1]
    guard ["wifi", "bluetooth"].contains(source) else { exit(2) }
    let service = ConnectivityService()
    var latest: ConnectivitySnapshot?
    service.load(source, refresh: true) { latest = $0 }
    DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
        let count = latest?.items.filter { item in
            switch item { case .wifi, .bluetooth: return true; default: return false }
        }.count ?? 0
        print("Connectivity check: \(source); visible entries: \(count); status: \(latest?.message ?? "ready")")
        exit(0)
    }
    withExtendedLifetime(service) { app.run() }
}
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
