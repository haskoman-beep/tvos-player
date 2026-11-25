import Foundation

/// Device test 1 of Build 4 follow-up 2 (P2): pressing right in a home row, the row's focus state ("a card or a
/// placeholder of this row holds the focus") passed through "nothing focused" for a moment on every step, between
/// the card losing and the next card gaining the focus. The row reported leave + enter each time, so the heading
/// snap scrolled and animated the row again on every step (the heading jittered), and the hero focus, the collapse
/// latch and the top-edge watch saw a leave too.
///
/// This filter sits between the raw focus state and the row's `onFocusInside` report: an enter is reported at once;
/// a leave only when the raw state is still "outside" after `leaveDelayMs`. A gap shorter than that is bridged and
/// counted (longest gap in ms), so the `nav` line on the real leave shows the gaps it absorbed.
public struct RowFocusPresence: Hashable, Sendable {
    /// How long the raw state must stay "outside" before the leave is reported. The gap between two cards lasts a
    /// frame or two; 100 ms is well below a remote's repeat interval (about 180 ms in the device log).
    public static let leaveDelayMs = 100

    /// What the caller does after a raw change.
    public enum Step: Hashable, Sendable {
        /// Nothing to report (already reported, or nothing changed).
        case none
        /// Report "inside" now.
        case enter
        /// Start the leave delay; pass `serial` to `leaveDue(serial:inside:)` when it ran out.
        case scheduleLeave(serial: Int)
        /// The focus came back before the delay ran out: the pending leave is void (cancel its timer).
        case cancelLeave
    }

    /// A reported leave and the gaps bridged during the visit.
    public struct Leave: Hashable, Sendable {
        public var bridged: Int
        public var longestGapMs: Int

        /// `nav` line for the leave: only when gaps were bridged (one line per row visit, else none).
        public func line(title: String) -> String? {
            guard bridged > 0 else { return nil }
            return "Reihe \(title) verlassen · \(bridged) Fokuslücke\(bridged == 1 ? "" : "n") zwischen Karten "
                + "überbrückt (längste \(longestGapMs) ms)"
        }
    }

    /// The state last reported to the page (true between a reported enter and a reported leave).
    public private(set) var reported = false
    /// Time (seconds) the raw state went "outside" while reported inside; nil without a pending leave.
    public private(set) var pendingSince: Double?
    private var serial = 0
    private var bridged = 0
    private var longestGapMs = 0

    public init() {}

    /// The raw focus state changed (`now` in seconds, any monotonic clock).
    public mutating func raw(_ inside: Bool, now: Double) -> Step {
        if inside {
            if let since = pendingSince {
                pendingSince = nil
                bridged += 1
                longestGapMs = max(longestGapMs, Int(((now - since) * 1000).rounded()))
                return .cancelLeave
            }
            guard !reported else { return .none }
            reported = true
            return .enter
        }
        guard reported, pendingSince == nil else { return .none }
        pendingSince = now
        serial += 1
        return .scheduleLeave(serial: serial)
    }

    /// The leave delay of `serial` ran out; `inside` is the raw state now. Returns the leave to report, or nil when
    /// the focus came back meanwhile (or a newer delay runs).
    public mutating func leaveDue(serial s: Int, inside: Bool) -> Leave? {
        guard s == serial, pendingSince != nil else { return nil }
        pendingSince = nil
        guard !inside, reported else { return nil }
        return endVisit()
    }

    /// The row left the screen: no delay, the visit ends now (nil when nothing was reported inside).
    public mutating func disappear() -> Leave? {
        pendingSince = nil
        serial += 1
        guard reported else { return nil }
        return endVisit()
    }

    private mutating func endVisit() -> Leave {
        let leave = Leave(bridged: bridged, longestGapMs: longestGapMs)
        reported = false
        bridged = 0
        longestGapMs = 0
        return leave
    }
}
