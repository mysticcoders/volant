import AppKit

/// The short sounds that say dictation started or stopped, so it's clear the microphone is live
/// without looking at the screen. They are macOS system sounds, so nothing is bundled; a missing
/// sound plays nothing. Tests replace `play`.
final class DictationSounds {
    enum Cue { case start, stop }

    /// How long the start sound plays, so the volume is lowered only after it.
    static let startDuration: TimeInterval = 0.3

    /// What a dictation phase change does: which sound plays, whether and when the volume is
    /// lowered, and whether it is restored.
    struct Plan: Equatable {
        var sound: Cue?
        var lowerAfter: TimeInterval?
        var restore = false
    }

    /// Entering listening plays the start sound and lowers the volume after it, or at once without
    /// sounds. Leaving listening restores the volume; finishing or cancelling plays the stop sound,
    /// a failure plays nothing. Changes that do not involve listening only restore.
    static func plan(from previous: SpeechDictation.Phase, to phase: SpeechDictation.Phase, sounds: Bool, lowersVolume: Bool) -> Plan {
        if phase == .listening {
            return Plan(sound: sounds ? .start : nil, lowerAfter: lowersVolume ? (sounds ? startDuration : 0) : nil)
        }
        let stops = previous == .listening && sounds && (phase == .finishing || phase == .idle)
        return Plan(sound: stops ? .stop : nil, restore: true)
    }

    var play: (Cue) -> Void = { cue in
        let sound = NSSound(named: cue == .start ? "Tink" : "Pop")
        sound?.volume = 0.6
        sound?.play()
    }
}
