import Foundation
import Testing
@testable import PlayerCore

// MARK: Build 7: focus scroll targets (row top, leading clearance)

@Test func shortRowLandsAtItsTopInsteadOfCentred() {
    // b6-1 log: Studios 3628…4060, focus scroll ended at 3545 (Abstand +83); list 676 pt high.
    let row = HomeRowSpan(minY: 3628, maxY: 4060)
    let card = HomeRowSpan(minY: 3710, maxY: 4040)
    #expect(FocusScrollTarget.rowTop(proposed: 3545, viewport: 676, row: row, focused: card, maxOffset: 7160) == 3628)
    // Tall poster row: ±20 pt off becomes exact too.
    let tall = HomeRowSpan(minY: 2938, maxY: 3565)
    let poster = HomeRowSpan(minY: 3020, maxY: 3540)
    #expect(FocusScrollTarget.rowTop(proposed: 2919, viewport: 676, row: tall, focused: poster, maxOffset: 6313) == 2938)
}

@Test func rowTopStopsAtTheContentEnd() {
    let row = HomeRowSpan(minY: 7042, maxY: 7669)
    let card = HomeRowSpan(minY: 7120, maxY: 7600)
    #expect(FocusScrollTarget.rowTop(proposed: 6950, viewport: 676, row: row, focused: card, maxOffset: 7000) == 7000)
    // A row at the very top cannot go above 0.
    let first = HomeRowSpan(minY: -10, maxY: 600)
    #expect(FocusScrollTarget.rowTop(proposed: 30, viewport: 676, row: first,
                                     focused: HomeRowSpan(minY: 70, maxY: 580), maxOffset: 5000) == 0)
}

@Test func rowTopLeavesOtherScrollsAlone() {
    let row = HomeRowSpan(minY: 3628, maxY: 4060)
    let card = HomeRowSpan(minY: 3710, maxY: 4040)
    // More than half the visible height: not this row's focus scroll (rescue, scroll to the top, other row).
    #expect(FocusScrollTarget.rowTop(proposed: 3200, viewport: 676, row: row, focused: card, maxOffset: 7160) == 3200)
    // Unknown focused element: no change.
    #expect(FocusScrollTarget.rowTop(proposed: 3545, viewport: 676, row: row, focused: nil, maxOffset: 7160) == 3545)
    // Row taller than the list: the focused card would leave the visible part at the row's top.
    let huge = HomeRowSpan(minY: 1000, maxY: 1900)
    let low = HomeRowSpan(minY: 1300, maxY: 1850)
    #expect(FocusScrollTarget.rowTop(proposed: 1200, viewport: 676, row: huge, focused: low, maxOffset: 5000) == 1200)
}

@Test func leftMoveKeepsTheContentMargin() {
    // Focus scroll to the leading edge (card at x 0) → card on the 80 pt line.
    #expect(FocusScrollTarget.leading(proposed: 412, current: 700, clearance: 80, minimum: -80) == 332)
    // First card: back to the start position, never past it.
    #expect(FocusScrollTarget.leading(proposed: 0, current: 300, clearance: 80, minimum: -80) == -80)
    #expect(FocusScrollTarget.leading(proposed: -40, current: 300, clearance: 80, minimum: -80) == -80)
    // Moving right or standing still: unchanged.
    #expect(FocusScrollTarget.leading(proposed: 900, current: 700, clearance: 80, minimum: -80) == 900)
    #expect(FocusScrollTarget.leading(proposed: 700.2, current: 700, clearance: 80, minimum: -80) == 700.2)
    // Already before the start (other coordinates): left alone.
    #expect(FocusScrollTarget.leading(proposed: -120, current: 300, clearance: 80, minimum: -80) == -120)
}

@Test func focusScrollLogLines() {
    #expect(FocusScrollTarget.rowLine(proposed: 3545, adjusted: 3628, row: HomeRowSpan(minY: 3628, maxY: 4060))
            == "Fokus-Scroll auf Reihenoberkante: Ziel 3545 → 3628 (Reihe 3628…4060)")
    #expect(FocusScrollTarget.leadingLine(proposed: 412, adjusted: 332, current: 700, offset: 700, start: -80)
            == "Fokus-Scroll links mit Rand: Ziel 412 → 332 (vorher 700, Versatz 700, Start -80)")
    #expect(FocusScrollTarget.leadingLine(proposed: 0, adjusted: 0, current: 300, offset: nil, start: 0)
            == "Fokus-Scroll links mit Rand: Ziel 0 → 0 (vorher 300, Versatz ?, Start 0)")
}

@Test func staleFocusedElementOutsideTheProposedRectIsIgnored() {
    // b7 review 3: the focus engine scrolls to the next row while the focused element is still the previous row's
    // card: that card is not inside the proposed visible part, so no snap back to it.
    let row = HomeRowSpan(minY: 3628, maxY: 4060)
    let oldCard = HomeRowSpan(minY: 3710, maxY: 4040)
    #expect(FocusScrollTarget.rowTop(proposed: 3800, viewport: 676, row: row, focused: oldCard, maxOffset: 7160) == 3800)
    // Partly visible counts as outside too.
    #expect(FocusScrollTarget.rowTop(proposed: 3330, viewport: 676, row: row, focused: oldCard, maxOffset: 7160) == 3330)
}

@Test func retargetWaitsAfterARescue() {
    // b7 review 5: one second after a rescued press the list keeps the proposed targets.
    #expect(FocusScrollTarget.mayRetarget(now: 100, lastRescue: nil))
    #expect(!FocusScrollTarget.mayRetarget(now: 100.4, lastRescue: 100))
    #expect(!FocusScrollTarget.mayRetarget(now: 100.99, lastRescue: 100))
    #expect(FocusScrollTarget.mayRetarget(now: 101, lastRescue: 100))
    // Clock went backwards (other uptime source): no lock-out.
    #expect(FocusScrollTarget.mayRetarget(now: 50, lastRescue: 100))
}

@Test func startClampUsesTheRealLeadingInset() {
    // b7 review 2: with no leading inset the start is 0; a left move to the first card never overscrolls.
    #expect(FocusScrollTarget.leading(proposed: 0, current: 300, clearance: 80, minimum: 0) == 0)
    #expect(FocusScrollTarget.leading(proposed: 40, current: 300, clearance: 80, minimum: 0) == 0)
    // Right move counted from the original target: unchanged.
    #expect(FocusScrollTarget.leading(proposed: 340, current: 300, clearance: 80, minimum: -80) == 340)
}
