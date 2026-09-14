import Foundation
import CoreAudio

enum AudioDirection: String, CaseIterable {
    case output, input
    var title: String { self == .output ? "Audio Output" : "Audio Input" }
    var scope: AudioObjectPropertyScope { self == .output ? kAudioDevicePropertyScopeOutput : kAudioDevicePropertyScopeInput }
    var selector: AudioObjectPropertySelector { self == .output ? kAudioHardwarePropertyDefaultOutputDevice : kAudioHardwarePropertyDefaultInputDevice }
}
struct AudioRoute: Hashable {
    let uid: String
    let device: AudioDeviceID
    let name: String
    let direction: AudioDirection
    let current: Bool
    var id: String { direction.rawValue + ":" + uid }
}
struct AudioRouteQuery {
    let directions: [AudioDirection]
    let term: String
    init?(_ query: String) {
        var words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard let head = words.first, ["audio", "input", "output"].contains(head) else { return nil }
        words.removeFirst()
        if let direction = AudioDirection(rawValue: head) { directions = [direction] }
        else if let first = words.first, let direction = AudioDirection(rawValue: first) { directions = [direction]; words.removeFirst() }
        else { directions = AudioDirection.allCases }
        term = words.joined(separator: " ")
    }
}
protocol AudioRouting {
    func routes() throws -> [AudioRoute]
    func select(_ route: AudioRoute) throws
}
struct CoreAudioRouting: AudioRouting {
    private func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
    private func read<T>(_ object: AudioObjectID, _ property: AudioObjectPropertyAddress, into value: inout T) -> Bool {
        var property = property
        var size = UInt32(MemoryLayout<T>.size)
        return withUnsafeMutablePointer(to: &value) { AudioObjectGetPropertyData(object, &property, 0, nil, &size, $0) == noErr && size == MemoryLayout<T>.size }
    }
    func routes() throws -> [AudioRoute] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var property = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &property, 0, nil, &size) == noErr, size <= 65536, size % 4 == 0 else {
            throw VolumeFailure(message: "Couldn’t list audio devices. Try again.")
        }
        if size == 0 { return [] }
        var devices = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        let status = devices.withUnsafeMutableBytes { AudioObjectGetPropertyData(system, &property, 0, nil, &size, $0.baseAddress!) }
        guard status == noErr else { throw VolumeFailure(message: "The audio device list changed. Try again.") }
        var routes: [AudioRoute] = []
        for direction in AudioDirection.allCases {
            var current = AudioDeviceID(kAudioObjectUnknown)
            _ = read(system, address(direction.selector), into: &current)
            for device in devices {
                var alive: UInt32 = 0
                var eligible: UInt32 = 0
                guard read(device, address(kAudioDevicePropertyDeviceIsAlive), into: &alive), alive != 0,
                      read(device, address(kAudioDevicePropertyDeviceCanBeDefaultDevice, scope: direction.scope), into: &eligible), eligible != 0 else { continue }
                var streams = address(kAudioDevicePropertyStreams, scope: direction.scope)
                var streamSize: UInt32 = 0
                guard AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &streamSize) == noErr, streamSize > 0 else { continue }
                var uid: CFString = "" as CFString
                var name: CFString = "Audio Device" as CFString
                guard read(device, address(kAudioDevicePropertyDeviceUID), into: &uid), !(uid as String).isEmpty else { continue }
                _ = read(device, address(kAudioObjectPropertyName), into: &name)
                routes.append(AudioRoute(uid: uid as String, device: device, name: name as String, direction: direction, current: device == current))
            }
        }
        return routes.sorted { lhs, rhs in
            if lhs.current != rhs.current { return lhs.current }
            if lhs.name != rhs.name { return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending }
            return lhs.id < rhs.id
        }
    }
    func select(_ route: AudioRoute) throws {
        // Resolve stable UID again: CoreAudio numeric device IDs can be recycled after disconnects.
        guard let fresh = try routes().first(where: { $0.id == route.id }) else {
            throw VolumeFailure(message: "This audio device disconnected. Refresh the list and try again.")
        }
        if fresh.current { return }
        var property = address(fresh.direction.selector)
        var writable = DarwinBoolean(false)
        let system = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectIsPropertySettable(system, &property, &writable) == noErr, writable.boolValue else {
            throw VolumeFailure(message: "macOS isn’t allowing this audio route to change.")
        }
        var device = fresh.device
        guard AudioObjectSetPropertyData(system, &property, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &device) == noErr else {
            throw VolumeFailure(message: "Couldn’t switch audio devices. The device may have disconnected.")
        }
        guard try routes().contains(where: { $0.id == fresh.id && $0.current }) else {
            throw VolumeFailure(message: "macOS hasn’t confirmed the switch yet. Refresh the list to check the current device.")
        }
    }
}
