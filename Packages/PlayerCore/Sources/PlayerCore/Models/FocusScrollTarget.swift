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
    /// card sits `clearance` inside the leading edge; never past `minimum` (the start position, minus the leading
    /// content margin).
    public static func leading(proposed: Double, current: Double, clearance: Double, minimum: Double) -> Double {
        guard proposed < current - directionSlack, clearance > 0 else { return proposed }
        return max(min(minimum, proposed), proposed - clearance)
    }

    /// Vertical home list, scroll target in `HomeListScroll.offset` terms (distance from the very top). The row that
    /// holds the focus goes to the list's top edge (as far as the content end allows) instead of where the focus
    /// engine put it. Unchanged when the correction is larger than half the visible height (not a focus scroll of
    /// this row: a programmatic scroll or a move to another row), or when the focused element would leave the
    /// visible part (rows taller than the list).
    /// - `focused`: the focused element's frame in the same content coordinates (nil: unknown, no change).
    public static func rowTop(proposed: Double, viewport: Double, row: HomeRowSpan, focused: HomeRowSpan?,
                              maxOffset: Double) -> Double {
        guard let focused, viewport > 0 else { return proposed }
        let target = min(max(row.minY, 0), max(0, maxOffset))
        guard abs(target - proposed) <= viewport / 2 else { return proposed }
        guard focused.minY >= target - directionSlack, focused.maxY <= target + viewport + directionSlack else {
            return proposed
        }
        return target
    }

    // MARK: Log lines ("nav")

    /// "Fokus-Scroll auf Reihenoberkante: Ziel 3545 → 3628 (Reihe 3628…4060)".
    public static func rowLine(proposed: Double, adjusted: Double, row: HomeRowSpan) -> String {
        "Fokus-Scroll auf Reihenoberkante: Ziel \(pt(proposed)) → \(pt(adjusted)) (Reihe \(pt(row.minY))…\(pt(row.maxY)))"
    }

    /// "Fokus-Scroll links mit Rand: Ziel 412 → 332 (vorher 700)".
    public static func leadingLine(proposed: Double, adjusted: Double, current: Double) -> String {
        "Fokus-Scroll links mit Rand: Ziel \(pt(proposed)) → \(pt(adjusted)) (vorher \(pt(current)))"
    }

    private static func pt(_ v: Double) -> String { "\(Int(v.rounded()))" }
}
