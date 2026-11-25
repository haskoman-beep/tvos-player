import Foundation

/// Build 4 follow-up S4: counts view body passes and focus moves for `metric: home.rowBody`. The first event opens a
/// window; the caller closes it `window` seconds later and logs the result. A window without a focus move gives no
/// line (body passes alone, e.g. a progress save during playback, are not what the metric is about).
public struct BodyPassCounter: Sendable {
    /// Seconds per window.
    public static let window: TimeInterval = 5

    private var passes = 0
    private var focusMoves = 0
    private var open = false

    public init() {}

    /// One body pass. True when it opened a window (the caller schedules `close()` after `window`).
    public mutating func pass() -> Bool {
        passes += 1
        return opened()
    }

    /// Focus moved onto a tile. True when it opened a window.
    public mutating func focusMoved() -> Bool {
        focusMoves += 1
        return opened()
    }

    /// Ends the window: its counts, or nil without a focus move. The next event opens a new window.
    public mutating func close() -> (passes: Int, focusMoves: Int)? {
        defer { passes = 0; focusMoves = 0; open = false }
        guard open, focusMoves > 0 else { return nil }
        return (passes, focusMoves)
    }

    private mutating func opened() -> Bool {
        guard !open else { return false }
        open = true
        return true
    }
}
