import Foundation

/// How loud a dictation was, so one that stayed near silence (an accidental tap of the key, or the
/// room's hum) is discarded instead of transcribed. The level is the root mean square of each audio
/// buffer, in decibels relative to full scale; the dictation keeps its loudest buffer.
public enum DictationLevel {
    /// The loudest buffer must reach this level for a dictation to be transcribed. Quiet speech at
    /// arm's length from a laptop microphone measures around -35 to -25 dBFS; a quiet room, below -55.
    public static let silenceThreshold: Float = -50
    /// What an empty or all-zero buffer measures.
    public static let floor: Float = -160

    /// The RMS level of `samples` in dBFS, or `floor` for none. Allocation-free, for the realtime
    /// audio thread.
    public static func decibels(_ samples: UnsafeBufferPointer<Float>) -> Float {
        guard !samples.isEmpty else { return floor }
        var sum: Float = 0
        for sample in samples { sum += sample * sample }
        let rms = (sum / Float(samples.count)).squareRoot()
        return rms > 0 ? max(floor, 20 * log10(rms)) : floor
    }

    /// Whether a dictation whose loudest buffer measured `loudest` dBFS was silence.
    public static func isSilent(loudest: Float) -> Bool { loudest < silenceThreshold }
}
