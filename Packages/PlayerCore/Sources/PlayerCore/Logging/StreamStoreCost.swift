import Foundation

/// Build 4 follow-up S3: main-thread time of storing a finished source search (merge into the cache, badge values,
/// notifying the tiles). From `threshold` on one line for the category „ruckler“, at most one per `minInterval`;
/// slow stores in between are counted and named in the next line (same pattern as `HitchDetector`). Fast stores
/// neither log nor count; S3 review (Minor 2): the first store after the interval, fast or slow, brings counted slow
/// stores out („Nachtrag“), so a burst followed only by fast stores is not lost.
public struct StreamStoreCost: Sendable {
    public static let threshold: TimeInterval = 0.008

    public var minInterval: TimeInterval
    private var lastReport: TimeInterval?
    private var suppressed = 0
    private var suppressedMax = 0

    public init(minInterval: TimeInterval = 10) { self.minInterval = minInterval }

    /// One store of `entries` entries that took `seconds` on the main thread, at `now` (monotone seconds).
    /// Returns the log text when one is due.
    public mutating func note(entries: Int, seconds: TimeInterval, at now: TimeInterval) -> String? {
        guard seconds >= Self.threshold else { return flushCounted(at: now) }
        let ms = Int((seconds * 1000).rounded())
        if let r = lastReport, now - r < minInterval {
            suppressed += 1
            suppressedMax = max(suppressedMax, ms)
            return nil
        }
        lastReport = now
        var s = "Quellen abgelegt: \(entries) Einträge, Hauptthread \(ms) ms"
        if suppressed > 0 { s += " · dazu \(suppressed) weitere (bis \(suppressedMax) ms)" }
        suppressed = 0
        suppressedMax = 0
        return s
    }

    /// A fast store after the interval: the counted slow stores as their own line, which counts as the last line.
    private mutating func flushCounted(at now: TimeInterval) -> String? {
        guard suppressed > 0, let r = lastReport, now - r >= minInterval else { return nil }
        lastReport = now
        let s = "Quellen abgelegt: Nachtrag · dazu \(suppressed) weitere (bis \(suppressedMax) ms)"
        suppressed = 0
        suppressedMax = 0
        return s
    }
}
