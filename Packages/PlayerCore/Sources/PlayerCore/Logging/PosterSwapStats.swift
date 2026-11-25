import Foundation

/// Build 4 follow-up S2: poster tiles replacing their picture with one from another address (TMDB poster → addon
/// poster), summed up for one log line per `window` with activity. A gap is a swap during which the tile showed its
/// placeholder instead of the old or the new picture (with "keep the previous picture" it should stay 0).
public struct PosterSwapStats: Sendable, Equatable {
    /// Seconds from the first swap of a window until its line is taken.
    public static let window: TimeInterval = 10

    public private(set) var swaps = 0
    public private(set) var gaps = 0
    public private(set) var longestGapMs = 0
    public private(set) var longestWaitMs = 0

    public init() {}

    /// One finished swap. `gapMs`: how long the placeholder showed, nil = no gap at all (0 still counts as a gap);
    /// `waitMs`: time until the new picture was there. Returns true for the first swap of a new window (the caller
    /// then takes the line `window` seconds later).
    @discardableResult
    public mutating func record(gapMs: Int?, waitMs: Int) -> Bool {
        let first = swaps == 0
        swaps += 1
        if let g = gapMs {
            gaps += 1
            longestGapMs = max(longestGapMs, g)
        }
        longestWaitMs = max(longestWaitMs, waitMs)
        return first
    }

    /// The window's log text (nil without swaps); starts a new window.
    public mutating func take() -> String? {
        guard swaps > 0 else { return nil }
        let line = "Kachelwechsel \(swaps) · mit Lücke \(gaps) · längste Lücke \(longestGapMs) ms"
            + " · längstes Warten \(longestWaitMs) ms"
        self = PosterSwapStats()
        return line
    }
}
