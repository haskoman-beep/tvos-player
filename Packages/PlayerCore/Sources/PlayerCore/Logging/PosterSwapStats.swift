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

    /// How a swap began: the tile kept showing a picture (old one kept or the new one already cached) or it showed
    /// its placeholder.
    public enum Start: Sendable, Equatable { case covered, gap }

    /// A load of `next` starts. A swap only when a picture of another address was shown before (`previous`);
    /// `pictureVisible`: what the view would draw right now has a picture. Nil = no swap.
    public static func start(previous: String?, next: String, pictureVisible: Bool) -> Start? {
        guard let previous, previous != next else { return nil }
        return pictureVisible ? .covered : .gap
    }

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
