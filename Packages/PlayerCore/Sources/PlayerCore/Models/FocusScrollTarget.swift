import Foundation

// Build 7 device test (b6-1 log, 27.11.): "Manchmal beim Stoppen geht die Karte etwas hoch" and "Poster immer noch
// links abgeschnitten, wenn nach links geklickt".
//
// Vertical: the focus engine does not scroll a home row to the list's top edge, it centres the focused card in the
// list frame (676 pt, bottom inset included). Rows that nearly fill the list (posters, 627 pt) have no room to move,
// so they ended ±20 pt off; shorter rows (landscape/logo tiles, 432 pt) ended with their top ~80 pt low
// (`Abstand +75…+84, unten +115…+124` in 40 of 53 `nachgerastet` lines), and the heading snap then moved them up
// visibly. The home list now corrects the focus scroll's own target (scroll target behaviour), so the first scroll
// already ends at the row's top.
//
// Horizontal: moving left, the focus engine scrolls just far enough to show the focused card's frame, i.e. to the
// row's leading edge (x ≈ 0). The lifted card (scale, glow/shadow) reaches past the screen edge there. The first
// card at rest sits at the 80 pt content margin; a card revealed by a left move now lands on that line too.

public enum FocusScrollTarget {
    /// Moves closer than this are no direction (points).
    public static let directionSlack: Double = 0.5

    /// Horizontal strip, scroll target x (the visible rect's leading edge in content coordinates). Only a target that
    /// moves toward the leading end (`proposed` < `current`) changes: it goes `clearance` further, so the revealed
    /// card sits `clearance` inside the leading edge; never past `minimum` (the start position; Build 8: 0,
    /// the target rect is inset-adjusted).
    public static func leading(proposed: Double, current: Double, clearance: Double, minimum: Double) -> Double {
        guard proposed < current - directionSlack, clearance > 0 else { return proposed }
        return max(min(minimum, proposed), proposed - clearance)
    }

    /// Build 8 device test (b7-1 log: 0 `Fokus-Scroll auf Reihenoberkante` lines): the b7 rule picked the row from
    /// UIKit's focused item, which can still be the previous row's card while the focus engine computes the scroll
    /// (stale, rejected). The row now comes from the proposed target itself: the focus engine centres the focused
    /// card, so the centre of the proposed visible rect lies in the row the focus moved into.
    ///
    /// Vertical home list, scroll target in `HomeListScroll.offset` terms (distance from the very top; the b7-1 log
    /// showed for the strips that the target rect is inset-adjusted, "vorher = Versatz + Inset"). `height`: height of
    /// the proposed visible rect. `rows`: the rows' frames in the same content coordinates.
    /// Unchanged: a target at the very top or already on a row's top (programmatic scrolls: rescue, `scrollToRow`,
    /// scroll to the top), a target at the content end (b8 review 2: the bottom button, last rows), no row at the
    /// centre, a correction larger than half the visible height (not a focus scroll of that row; also the way up to
    /// the hero buttons), or a row taller than the visible height (b8 review 5: its bottom would leave the list).
    public static func rowTop(proposed: Double, height: Double, rows: [(UUID, HomeRowSpan)],
                              maxOffset: Double) -> VerticalDecision {
        let probe = proposed + height / 2
        func keep(_ o: VerticalOutcome, _ row: (UUID, HomeRowSpan)? = nil) -> VerticalDecision {
            VerticalDecision(outcome: o, target: proposed, probeY: probe, row: row?.0, span: row?.1)
        }
        guard height > 0 else { return keep(.noScroll) }
        guard proposed > HeadingSnap.tolerance else { return keep(.veryTop) }
        let end = max(0, maxOffset)
        func top(_ span: HomeRowSpan) -> Double { min(max(span.minY, 0), end) }
        if let r = rows.first(where: { abs(top($0.1) - proposed) <= HeadingSnap.tolerance }) {
            return keep(.atRowTop, r)
        }
        guard proposed < end - HeadingSnap.tolerance else { return keep(.atEnd) }
        guard let row = row(at: probe, rows: rows) else { return keep(.noRow) }
        let target = top(row.1)
        guard abs(target - proposed) <= height / 2 else { return keep(.tooFar, row) }
        guard row.1.maxY - target <= height + directionSlack else { return keep(.tooTall, row) }
        guard abs(target - proposed) > HeadingSnap.tolerance else { return keep(.atRowTop, row) }
        return VerticalDecision(outcome: .retargeted, target: target, probeY: probe, row: row.0, span: row.1)
    }

    /// Rows are 50–70 pt apart; a centre in that gap belongs to the nearer row. Farther away (hero, action button)
    /// there is no row.
    public static let gapSlack: Double = 80

    /// The row containing `y`, else the nearest one within `gapSlack`.
    public static func row(at y: Double, rows: [(UUID, HomeRowSpan)]) -> (UUID, HomeRowSpan)? {
        if let r = rows.first(where: { y >= $0.1.minY && y <= $0.1.maxY }) { return r }
        func distance(_ s: HomeRowSpan) -> Double { y < s.minY ? s.minY - y : y - s.maxY }
        guard let near = rows.min(by: { distance($0.1) < distance($1.1) }), distance(near.1) <= gapSlack
        else { return nil }
        return near
    }

    /// Why one call of the vertical behaviour kept or changed the target (log text German).
    public enum VerticalOutcome: String, CaseIterable, Hashable, Sendable {
        case notVertical = "nicht senkrecht"
        case offMain = "nicht im Hauptthread"
        case noScroll = "kein Scrollzustand"
        case rescue = "Rettung läuft"
        case veryTop = "Ziel ganz oben"
        case atRowTop = "Ziel schon an Reihenoberkante"
        case atEnd = "Ziel am Inhaltsende"
        case noRow = "keine Reihe in der Mitte"
        case tooFar = "Korrektur über halbe Höhe"
        case tooTall = "Reihe höher als die Liste"
        case retargeted = "auf Reihenoberkante"
    }

    public struct VerticalDecision: Hashable, Sendable {
        public var outcome: VerticalOutcome
        /// Final target (= proposed unless `retargeted`).
        public var target: Double
        /// Centre of the proposed visible rect (content y) used to pick the row; nil when the call ended before
        /// (b8 review 1).
        public var probeY: Double?
        public var row: UUID?
        public var span: HomeRowSpan?

        public init(outcome: VerticalOutcome, target: Double, probeY: Double?, row: UUID?, span: HomeRowSpan?) {
            self.outcome = outcome
            self.target = target
            self.probeY = probeY
            self.row = row
            self.span = span
        }
    }

    /// b7 review 5: after a rescued up/down press (`HomeMoveRescue`: scroll to a row, the action button or the very
    /// top) the home list leaves scroll targets alone this long (seconds), so a later target update cannot pull the
    /// list back to the old row while the rescue's own scroll runs.
    public static let rescueQuiet: Double = 1

    /// May the vertical target be moved? `lastRescue`: uptime of the last rescue (nil: none).
    public static func mayRetarget(now: Double, lastRescue: Double?) -> Bool {
        guard let lastRescue else { return true }
        return now - lastRescue >= rescueQuiet || now < lastRescue
    }

    // MARK: Log lines ("nav")

    /// "Fokus-Scroll auf Reihenoberkante: Ziel 3545 → 3628 (Reihe 3628…4060)".
    public static func rowLine(proposed: Double, adjusted: Double, row: HomeRowSpan) -> String {
        "Fokus-Scroll auf Reihenoberkante: Ziel \(pt(proposed)) → \(pt(adjusted)) (Reihe \(pt(row.minY))…\(pt(row.maxY)))"
    }

    /// "Fokus-Scroll links mit Rand: Ziel 412 → 332 (vorher 700, Versatz 700, Start −80)". b7 review 1: `current` is
    /// the behaviour's original target, `offset` the strip's content offset (ScrollGeometry) at that moment; at rest
    /// both should match, which confirms the coordinate space on the device.
    public static func leadingLine(proposed: Double, adjusted: Double, current: Double, offset: Double?,
                                   start: Double) -> String {
        let o = offset.map { pt($0) } ?? "?"
        return "Fokus-Scroll links mit Rand: Ziel \(pt(proposed)) → \(pt(adjusted)) (vorher \(pt(current)), Versatz \(o), Start \(pt(start)))"
    }

    /// Build 8: one call of the vertical behaviour (first `FocusScrollProbe.detailLines` per app run): "Fokus-Scroll
    /// senkrecht #3: keine Reihe in der Mitte · Ziel 3356 → 3356 · Höhe 676 · Mitte 3694". With a row:
    /// "… · Reihe 3434…3866".
    public static func verticalLine(number: Int, outcome: VerticalOutcome, proposed: Double, target: Double,
                                    height: Double?, probeY: Double?, span: HomeRowSpan?) -> String {
        var parts = ["Fokus-Scroll senkrecht #\(number): \(outcome.rawValue)", "Ziel \(pt(proposed)) → \(pt(target))"]
        if let height { parts.append("Höhe \(pt(height))") }
        if let probeY { parts.append("Mitte \(pt(probeY))") }
        if let span { parts.append("Reihe \(pt(span.minY))…\(pt(span.maxY))") }
        return parts.joined(separator: " · ")
    }

    private static func pt(_ v: Double) -> String { "\(Int(v.rounded()))" }
}

/// Build 8: counts the calls of the vertical focus scroll behaviour per outcome, so the device log tells whether it
/// is called at all and which guard keeps it out. The first `detailLines` calls per app run get a line each; a
/// summary (with the number of row entries for comparison) follows every `summaryEvery` calls and when the home
/// page disappears.
public struct FocusScrollProbe: Sendable {
    public static let detailLines = 20
    public static let summaryEvery = 100

    /// b8 review 6: counted only, no detail line (launch and scroll-to-top calls would use up the lines).
    public static let quiet: Set<FocusScrollTarget.VerticalOutcome> = [.veryTop]

    public private(set) var total = 0
    /// Detail lines given so far.
    public private(set) var detailed = 0
    public private(set) var counts: [FocusScrollTarget.VerticalOutcome: Int] = [:]
    /// Rows the focus entered (`showHeading`): with 0 calls this says "never called", not "nothing happened".
    public private(set) var rowEntries = 0
    private var summarized: (total: Int, rows: Int)?

    public init() {}

    /// Counts one call; `true`: it gets its own line (call number = `total`). `quiet` outcomes never do.
    public mutating func note(_ outcome: FocusScrollTarget.VerticalOutcome) -> Bool {
        total += 1
        counts[outcome, default: 0] += 1
        guard !Self.quiet.contains(outcome), detailed < Self.detailLines else { return false }
        detailed += 1
        return true
    }

    public mutating func noteRowEntry() { rowEntries += 1 }

    /// After `note`: time for a periodic summary.
    public var summaryDue: Bool { total > 0 && total % Self.summaryEvery == 0 }

    /// The summary line, nil when nothing changed since the last one (`markSummarized`).
    public func summaryLine() -> String? {
        if let s = summarized, s.total == total, s.rows == rowEntries { return nil }
        guard total > 0 || rowEntries > 0 else { return nil }
        let parts = FocusScrollTarget.VerticalOutcome.allCases.compactMap { o in
            counts[o].map { "\(o.rawValue) \($0)" }
        }
        let tail = parts.isEmpty ? "" : " · " + parts.joined(separator: " · ")
        return "Fokus-Scroll senkrecht: \(total) Aufrufe bei \(rowEntries) Reihenwechseln\(tail)"
    }

    public mutating func markSummarized() { summarized = (total, rowEntries) }
}

/// Build 8 (b7-1 log 17:53:16.2: a snap at 0.4 s moved Preise from +15 to +71, the system's focus scroll was still
/// running to its own target): the last target a scroll of the home list was heading for. While the list is still
/// on its way there, the heading checks do not snap; a focus scroll retargeted to a row's top owns that row change
/// (`showHeading` then adds no scroll of its own).
public struct FocusScrollFlight: Hashable, Sendable {
    /// The system's focus scroll takes about 0.3–0.4 s.
    public static let window: Double = 0.6

    /// Target in `HomeListScroll.offset` terms.
    public var target: Double
    /// Uptime of the target update.
    public var at: Double
    /// The row whose top the target was moved to (`retargeted`), nil otherwise.
    public var row: UUID?

    public init(target: Double, at: Double, row: UUID?) {
        self.target = target
        self.at = at
        self.row = row
    }

    private func recent(_ now: Double) -> Bool { now >= at && now - at < Self.window }

    /// b8 review 4: the list counts as moving while its offset changed this recently (seconds).
    public static let movingWindow: Double = 0.12

    /// Still on the way: recent, more than `HeadingSnap.snapMinimum` away from the target and still moving
    /// (`lastMove`: uptime of the last offset change). A list that came to rest off a kept target is not in flight,
    /// so the check snaps it.
    public func inFlight(now: Double, offset: Double, lastMove: Double?) -> Bool {
        guard recent(now), abs(offset - target) > HeadingSnap.snapMinimum, let lastMove else { return false }
        return now >= lastMove && now - lastMove < Self.movingWindow
    }

    /// A recent focus scroll heads for this row's top: it owns the row change.
    public func owns(row id: UUID, now: Double) -> Bool { row == id && recent(now) }
}
