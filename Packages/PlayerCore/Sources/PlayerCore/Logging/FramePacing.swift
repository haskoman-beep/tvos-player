import Foundation

/// Build 4 follow-up S1: frame pacing of the home page from display-link timestamps. `HitchDetector` only reports
/// the main thread stopping for 250 ms; the stutter of fast focus moves lies at 30–100 ms and shows here.
/// Rules: focus activity starts a window (`activity`); every frame interval counts, one longer than
/// `missFactor` × the nominal frame is missed. A window closes after `window` seconds with a report; measuring goes on
/// with the next window only when focus moved within the last `keepAlive` seconds of the closing one. An interval over
/// `pauseGap` (background, a long hang the hitch watchdog logs) is not counted and closes the window early at its last
/// counted frame, so the pause never stretches a line (review M1). `stop()` closes a partial window.
/// No allocation per frame (counters only).
/// Build 4 follow-up 2 (P3): render-side events (`event`) are counted per window, and every missed frame is checked
/// against the latest event of each kind: within the kind's `span` before the stalled interval it counts as near that
/// kind (one miss can be near several kinds), otherwise as „ohne“. The line then says whether the missed frames
/// coincide with backdrop swaps, poster pictures, badge passes or stored sources.
public struct FramePacing: Sendable {
    /// Build 4 follow-up 2 (P3): render-side events of the home page that may cost a frame.
    public enum Event: Int, Sendable, CaseIterable {
        /// The hero backdrop swaps its picture (start of the 0.6 s crossfade).
        case backdrop
        /// A poster card expands after its focus rest (0.25 s animation, larger picture).
        case expand
        /// A poster tile sets a loaded picture (0.2 s fade-in, first upload of the bitmap).
        case poster
        /// One batched pass of quality badges reached the cards.
        case badges
        /// A source list was stored (cache, badge cache).
        case sources
        /// A source prefetch started (focus rest or visible tiles).
        case prefetch

        /// Fixed name in the log line.
        public var label: String {
            switch self {
            case .backdrop: "Hintergrund"
            case .expand: "Aufklappen"
            case .poster: "Poster"
            case .badges: "Plaketten"
            case .sources: "Quellen"
            case .prefetch: "Vorladen"
            }
        }

        /// Note („zuletzt“) the event leaves in its window.
        public var note: String {
            switch self {
            case .backdrop: "Hintergrund gewechselt"
            case .expand: "Karte aufgeklappt"
            case .poster: "Poster angekommen"
            case .badges: "Plaketten gesetzt"
            case .sources: "Quellen abgelegt"
            case .prefetch: "Vorladen gestartet"
            }
        }

        /// Seconds after the event in which a stalled frame still counts as near it: the event's own animation
        /// (crossfade 0.6 s, expansion 0.25 s, fade 0.2 s) plus about 0.2 s for the commit that starts it.
        public var span: TimeInterval {
            switch self {
            case .backdrop: 0.8
            case .expand: 0.45
            case .poster, .badges, .sources, .prefetch: 0.3
            }
        }

        /// Stored once: `allCases` builds a new array on every call (no allocation per frame).
        static let all: [Event] = Event.allCases
    }

    /// Build 4 follow-up 2 (P3): events of one window and the missed frames near them.
    public struct EventTally: Sendable, Equatable {
        private var counts = [Int](repeating: 0, count: Event.all.count)
        private var nearCounts = [Int](repeating: 0, count: Event.all.count)
        /// Missed frames near no event.
        public private(set) var missedAlone = 0

        public init() {}

        /// Events of `kind` in the window.
        public func count(_ kind: Event) -> Int { counts[kind.rawValue] }
        /// Missed frames near an event of `kind`.
        public func near(_ kind: Event) -> Int { nearCounts[kind.rawValue] }

        public mutating func counted(_ kind: Event) { counts[kind.rawValue] += 1 }

        /// One missed frame near the given kinds (none: „ohne“).
        public mutating func missed(near kinds: [Event]) {
            if kinds.isEmpty { missedAlone += 1 }
            for k in kinds { nearCounts[k.rawValue] += 1 }
        }

        /// Frame path: one missed frame, kind by index (no array built).
        mutating func missedNear(index: Int) { nearCounts[index] += 1 }
        mutating func missedWithoutEvent() { missedAlone += 1 }

        /// „Hintergrund 1, Poster 2“ (kinds with events, fixed order), nil without any.
        var countsText: String? { Self.list(counts, extra: nil) }

        /// „Hintergrund 2, ohne 1“, nil without missed frames.
        var nearText: String? { Self.list(nearCounts, extra: missedAlone) }

        private static func list(_ values: [Int], extra: Int?) -> String? {
            var parts: [String] = []
            for e in Event.all where values[e.rawValue] > 0 { parts.append("\(e.label) \(values[e.rawValue])") }
            if let extra, extra > 0 { parts.append("ohne \(extra)") }
            return parts.isEmpty ? nil : parts.joined(separator: ", ")
        }
    }

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
        /// Build 4 follow-up 2 (P3): events of the window and the missed frames near them.
        public var events: EventTally

        public init(frames: Int, missed: Int, dropped: Int, longestMs: Int, hz: Int, tenths: Int, note: String?,
                    events: EventTally = EventTally()) {
            self.frames = frames; self.missed = missed; self.dropped = dropped; self.longestMs = longestMs
            self.hz = hz; self.tenths = tenths; self.note = note; self.events = events
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
    private var events = EventTally()
    /// Latest time of each event kind (also while not measuring: an event just before the start still counts as near).
    private var lastEventAt = [TimeInterval](repeating: -.infinity, count: Event.all.count)

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

    /// Build 4 follow-up 2 (P3): a render-side event at `now` (same clock as the frame timestamps). Counted and
    /// named as the window's note only while measuring; its time is kept for the nearness of the next missed frames.
    public mutating func event(_ kind: Event, at now: TimeInterval) {
        lastEventAt[kind.rawValue] = now
        guard isRunning else { return }
        events.counted(kind)
        lastNote = kind.note
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
                attributeMiss(stallStart: last)
            }
            if gap > longest { longest = gap }
        }
        guard let start = windowStart, timestamp - start >= window else { return Tick(report: nil, keepRunning: true) }
        return closeWindow(at: timestamp)
    }

    /// A missed frame whose interval began at `stallStart`: near every kind whose latest event lies within its span
    /// before that (or during the stall), else without an event.
    private mutating func attributeMiss(stallStart: TimeInterval) {
        var any = false
        for i in 0..<lastEventAt.count where lastEventAt[i] >= stallStart - Event.all[i].span {
            events.missedNear(index: i)
            any = true
        }
        if !any { events.missedWithoutEvent() }
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
               hz: Int((1 / nominal).rounded()), tenths: max(0, Int(((end - start) * 10).rounded())), note: lastNote,
               events: events)
    }

    private mutating func resetWindow() {
        frames = 0; missed = 0; dropped = 0; longest = 0; lastNote = nil
        events = EventTally()
    }

    /// Log text of a report (category `ruckler`). `place`: where it was measured (home page, or „Spur-Panel“ for the
    /// track panel over the running video).
    public static func text(_ r: Report, place: String = "Startseite") -> String {
        var s = "\(place) \(r.tenths / 10),\(r.tenths % 10) s: \(r.frames) Bilder (\(r.hz) Hz)"
        s += " · \(r.missed) verpasst · ≈\(r.dropped) Bilder fehlen · längstes \(r.longestMs) ms"
        if let e = r.events.countsText { s += " · Ereignisse: \(e)" }
        if r.missed > 0, let m = r.events.nearText { s += " · verpasst bei: \(m)" }
        if let n = r.note, !n.isEmpty { s += " · zuletzt: \(n)" }
        return s
    }
}
