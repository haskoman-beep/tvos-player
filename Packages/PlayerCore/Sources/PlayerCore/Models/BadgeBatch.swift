import Foundation

/// Build 4 follow-up 2 (P3): source results (cache IDs whose badge values changed) collected for one pass to the
/// cards instead of one pass per result. The values themselves are stored at once; only the notification waits.
/// - `coalesce` (0.5 s) after the first waiting result: searches started together (up to 6 at once) end spread over
///   0.5–2 s; one pass per half second instead of one per title.
/// - Not before the focus has been quiet for `focusQuiet` (1 s, `FocusRest.prefetchQuiet`): the card lift, the
///   expansion after 350 ms and the 0.6 s backdrop crossfade are over by then.
/// - At the latest `maxHold` (3 s) after the first waiting result, so a long browse does not hold badges back for good
///   (at most one pass per 3 s while the focus keeps moving).
public struct BadgeBatch: Sendable {
    public struct Limits: Sendable, Equatable {
        public var coalesce: TimeInterval
        public var focusQuiet: TimeInterval
        public var maxHold: TimeInterval

        public init(coalesce: TimeInterval = 0.5, focusQuiet: TimeInterval = FocusRest.prefetchQuiet,
                    maxHold: TimeInterval = 3) {
            self.coalesce = coalesce
            self.focusQuiet = focusQuiet
            self.maxHold = maxHold
        }
    }

    /// One pass: the IDs and how long the oldest of them waited.
    public struct Flush: Sendable, Equatable {
        public let ids: Set<String>
        public let waited: TimeInterval

        public init(ids: Set<String>, waited: TimeInterval) {
            self.ids = ids; self.waited = waited
        }
    }

    public let limits: Limits
    private var pending: Set<String> = []
    private var firstAt: Date?
    private var focusAt: Date?

    public init(limits: Limits = Limits()) { self.limits = limits }

    /// A result for `id` arrived.
    public mutating func add(_ id: String, now: Date) {
        pending.insert(id)
        if firstAt == nil { firstAt = now }
    }

    /// The focus moved to another tile.
    public mutating func focusMoved(now: Date) { focusAt = now }

    /// When the waiting IDs are due; nil when nothing waits.
    public var flushAt: Date? {
        guard let first = firstAt, !pending.isEmpty else { return nil }
        var due = first.addingTimeInterval(limits.coalesce)
        if let f = focusAt { due = max(due, f.addingTimeInterval(limits.focusQuiet)) }
        return min(due, first.addingTimeInterval(limits.maxHold))
    }

    /// The waiting IDs once due (and empties the batch), else nil.
    public mutating func take(now: Date) -> Flush? {
        guard let due = flushAt, let first = firstAt, now >= due else { return nil }
        let flush = Flush(ids: pending, waited: now.timeIntervalSince(first))
        clear()
        return flush
    }

    /// Drops the waiting IDs (profile switch).
    public mutating func clear() {
        pending = []
        firstAt = nil
    }
}

/// P3: badge passes summed up for one `ruckler` line per `window` with passes.
public struct BadgePassStats: Sendable, Equatable {
    /// Seconds from the first pass of a window until its line is taken.
    public static let window: TimeInterval = 10

    public private(set) var passes = 0
    public private(set) var titles = 0
    public private(set) var longestWaitMs = 0

    public init() {}

    /// One pass. True for the first pass of a new window (the caller takes the line `window` seconds later).
    @discardableResult
    public mutating func record(_ flush: BadgeBatch.Flush) -> Bool {
        let first = passes == 0
        passes += 1
        titles += flush.ids.count
        longestWaitMs = max(longestWaitMs, Int((flush.waited * 1000).rounded()))
        return first
    }

    /// The window's log text (nil without passes); starts a new window.
    public mutating func take() -> String? {
        guard passes > 0 else { return nil }
        let line = "Plaketten gebündelt: \(passes) \(passes == 1 ? "Durchgang" : "Durchgänge") · \(titles) Titel"
            + " · längstes Warten \(longestWaitMs) ms"
        self = BadgePassStats()
        return line
    }
}
