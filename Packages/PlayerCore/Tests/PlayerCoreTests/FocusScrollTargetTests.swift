import Foundation
import Testing
@testable import PlayerCore

// MARK: Build 7: focus scroll targets (row top, leading clearance)

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

// MARK: Build 8: vertical row from the proposed rect, probe, flight

private let studios = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
private let preise = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
private let genres = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
/// b7-1 log: Preise 2938…3370, Studios 3434…3866, Genres 3930…4362, list 676 pt high, max ≈ 7406.
private let homeRows: [(UUID, HomeRowSpan)] = [
    (preise, HomeRowSpan(minY: 2938, maxY: 3370)),
    (studios, HomeRowSpan(minY: 3434, maxY: 3866)),
    (genres, HomeRowSpan(minY: 3930, maxY: 4362)),
]

@Test func centredFocusScrollGoesToTheRowTop() {
    // Studios landed at 3356 (Abstand +78): the centre 3694 lies in Studios → its top.
    let d = FocusScrollTarget.rowTop(proposed: 3356, height: 676, rows: homeRows, maxOffset: 7406)
    #expect(d.outcome == .retargeted)
    #expect(d.target == 3434)
    #expect(d.row == studios)
    #expect(d.probeY == 3694)
    // Genres +73 (3857) and Preise +128 (2810) as well.
    #expect(FocusScrollTarget.rowTop(proposed: 3857, height: 676, rows: homeRows, maxOffset: 7406).target == 3930)
    #expect(FocusScrollTarget.rowTop(proposed: 2810, height: 676, rows: homeRows, maxOffset: 7406).target == 2938)
}

@Test func rowChoiceNeedsNoFocusedItem() {
    // b7-1: the focused UIKit item can still be the previous row's card; the target alone decides. A move up from
    // Genres into Studios proposes Studios' card centred (3356) and lands on Studios, not back on Genres.
    let d = FocusScrollTarget.rowTop(proposed: 3356, height: 676, rows: homeRows, maxOffset: 7406)
    #expect(d.row == studios)
}

@Test func centreInTheGapBetweenRowsTakesTheNearerRow() {
    // Centre 3400 between Preise (…3370) and Studios (3434…): Preise is 30 pt away, Studios 34.
    let d = FocusScrollTarget.rowTop(proposed: 3062, height: 676, rows: homeRows, maxOffset: 7406)
    #expect(d.row == preise)
    #expect(d.target == 2938)
    // Far from every row (hero above the rows): no row.
    let hero = FocusScrollTarget.rowTop(proposed: 1800, height: 676, rows: homeRows, maxOffset: 7406)
    #expect(hero.outcome == .noRow)
    #expect(hero.target == 1800)
}

@Test func programmaticScrollsKeepTheirTarget() {
    // Already on a row's top (scrollToRow, rescue): unchanged, even for a row shorter than half the list.
    let short: [(UUID, HomeRowSpan)] = [(preise, HomeRowSpan(minY: 1000, maxY: 1200)),
                                        (studios, HomeRowSpan(minY: 1260, maxY: 1900))]
    let d = FocusScrollTarget.rowTop(proposed: 1000, height: 676, rows: short, maxOffset: 7406)
    #expect(d.outcome == .atRowTop)
    #expect(d.target == 1000)
    // Very top (hero, scroll to the top).
    #expect(FocusScrollTarget.rowTop(proposed: 0, height: 676, rows: homeRows, maxOffset: 7406).outcome == .veryTop)
    // More than half the visible height away: not this row's focus scroll.
    let far: [(UUID, HomeRowSpan)] = [(genres, HomeRowSpan(minY: 3000, maxY: 4000))]
    let f = FocusScrollTarget.rowTop(proposed: 2600, height: 676, rows: far, maxOffset: 7406)
    #expect(f.outcome == .tooFar)
    #expect(f.target == 2600)
    // No height: nothing to decide.
    #expect(FocusScrollTarget.rowTop(proposed: 3356, height: 0, rows: homeRows, maxOffset: 7406).outcome == .noScroll)
}

@Test func rowTopStopsAtTheContentEnd() {
    let last: [(UUID, HomeRowSpan)] = [(genres, HomeRowSpan(minY: 7042, maxY: 7669))]
    let d = FocusScrollTarget.rowTop(proposed: 6950, height: 676, rows: last, maxOffset: 7000)
    #expect(d.outcome == .retargeted)
    #expect(d.target == 7000)
    // At the content end already: unchanged.
    #expect(FocusScrollTarget.rowTop(proposed: 7000, height: 676, rows: last, maxOffset: 7000).outcome == .atRowTop)
}

@Test func probeLogsTheFirstCallsAndSummarizes() {
    var p = FocusScrollProbe()
    #expect(p.summaryLine() == nil)
    p.noteRowEntry()
    #expect(p.summaryLine() == "Fokus-Scroll senkrecht: 0 Aufrufe bei 1 Reihenwechseln")
    for i in 1...FocusScrollProbe.detailLines {
        let detail = p.note(i == 1 ? .noRow : .retargeted)
        #expect(detail)
    }
    let late = p.note(.retargeted)
    #expect(!late)
    #expect(p.summaryLine() == "Fokus-Scroll senkrecht: 21 Aufrufe bei 1 Reihenwechseln · keine Reihe in der Mitte 1 · auf Reihenoberkante 20")
    p.markSummarized()
    #expect(p.summaryLine() == nil)
    while p.total < FocusScrollProbe.summaryEvery { _ = p.note(.atRowTop) }
    #expect(p.summaryDue)
    #expect(p.summaryLine() != nil)
}

@Test func verticalLogLine() {
    #expect(FocusScrollTarget.verticalLine(number: 3, outcome: .retargeted, proposed: 3356, target: 3434, height: 676,
                                           probeY: 3694, span: HomeRowSpan(minY: 3434, maxY: 3866))
            == "Fokus-Scroll senkrecht #3: auf Reihenoberkante · Ziel 3356 → 3434 · Höhe 676 · Mitte 3694 · Reihe 3434…3866")
    #expect(FocusScrollTarget.verticalLine(number: 1, outcome: .offMain, proposed: 10, target: 10, height: nil,
                                           probeY: nil, span: nil)
            == "Fokus-Scroll senkrecht #1: nicht im Hauptthread · Ziel 10 → 10")
}

@Test func flightBlocksSnapsAndOwnsTheRowChange() {
    let f = FocusScrollFlight(target: 3434, at: 100, row: studios)
    // b7-1 17:53:16.2 pattern: the list is still on its way → no snap.
    #expect(f.inFlight(now: 100.3, offset: 3380))
    // Arrived (within the snap minimum) or too old: not in flight.
    #expect(!f.inFlight(now: 100.3, offset: 3430))
    #expect(!f.inFlight(now: 100.7, offset: 3380))
    #expect(f.owns(row: studios, now: 100.1))
    #expect(!f.owns(row: genres, now: 100.1))
    #expect(!f.owns(row: studios, now: 101))
    #expect(!FocusScrollFlight(target: 3434, at: 100, row: nil).owns(row: studios, now: 100.1))
}

@Test func stripStartIsZeroInTargetSpace() {
    // b7-1 log: "vorher" = "Versatz" + 160 in all 7 lines, the target rect is inset-adjusted: the start is 0.
    #expect(FocusScrollTarget.leading(proposed: 60, current: 400, clearance: 80, minimum: 0) == 0)
    #expect(FocusScrollTarget.leading(proposed: 2384, current: 2960, clearance: 80, minimum: 0) == 2304)
}
