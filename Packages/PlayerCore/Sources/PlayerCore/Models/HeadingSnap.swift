import Foundation

// S5 (Build 4 follow-up): when focus enters a home row, the row (heading included) scrolls to the list's top edge.
// On first entry the system's focus scroll could finish after that snap (placeholder → card hand-over, slow first
// decodes), and the whole row stayed too low with its bottom cut. The home page now checks the row a few times while
// focus stays in it and snaps again only when the row's top is off the list's top edge.

/// Vertical scroll state of the home list in points. `offset` is the distance from the very top
/// (`contentOffset.y + contentInsets.top`): a row whose top (list content coordinates) equals `offset` sits at the
/// list's top edge.
public struct HomeListScroll: Hashable, Sendable {
    public var offset: Double
    /// Largest `offset` (content end); the last rows cannot reach the top edge.
    public var maxOffset: Double

    public init(offset: Double, maxOffset: Double) {
        self.offset = offset
        self.maxOffset = maxOffset
    }

    /// From the scroll view's geometry (`ScrollGeometry`): raw content offset, content height, insets, visible height.
    public init(contentOffsetY: Double, contentHeight: Double, insetTop: Double, insetBottom: Double,
                viewportHeight: Double) {
        offset = contentOffsetY + insetTop
        maxOffset = max(0, contentHeight + insetTop + insetBottom - viewportHeight)
    }
}

/// A home row's frame in the list's content coordinates (heading included; the scroll target of the row).
public struct HomeRowSpan: Hashable, Sendable {
    public var minY: Double
    public var maxY: Double

    public init(minY: Double, maxY: Double) {
        self.minY = minY
        self.maxY = maxY
    }
}

/// What the home page knows at one heading check (log line and decision).
public struct HeadingSnapSample: Hashable, Sendable {
    /// The list's scroll view as UIKit sees it (raw offset, frame in the window, adjusted insets, safe area top of
    /// the page).
    public struct ListView: Hashable, Sendable {
        public var offsetY: Double
        public var maxOffsetY: Double
        public var frameMinY: Double
        public var frameMaxY: Double
        public var insetTop: Double
        public var insetBottom: Double
        public var safeTop: Double

        public init(offsetY: Double, maxOffsetY: Double, frameMinY: Double, frameMaxY: Double, insetTop: Double,
                    insetBottom: Double, safeTop: Double) {
            self.offsetY = offsetY
            self.maxOffsetY = maxOffsetY
            self.frameMinY = frameMinY
            self.frameMaxY = frameMaxY
            self.insetTop = insetTop
            self.insetBottom = insetBottom
            self.safeTop = safeTop
        }
    }

    public var row: HomeRowSpan?
    public var scroll: HomeListScroll?
    public var list: ListView?

    public init(row: HomeRowSpan?, scroll: HomeListScroll?, list: ListView?) {
        self.row = row
        self.scroll = scroll
        self.list = list
    }
}

public enum HeadingSnap {
    /// A row closer than this to the list's top edge counts as in place (points).
    public static let tolerance: Double = 2
    /// Checks after focus entered the row (ms). The system's focus scroll runs about 0.3 s; hand-overs and first
    /// decodes can delay it. Bounded: after 1.5 s the row is left alone.
    public static let checksMs = [400, 900, 1500]
    /// Wait after a snap before the "nach Rasten" sample (the snap animates 0.2 s).
    public static let afterSnapMs = 250

    public enum Decision: Hashable, Sendable {
        /// No row frame or no scroll state yet.
        case unknown
        /// The row's top is at the list's top edge, or as close as the content end allows.
        case inPlace
        /// The row's top is `deviation` points off the list's top edge (positive: the row sits too low).
        case snap(deviation: Double)
    }

    /// Should the row scroll again? Only when a snap would move it by more than the tolerance (a row near the
    /// content end stops at the largest offset).
    public static func decide(row: HomeRowSpan?, scroll: HomeListScroll?, tolerance: Double = tolerance) -> Decision {
        guard let row, let scroll else { return .unknown }
        let target = min(max(row.minY, 0), scroll.maxOffset)
        guard abs(target - scroll.offset) > tolerance else { return .inPlace }
        return .snap(deviation: row.minY - scroll.offset)
    }

    /// `check`: index in `checksMs`. Without a measurement only the first check snaps (the Build 3 behaviour: one
    /// blind re-snap), so a missing frame never makes the list move three times.
    public static func shouldSnap(_ decision: Decision, check: Int) -> Bool {
        switch decision {
        case .snap: true
        case .unknown: check == 0
        case .inPlace: false
        }
    }

    // MARK: Log lines ("nav")

    /// A check snapped the row again: state before and after the snap.
    public static func snapLine(title: String, ms: Int, before: HeadingSnapSample, after: HeadingSnapSample) -> String {
        "Reihe \(title) nach \(seconds(ms)) nachgerastet: vorher \(text(before)) · nach Rasten \(text(after))"
    }

    /// The last check without a snap: where the row ended.
    public static func checkLine(title: String, ms: Int, decision: Decision, sample: HeadingSnapSample) -> String {
        let state: String
        switch decision {
        case .inPlace: state = "an der Oberkante"
        case .unknown: state = "Lage unbekannt"
        case .snap(let d): state = "weicht ab \(signed(d))"
        }
        return "Reihe \(title) nach \(seconds(ms)): \(state) · \(text(sample))"
    }

    /// "y 788/max 2460 · Reihe 850…1330 (Abstand +38) · Liste 470…1080 · Inset 24/60 · Safe 60". `y`/`max`: raw UIKit
    /// offset; Reihe: content coordinates; Abstand: row top minus list top edge; Liste: frame in the window.
    static func text(_ s: HeadingSnapSample) -> String {
        var parts: [String] = []
        if let l = s.list { parts.append("y \(pt(l.offsetY))/max \(pt(l.maxOffsetY))") } else { parts.append("keine Liste") }
        if let r = s.row {
            let gap = s.scroll.map { " (Abstand \(signed(r.minY - $0.offset)))" } ?? ""
            parts.append("Reihe \(pt(r.minY))…\(pt(r.maxY))\(gap)")
        } else {
            parts.append("Reihe ?")
        }
        if let l = s.list {
            parts.append("Liste \(pt(l.frameMinY))…\(pt(l.frameMaxY))")
            parts.append("Inset \(pt(l.insetTop))/\(pt(l.insetBottom))")
            parts.append("Safe \(pt(l.safeTop))")
        }
        return parts.joined(separator: " · ")
    }

    private static func pt(_ v: Double) -> String { "\(Int(v.rounded()))" }

    private static func signed(_ v: Double) -> String {
        let n = Int(v.rounded())
        return n > 0 ? "+\(n)" : "\(n)"
    }

    /// 400 → "0,4 s", 1500 → "1,5 s".
    private static func seconds(_ ms: Int) -> String { "\(ms / 1000),\((ms % 1000) / 100) s" }
}
