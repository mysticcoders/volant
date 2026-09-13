import Foundation

/// Pure scoring for learned ranking. A use adds 1 to a score that decays with a seven-day half-life,
/// so something picked daily outranks something picked fifty times last year.
enum Frecency {
    static let halfLife: TimeInterval = 7 * 24 * 3600

    static func decayed(score: Double, last: Date, now: Date = Date()) -> Double {
        let age = max(0, now.timeIntervalSince(last))
        return score * pow(2, -age / halfLife)
    }

    /// Score after one more use at `now`, given the stored score and its timestamp.
    static func bumped(score: Double, last: Date, now: Date = Date()) -> Double {
        decayed(score: score, last: last, now: now) + 1
    }
}
