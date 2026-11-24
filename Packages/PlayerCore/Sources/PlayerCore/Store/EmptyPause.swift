import Foundation

/// Task 3.7 (A-A-4): pause of the source prefetch after empty searches. One title without sources is normal
/// (unreleased, rare); only consecutive searches of `titles` **different** titles within `window`, each with every
/// asked addon empty or failed, look like a rate limit and pause the prefetch for `defaultPause`. A search with
/// hits ends the streak and the pause. Searches no addon was asked for do not count (the caller skips them).
/// The pause never applies to the search of an open page (detail page, source list, autoplay): the app only
/// consults it for prefetching.
public struct EmptyPause: Sendable, Equatable {
    public static let titles = 3
    public static let window: TimeInterval = 60
    /// Same value as `StreamPrefetcher.allEmptyPause` in the app.
    public static let defaultPause: TimeInterval = 300

    /// Titles of the current streak with the time of their last empty search.
    private var empty: [String: Date] = [:]
    /// Start of the running pause (refreshed by further empty titles while it runs).
    public private(set) var pausedAt: Date?

    public init() {}

    /// An empty search of `id`. Returns true when this search starts a pause (none ran before).
    @discardableResult
    public mutating func recordEmpty(id: String, now: Date) -> Bool {
        empty = empty.filter { abs(now.timeIntervalSince($0.value)) < Self.window }
        empty[id] = now
        guard empty.count >= Self.titles else { return false }
        let starts = !isPaused(now: now)
        pausedAt = now
        return starts
    }

    /// A search with hits. Returns true when it lifts a running pause.
    @discardableResult
    public mutating func recordHit(now: Date = Date()) -> Bool {
        let lifted = isPaused(now: now)
        empty.removeAll()
        pausedAt = nil
        return lifted
    }

    public func isPaused(now: Date, pause: TimeInterval = EmptyPause.defaultPause) -> Bool {
        guard let t = pausedAt else { return false }
        return now.timeIntervalSince(t) < pause
    }
}
