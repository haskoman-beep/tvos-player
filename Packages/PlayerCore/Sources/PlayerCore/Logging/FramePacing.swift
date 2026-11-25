import Foundation

/// Build 4 follow-up S1: frame pacing of the home page from display-link timestamps. `HitchDetector` only reports
/// the main thread stopping for 250 ms; the stutter of fast focus moves lies at 30–100 ms and shows here.
/// Rules: focus activity starts a window (`activity`); every frame interval counts, one longer than
/// `missFactor` × the nominal frame is missed. A window closes after `window` seconds with a report; measuring goes on
/// with the next window only when focus moved within the last `keepAlive` seconds of the closing one. An interval over
/// `pauseGap` (background, a long hang the hitch watchdog logs) is not counted and closes the window early at its last
/// counted frame, so the pause never stretches a line (review M1). `stop()` closes a partial window.
/// No allocation per frame (counters only).
public struct FramePacing: Sendable {
    /// One line of the log.
    public struct Report: Sendable, Equatable {
        /// Frame intervals counted in the window.
        public var frames: Int
        /// Intervals longer than `missFactor` × the nominal frame.
        public var missed: Int
        /// Frames dropped in those intervals (review M2): rounded nominal frames per interval minus the one shown,
        /// at least 1 each, so an 80 ms stall at 60 Hz counts 4 and a 26 ms one 1.
        public var dropped: Int
        /// Longest interval in milliseconds.
        public var longestMs: Int
        /// Nominal display rate (last frame of the window).
        public var hz: Int
        /// Window length in tenths of a second.
        public var tenths: Int
        /// Last note set in the window.
        public var note: String?

        public init(frames: Int, missed: Int, dropped: Int, longestMs: Int, hz: Int, tenths: Int, note: String?) {
            self.frames = frames; self.missed = missed; self.dropped = dropped; self.longestMs = longestMs
            self.hz = hz; self.tenths = tenths; self.note = note
        }
    }

    /// Result of one frame: a closed window's report and whether the display link keeps running.
    public struct Tick: Sendable, Equatable {
        public var report: Report?
        public var keepRunning: Bool
    }

    public static let defaultWindow: TimeInterval = 5
    /// Measuring after the last focus move, so posters arriving after the press still count.
    public static let defaultKeepAlive: TimeInterval = 2
    public static let missFactor = 1.5
    public static let pauseGap: TimeInterval = 1
    /// Nominal frame when the display link reports none.
    public static let fallbackFrame: TimeInterval = 1.0 / 60

    public var window: TimeInterval
    public var keepAlive: TimeInterval
    public private(set) var isRunning = false
    private var lastActivity: TimeInterval = 0
    private var lastFrame: TimeInterval?
    private var windowStart: TimeInterval?
    private var lastCounted: TimeInterval = 0
    private var frames = 0
    private var missed = 0
    private var dropped = 0
    private var longest: TimeInterval = 0
    private var nominal: TimeInterval = FramePacing.fallbackFrame
    private var lastNote: String?

    public init(window: TimeInterval = defaultWindow, keepAlive: TimeInterval = defaultKeepAlive) {
        self.window = window; self.keepAlive = keepAlive
    }

    /// Focus moved at `now` (same clock as the frame timestamps). True when the caller must start the display link.
    public mutating func activity(at now: TimeInterval) -> Bool {
        lastActivity = now
        guard !isRunning else { return false }
        isRunning = true
        resetWindow()
        lastFrame = nil
        return true
    }

    /// Short event note for the current window; dropped while not measuring.
    public mutating func note(_ s: String) {
        guard isRunning else { return }
        lastNote = s
    }

    /// A display-link frame at `timestamp` with the nominal frame duration `nominal` (≤ 0: 60 Hz).
    public mutating func frame(at timestamp: TimeInterval, nominal: TimeInterval) -> Tick {
        guard isRunning else { return Tick(report: nil, keepRunning: false) }
        if nominal > 0 { self.nominal = nominal }
        guard let last = lastFrame else {
            lastFrame = timestamp
            if windowStart == nil { windowStart = timestamp; lastCounted = timestamp }
            return Tick(report: nil, keepRunning: true)
        }
        lastFrame = timestamp
        let gap = timestamp - last
        if gap > Self.pauseGap { return closeWindow(at: timestamp) }
        if gap > 0 {
            frames += 1
            lastCounted = timestamp
            if gap > Self.missFactor * self.nominal {
                missed += 1
                dropped += max(1, Int((gap / self.nominal).rounded()) - 1)
            }
            if gap > longest { longest = gap }
        }
        guard let start = windowStart, timestamp - start >= window else { return Tick(report: nil, keepRunning: true) }
        return closeWindow(at: timestamp)
    }

    /// Ends the current window at its last counted frame (no report without frames) and starts the next one at
    /// `timestamp`, or stops when focus did not move within `keepAlive`.
    private mutating func closeWindow(at timestamp: TimeInterval) -> Tick {
        let r = frames > 0 ? windowStart.map { report(end: lastCounted, start: $0) } : nil
        resetWindow()
        windowStart = timestamp
        lastCounted = timestamp
        if timestamp - lastActivity >= keepAlive {
            isRunning = false
            lastFrame = nil
            windowStart = nil
            return Tick(report: r, keepRunning: false)
        }
        return Tick(report: r, keepRunning: true)
    }

    /// Ends measuring (page left, playback): the partial window's report, nil when nothing was counted.
    public mutating func stop() -> Report? {
        defer { isRunning = false; lastFrame = nil; windowStart = nil; resetWindow() }
        guard isRunning, frames > 0, let start = windowStart else { return nil }
        return report(end: lastCounted, start: start)
    }

    private func report(end: TimeInterval, start: TimeInterval) -> Report {
        Report(frames: frames, missed: missed, dropped: dropped, longestMs: Int((longest * 1000).rounded()),
               hz: Int((1 / nominal).rounded()), tenths: max(0, Int(((end - start) * 10).rounded())), note: lastNote)
    }

    private mutating func resetWindow() {
        frames = 0; missed = 0; dropped = 0; longest = 0; lastNote = nil
    }

    /// Log text of a report (category `ruckler`).
    public static func text(_ r: Report) -> String {
        var s = "Startseite \(r.tenths / 10),\(r.tenths % 10) s: \(r.frames) Bilder (\(r.hz) Hz)"
        s += " · \(r.missed) verpasst · ≈\(r.dropped) Bilder fehlen · längstes \(r.longestMs) ms"
        if let n = r.note, !n.isEmpty { s += " · zuletzt: \(n)" }
        return s
    }
}
