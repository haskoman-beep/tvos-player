import Foundation

/// Build 5 (b5r): how long the home backdrop waits after a focus move before it follows the card. Device test 2
/// (build b4-nacharbeit-2): with the 350 ms rest the backdrop swapped every 1–1.5 s while the user kept pressing right
/// (each swap a 0.6 s full-screen crossfade plus a hero info reload); the missed frames sat mostly at "Hintergrund".
/// Now the rest is at least `baseMilliseconds`, and while the user presses in a rhythm (moves less than
/// `burstGapMilliseconds` apart) it is longer than the longest of the last `historyCount` gaps, so no swap lands
/// between two presses. Capped at `maxMilliseconds`. Pure value, the caller passes a monotonic clock in seconds.
public struct BackdropRest: Sendable, Equatable {
    public static let baseMilliseconds = 800
    public static let maxMilliseconds = 1500
    /// Moves further apart than this are no burst: the user looked at the card.
    public static let burstGapMilliseconds = 1500
    /// The rest is this much longer than the burst's longest recent gap.
    public static let marginMilliseconds = 300
    public static let historyCount = 3

    private var lastMove: TimeInterval?
    private var gaps: [Int] = []
    private var movesSinceSwap = 0

    public init() {}

    /// The focus moved at `now`; returns the rest in ms before the backdrop may follow this card.
    public mutating func moved(at now: TimeInterval) -> Int {
        defer { lastMove = now }
        movesSinceSwap += 1
        guard let last = lastMove else { gaps = []; return Self.baseMilliseconds }
        let gap = Int(((now - last) * 1000).rounded())
        guard gap >= 0, gap <= Self.burstGapMilliseconds else { gaps = []; return Self.baseMilliseconds }
        gaps.append(gap)
        if gaps.count > Self.historyCount { gaps.removeFirst(gaps.count - Self.historyCount) }
        let longest = gaps.max() ?? 0
        return min(Self.maxMilliseconds, max(Self.baseMilliseconds, longest + Self.marginMilliseconds))
    }

    /// The moves before this one were part of a burst.
    public var inBurst: Bool { !gaps.isEmpty }

    /// The backdrop followed the latest card: how many earlier moves since the last swap got none (log line).
    public mutating func swapped() -> Int {
        defer { movesSinceSwap = 0 }
        return max(0, movesSinceSwap - 1)
    }

    /// The focus left the rows: the next move starts fresh.
    public mutating func reset() {
        lastMove = nil
        gaps = []
    }
}

extension FocusRest {
    /// Build 5 (b5r): a home focus stop with the backdrop rest of `BackdropRest`. The source prefetch keeps its
    /// 1 s rest in all, but never starts before the crossfade (`fadeMilliseconds`) after the swap is over (with the
    /// 800 ms rest it starts 1.4 s after the stop). Shown already: no swap, the prefetch after its full rest.
    public static func stop(alreadyShown: Bool, backdropRest: Int, fadeMilliseconds: Int) -> Stop {
        guard !alreadyShown else { return Stop(backdropWait: nil, prefetchWait: prefetchMilliseconds) }
        let rest = max(0, backdropRest)
        return Stop(backdropWait: rest, prefetchWait: max(prefetchMilliseconds - rest, max(0, fadeMilliseconds)))
    }
}
