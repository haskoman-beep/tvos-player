import Foundation

/// Topmost focusable element of the home page (wave F-j). Up from here must always reach the tab bar.
public enum HomeTopEdge: String, CaseIterable, Hashable, Sendable {
    /// Play/Details row of the hero.
    case heroButtons
    /// First row (home page without hero).
    case firstRow
    /// "Add rows" button of the empty home page.
    case addRowsButton
    /// "Rows & collections" button when no row is shown below a missing hero.
    case managerButton

    /// Which element sits on top for the given home page layout.
    /// - `hasHero`: the hero layout is shown (button row above the rows).
    /// - `rowCount`: rows shown below the hero (or all rows without hero).
    /// - `layoutEmpty`: the profile has no rows at all (empty home page with "add rows").
    public static func topmost(hasHero: Bool, rowCount: Int, layoutEmpty: Bool) -> HomeTopEdge {
        if hasHero { return .heroButtons }
        if rowCount > 0 { return .firstRow }
        return layoutEmpty ? .addRowsButton : .managerButton
    }

    /// Name for the log (German like all log lines).
    public var logName: String {
        switch self {
        case .heroButtons: "Knopfzeile"
        case .firstRow: "erste Reihe"
        case .addRowsButton: "Reihen hinzufügen"
        case .managerButton: "Reihen & Collections"
        }
    }
}

/// Which home page parts hold focus; `atTop` says whether that is the topmost element.
public struct HomeTopFocus: Hashable, Sendable {
    public enum Part: Hashable, Sendable { case heroButtons, firstRow, actionButton }

    public var edge: HomeTopEdge
    public private(set) var focused: Set<Part> = []

    public init(edge: HomeTopEdge) { self.edge = edge }

    public mutating func set(_ part: Part, _ isFocused: Bool) {
        if isFocused { focused.insert(part) } else { focused.remove(part) }
    }

    /// The part that stands for the current top edge.
    public static func part(for edge: HomeTopEdge) -> Part {
        switch edge {
        case .heroButtons: .heroButtons
        case .firstRow: .firstRow
        case .addRowsButton, .managerButton: .actionButton
        }
    }

    public var atTop: Bool { focused.contains(Self.part(for: edge)) }
}

/// Remembers when focus left the top edge. The focus notifications can arrive after SwiftUI already moved its
/// focus state, so "was at the top" stays true for a short grace period.
public struct TopEdgeTracker: Hashable, Sendable {
    public static let grace: Double = 0.3
    public private(set) var atTop = false
    public private(set) var leftAt: Double?

    public init() {}

    /// Returns true when the state changed.
    @discardableResult
    public mutating func set(_ top: Bool, now: Double) -> Bool {
        guard top != atTop else { return false }
        atTop = top
        leftAt = top ? nil : now
        return true
    }

    public func wasAtTop(now: Double) -> Bool {
        if atTop { return true }
        guard let leftAt else { return false }
        return now - leftAt <= Self.grace
    }
}

/// Rules that keep the top tab bar reachable from the home page (wave F-j).
public enum HomeTopRules {
    /// Scroll offsets up to this count as "at the very top" (points).
    public static let topTolerance: Double = 0.5
    /// Offsets up to this still count as the top position of the page: the focus scroll to the topmost element
    /// leaves the content padding (24 pt with the hero, 40 pt without) plus the focus margin (points).
    public static let restOffset: Double = 60
    /// Time after reaching the top edge before the offset is checked and logged (focus scroll has settled).
    public static let settleMilliseconds = 400

    public enum BarRequest: Hashable, Sendable { case automatic, visible }

    /// Top navigation only: the tab bar is requested explicitly, so a bar that stayed hidden comes back, while
    /// - the top edge holds focus (`atTop`),
    /// - the focus is in the tab bar itself (`inBar`): the request must not drop the moment the move up lands there,
    /// - or the page sits at its top position (`offset` up to `restOffset`); moving up into the bar does not scroll,
    ///   so this holds the request even when the bar is not recognised as such.
    /// Scrolled down with the focus in the content (and always with the sidebar) the system decides.
    public static func barRequest(atTop: Bool, inBar: Bool, offset: Double, navigation: NavigationStyle) -> BarRequest {
        guard navigation == .top else { return .automatic }
        return atTop || inBar || offset <= restOffset ? .visible : .automatic
    }

    /// Top navigation only: the top edge holds focus and the page is not exactly at the top. A residual offset up to
    /// `restOffset` is left alone while the tab bar is on screen, so the page does not shift on its own; beyond that,
    /// or with the bar off screen, the page snaps to the very top.
    public static func shouldScrollToTop(atTop: Bool, offset: Double, barOnScreen: Bool,
                                         navigation: NavigationStyle) -> Bool {
        guard atTop, navigation == .top, offset > topTolerance else { return false }
        return !barOnScreen || offset > restOffset
    }
}

/// Wave F-m: the top tab bar can stay stuck where an earlier page left it. Device log build 198: the player cover
/// was still being dismissed when the source list scrolled to the played row (row 11, about 2300 pt down; the scroll
/// ran about 90 ms before the player's `onDisappear`). The bar followed that list off the screen (y −2250…−2182) and
/// after Menu back (home page, or detail page and grid in the Library tab) it stayed there: offsets 429 → 207 → 7 →
/// 2 pt never moved it, so neither the SwiftUI request nor the focus engine could reach it ("kein Ziel"). The source
/// list now waits for the end of the dismissal; a guard for all tabs repairs the binding in UIKit, one step at a time.
public enum TabBarRepair: Int, Hashable, Sendable, CaseIterable {
    /// Make the visible page's main scroll view the content scroll view (top edge) of its view controller again.
    case rebind = 1
    /// Hide and show the bar through the tab bar controller. Runs while scrolled down too (review F-m I1): a bar
    /// shown over the rows for a moment is better than a dead end, the next scroll hides it again.
    case reshow = 2

    /// Wait after a step before the bar is read again (layout and the start of the bar animation).
    public static let checkMilliseconds = 350
    /// Wait after a pop (transition finished) before the first check.
    public static let popMilliseconds = 600
    /// Wait after the player cover was dismissed: the source list moves focus to the played row first (about 400 ms).
    public static let playerClosedMilliseconds = 900

    /// Next step after `done` (nil = none yet); each step runs once per visit of a page.
    public static func next(after done: TabBarRepair?) -> TabBarRepair? {
        switch done {
        case nil: .rebind
        case .rebind: .reshow
        case .reshow: nil
        }
    }

    public var logName: String {
        switch self {
        case .rebind: "an die Seite gebunden"
        case .reshow: "über den Controller neu eingeblendet"
        }
    }

    /// What started the check.
    public enum Trigger: Hashable, Sendable {
        case popped, playerClosed, arrivedAtTop, upFailed

        /// A new page (or the page after the player) starts a new visit: the steps may run again.
        public var startsVisit: Bool { self == .popped || self == .playerClosed }

        /// Delay before the first check.
        public var delayMilliseconds: Int {
            switch self {
            case .popped: TabBarRepair.popMilliseconds
            case .playerClosed: TabBarRepair.playerClosedMilliseconds
            case .arrivedAtTop, .upFailed: 0
            }
        }

        public var logName: String {
            switch self {
            case .popped: "nach dem Zurückgehen"
            case .playerClosed: "nach dem Player"
            case .arrivedAtTop: "am oberen Rand"
            case .upFailed: "nach gescheitertem Hoch"
            }
        }
    }
}

extension HomeTopRules {
    /// Top of the bar in window coordinates while it is shown (device logs: y 46…114).
    public static let barRestTop: Double = 46
    /// A bar further up than the page offset can explain by more than this is stuck (points).
    public static let strandTolerance: Double = 200

    /// Top navigation only: the bar is stuck off screen above. It moves at most as far as the page (one to one), so
    /// a bar further up than `barRestTop − offset − strandTolerance` follows something else (build 198: −2250 at
    /// offsets 2 and 207). A bar that tvOS slid away by a short scroll stays within that, also at the top position
    /// (review F-m M4). A bar hidden on purpose (`isHidden`, controller) is left alone.
    public static func barStranded(_ bar: TabBarState, offset: Double, navigation: NavigationStyle) -> Bool {
        guard navigation == .top, bar.found, !bar.hidden, !bar.controllerHidden, bar.maxY <= 1 else { return false }
        return bar.minY < barRestTop - max(0, offset) - strandTolerance
    }
}

/// Snapshot of the system tab bar, read from UIKit in the app (for the log).
public struct TabBarState: Hashable, Sendable {
    public var found: Bool
    /// `UITabBar.isHidden`.
    public var hidden: Bool
    /// `UITabBarController.isTabBarHidden`.
    public var controllerHidden: Bool
    public var alpha: Double
    /// Frame in window coordinates.
    public var minY: Double
    public var maxY: Double
    public var windowHeight: Double

    public init(found: Bool, hidden: Bool = false, controllerHidden: Bool = false, alpha: Double = 1,
                minY: Double = 0, maxY: Double = 0, windowHeight: Double = 1080) {
        self.found = found
        self.hidden = hidden
        self.controllerHidden = controllerHidden
        self.alpha = alpha
        self.minY = minY
        self.maxY = maxY
        self.windowHeight = windowHeight
    }

    public static let notFound = TabBarState(found: false)

    private var offScreen: Bool { maxY <= 1 || minY >= windowHeight - 1 }

    public var onScreen: Bool { found && !hidden && !controllerHidden && alpha > 0.01 && !offScreen }

    public var summary: String {
        guard found else { return "nicht gefunden" }
        if controllerHidden { return "versteckt (Controller)" }
        if hidden { return "versteckt (isHidden)" }
        if alpha <= 0.01 { return "unsichtbar (Alpha \(Self.fmt(alpha)))" }
        if offScreen { return "außerhalb des Bildes (y \(Int(minY.rounded()))…\(Int(maxY.rounded())))" }
        let a = alpha < 0.99 ? ", Alpha \(Self.fmt(alpha))" : ""
        return "sichtbar (y \(Int(minY.rounded()))…\(Int(maxY.rounded()))\(a))"
    }

    private static func fmt(_ v: Double) -> String { String(format: "%.2f", v) }
}

/// Log lines of the tab bar probe on the home page (category "nav", German like all log lines).
public enum TabBarReachLog {
    /// Result of an up move seen by the focus system.
    public enum UpOutcome: Hashable, Sendable {
        /// Focus moved into the tab bar.
        case reachedBar
        /// Focus moved to another element in the content (described).
        case stayedInContent(String)
        /// The focus engine found no target.
        case failed

        /// Case without details (throttle key).
        public var kind: String {
            switch self {
            case .reachedBar: "bar"
            case .stayedInContent: "content"
            case .failed: "failed"
            }
        }
    }

    /// Whether an up move gets a line: at the top edge always, away from it only a failed move.
    public static func logs(_ outcome: UpOutcome, atTop: Bool) -> Bool { atTop || outcome == .failed }

    public static func styleName(_ n: NavigationStyle) -> String { n == .top ? "Menü oben" : "Seitenleiste" }

    private static func pt(_ v: Double) -> String { "\(Int(v.rounded())) pt" }

    /// Top edge got focus and the focus scroll settled.
    public static func arrived(edge: HomeTopEdge, offset: Double, scrolledToTop: Bool, bar: TabBarState,
                               request: HomeTopRules.BarRequest, navigation: NavigationStyle) -> String {
        var s = "Oberer Rand fokussiert (\(edge.logName)) · Versatz \(pt(offset))"
        if scrolledToTop { s += " → nach ganz oben" }
        s += " · Leiste \(bar.summary)"
        if request == .visible { s += " · Leiste angefordert" }
        return s + " · \(styleName(navigation))"
    }

    /// Wave F-m: one repair step of a stuck tab bar with the state before and after it. `page` names the visible
    /// page (tab and depth). `applied` is false when the step could not run (no page scroll view or no tab bar
    /// controller found); `observed` names the content scroll view the tab bar controller reports before the step.
    public static func repaired(_ step: TabBarRepair, trigger: TabBarRepair.Trigger, page: String, applied: Bool,
                                before: TabBarState, after: TabBarState, offset: Double, observed: String,
                                navigation: NavigationStyle) -> String {
        let what = applied ? step.logName : "\(step.logName) nicht möglich"
        return "Leiste hing fest (\(trigger.logName), \(page)): \(before.summary) · Versatz \(pt(offset))"
            + " · beobachtet \(observed) → \(what) · danach Leiste \(after.summary) · \(styleName(navigation))"
    }

    /// Wave F-m: all steps ran on this page and the bar is still stuck (logged once per visit).
    public static func repairExhausted(trigger: TabBarRepair.Trigger, page: String, bar: TabBarState, offset: Double,
                                       navigation: NavigationStyle) -> String {
        "Leiste hängt weiter (\(trigger.logName), \(page)), alle Reparaturen versucht · Leiste \(bar.summary)"
            + " · Versatz \(pt(offset)) · \(styleName(navigation))"
    }

    /// An up move while the home page is visible. `atTop`: focus was on the top edge (or just left it).
    public static func up(_ outcome: UpOutcome, atTop: Bool, edge: HomeTopEdge, bar: TabBarState, offset: Double,
                          navigation: NavigationStyle) -> String? {
        guard logs(outcome, atTop: atTop) else { return nil }
        let tail = "Leiste \(bar.summary) · Versatz \(pt(offset)) · \(styleName(navigation))"
        guard atTop else {
            // Up inside the content is normal; only a failed move is worth a line.
            return "Hoch gescheitert, nicht am oberen Rand (oben: \(edge.logName)) · \(tail)"
        }
        switch outcome {
        case .reachedBar:
            return "Hoch am oberen Rand → Leiste erreicht · \(styleName(navigation))"
        case .stayedInContent(let what):
            return "Hoch am oberen Rand → Leiste nicht erreicht, Fokus blieb im Inhalt (\(what)) · \(tail)"
        case .failed:
            return "Hoch am oberen Rand → Leiste nicht erreichbar (kein Ziel) · \(tail)"
        }
    }
}

/// At most one line per key and interval.
public struct LogThrottle: Sendable {
    public let interval: Double
    private var last: [String: Double] = [:]

    public init(interval: Double) { self.interval = interval }

    public mutating func allow(_ key: String, now: Double) -> Bool {
        if let t = last[key], now - t < interval { return false }
        last[key] = now
        return true
    }
}

/// Wave F-j round 1 (hypothesis D): an autostart (continue with the last source, "play now") must not open the
/// full-screen player while the push transition of the source list is still running. Presenting during a push
/// can leave the tab bar in a stale state. The source list waits until `settleMs` after it appeared.
public enum AutostartAfterPush {
    /// Push transition on tvOS (about 0.5 s) plus margin.
    public static let settleMs = 700

    /// Remaining wait before the player may open, given the time since the source list appeared (0 = now).
    public static func remainingWait(elapsedMs: Int) -> Int { max(0, settleMs - max(0, elapsedMs)) }
}

/// Wave F-m round 2 (review N-I1): which scroll view of the visible page drives the top tab bar. Only a scroll view
/// that scrolls vertically counts (a full-width hero row strip of 738 pt is taller than the 570 pt hero home list
/// but scrolls sideways), compared by its part inside the window (rows built below the screen do not count). A
/// scroll view the page handed over itself (home list) wins while it is eligible.
public enum PageScrollPick {
    public struct Candidate: Equatable, Sendable {
        /// Frame in window coordinates.
        public var frame: CGRect
        public var contentSize: CGSize
        public var alwaysBounceVertical: Bool
        /// Handed over by the page (known main list).
        public var known: Bool

        public init(frame: CGRect, contentSize: CGSize, alwaysBounceVertical: Bool = false, known: Bool = false) {
            self.frame = frame
            self.contentSize = contentSize
            self.alwaysBounceVertical = alwaysBounceVertical
            self.known = known
        }

        public var scrollsVertically: Bool { contentSize.height > frame.height + 1 || alwaysBounceVertical }
    }

    /// Minimum visible height, as a share of the window height.
    public static let minHeightShare: CGFloat = 0.4

    /// Index of the chosen candidate; outermost (first) on equal visible area, nil if none qualifies.
    public static func choose(_ candidates: [Candidate], window: CGRect) -> Int? {
        var best: Int?
        var bestArea: CGFloat = 0
        for (i, c) in candidates.enumerated() where c.scrollsVertically {
            let visible = c.frame.intersection(window)
            guard !visible.isNull, visible.height >= window.height * minHeightShare else { continue }
            if c.known { return i }
            let area = visible.width * visible.height
            if area > bestArea { best = i; bestArea = area }
        }
        return best
    }
}
