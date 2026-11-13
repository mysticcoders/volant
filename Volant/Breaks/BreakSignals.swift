import CoreAudio
import CoreGraphics
import CoreMediaIO
import Foundation

/// Reads the system state Breaks need, without permission prompts: how long since the last
/// keyboard or pointer event, and whether any app has a camera or microphone running. Nothing read
/// here names an app, a window or what the owner typed, and nothing is logged or stored.
enum BreakSignals {
    /// Seconds since the last input event of any kind in this login session. It reads the event
    /// source's idle counter, not events themselves, so it needs no Input Monitoring or
    /// Accessibility grant inside the sandbox.
    static func idleSeconds() -> TimeInterval {
        guard let anyEvent = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyEvent)
    }

    /// Whether a camera or microphone is running in any process, as during a call or a recording.
    static func cameraOrMicrophoneInUse() -> Bool {
        microphoneInUse() || cameraInUse()
    }

    /// Whether any audio input device is running somewhere. Reads device properties only; no
    /// audio is opened, so it needs no microphone grant.
    static func microphoneInUse() -> Bool {
        audioDevices().contains { device in
            hasInputStreams(device) && audioRunningSomewhere(device)
        }
    }

    /// Whether any camera is running somewhere. Reads device properties only; no stream is
    /// opened, so it needs no camera grant.
    static func cameraInUse() -> Bool {
        cameraDevices().contains(where: cameraRunningSomewhere)
    }

    /// The system's audio device identifiers, or none when they can't be read.
    static func audioDevices() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var devices = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices) == noErr else { return [] }
        return devices
    }

    /// Whether an audio device has input streams, so it is a microphone rather than a speaker.
    static func hasInputStreams(_ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioObjectPropertyScopeInput,
                                                 mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
    }

    /// Whether any process is running the audio device.
    private static func audioRunningSomewhere(_ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere, mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr && running != 0
    }

    /// The system's camera identifiers, or none when they can't be read.
    static func cameraDevices() -> [CMIOObjectID] {
        var address = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
                                                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                                                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &size) == 0, size > 0 else { return [] }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, size, &used, &devices) == 0 else { return [] }
        return Array(devices.prefix(Int(used) / MemoryLayout<CMIOObjectID>.size))
    }

    /// Whether any process is running the camera.
    private static func cameraRunningSomewhere(_ device: CMIOObjectID) -> Bool {
        var address = CMIOObjectPropertyAddress(mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                                                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
                                                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard))
        var running: UInt32 = 0
        var used: UInt32 = 0
        return CMIOObjectGetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &running) == 0 && running != 0
    }
}
