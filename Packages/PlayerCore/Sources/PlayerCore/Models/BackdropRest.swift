import Foundation

/// Build 5 (b5r): how long the home backdrop waits after a focus move before it follows the card. Device test 2
/// (build b4-nacharbeit-2): with the 350 ms rest the backdrop swapped every 1–1.5 s while the user kept pressing right
/// (each swap a 0.6 s full-screen crossfade plus a hero info reload); the missed frames sat mostly at "Hintergrund".
/// Now the rest is at least `baseMilliseconds`, and while the user presses in a rhythm (moves less than
/// `burstGapMilliseconds` apart) it is longer than the longest of the last `historyCount` gaps, so no swap lands
/// between two presses. Capped at `maxMilliseconds` (a 1.6–2.0 s rhythm swaps once at 1.5 s). Pure value, the caller
/// passes a monotonic clock in seconds.
public struct BackdropRest: Sendable, Equatable {
    public static let baseMilliseconds = 800
    public static let maxMilliseconds = 1500
    /// Moves further apart than this are no burst: the user looked at the card. b5r review M2: 2 s, device test 2
    /// had 6 of 22 swap gaps at 1.56–1.82 s, which a 1.5 s limit still counted as single stops.
    public static let burstGapMilliseconds = 2000
    /// The rest is this much longer than the burst's longest recent gap.
    public static let marginMilliseconds = 300
    public static let historyCount = 3
    /// The backdrop crossfade (`HeroMetrics.backdropFade`, today's 0.6 s).
    public static let fadeMilliseconds = 600
    /// b5r review M1: how long the home focus must be quiet before the badge pass (`BadgeBatch`) and the visible-tile
    /// prefetch (`VisiblePrefetchPlan`) may run: the longest rest plus the crossfade (2.1 s), so neither lands in a
    /// backdrop swap. Replaces P3's 1 s (350 ms rest + 0.6 s fade) on the home page.
    public static let homeFocusQuiet: TimeInterval = Double(maxMilliseconds + fadeMilliseconds) / 1000

    private var lastMove: TimeInterval?
    private var gaps: [Int] = []
    private var movesSinceSwap = 0

    public init() {}

    /// The focus moved at `now`; returns the rest in ms before the backdrop may follow this card. `wantsSwap` false
    /// (card shown already, backdrop follow off): the move still shapes the rhythm, but is not counted as skipped.
    public mutating func moved(at now: TimeInterval, wantsSwap: Bool = true) -> Int {
        defer { lastMove = now }
        if wantsSwap { movesSinceSwap += 1 }
        guard let last = lastMove else { gaps = []; return Self.baseMilliseconds }
        let gap = Int(((now - last) * 1000).rounded())
        guard gap >= 0, gap <= Self.burstGapMilliseconds else { gaps = []; return Self.baseMilliseconds }
        gaps.append(gap)
        if gaps.count > Self.historyCount { gaps.removeFirst(gaps.count - Self.historyCount) }
        let longest = gaps.max() ?? 0
        return min(Self.maxMilliseconds, max(Self.baseMilliseconds, longest + Self.marginMilliseconds))
    }

    /// The backdrop followed the latest card: how many earlier moves since the last swap got none (log line).
    public mutating func swapped() -> Int {
        defer { movesSinceSwap = 0 }
        return max(0, movesSinceSwap - 1)
    }

    /// The focus left the rows: the next move starts fresh.
    public mutating func reset() {
        lastMove = nil
        gaps = []
        movesSinceSwap = 0
    }
}

extension FocusRest {
    /// Build 5 (b5r): a home focus stop with the backdrop rest of `BackdropRest`. The source prefetch keeps its
    /// 1 s rest in all, but never starts before the crossfade (`fadeMilliseconds`) after the swap is over (with the
    /// 800 ms rest it starts 1.4 s after the stop). Shown already: no swap, the prefetch after its full rest.
    /// (Replaces the 350 ms `stop(alreadyShown:)` of P3.)
    public static func stop(alreadyShown: Bool, backdropRest: Int,
                            fadeMilliseconds: Int = BackdropRest.fadeMilliseconds) -> Stop {
        guard !alreadyShown else { return Stop(backdropWait: nil, prefetchWait: prefetchMilliseconds) }
        let rest = max(0, backdropRest)
        return Stop(backdropWait: rest, prefetchWait: max(prefetchMilliseconds - rest, max(0, fadeMilliseconds)))
    }
}
