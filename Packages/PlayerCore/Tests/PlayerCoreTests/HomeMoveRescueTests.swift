import Testing
import Foundation
@testable import PlayerCore

// Build 5 device test 1, item 2: up from the first row must reach the hero buttons; item 7: a dropped up/down
// press in the rows moves to the neighbour row instead of being swallowed.
@Test func upFromTheFirstRowGoesToTheHeroButtons() {
    #expect(HomeMoveRescue.decide(up: true, focusedRow: 0, rowCount: 9, edge: .heroButtons) == .heroButtons)
    // Without a hero the first row is the top edge; the tab bar above is reached by the system.
    #expect(HomeMoveRescue.decide(up: true, focusedRow: 0, rowCount: 9, edge: .firstRow) == nil)
}

@Test func droppedMovesInTheRowsGoToTheNeighbourRow() {
    #expect(HomeMoveRescue.decide(up: true, focusedRow: 3, rowCount: 9, edge: .heroButtons) == .row(2))
    #expect(HomeMoveRescue.decide(up: false, focusedRow: 3, rowCount: 9, edge: .heroButtons) == .row(4))
    #expect(HomeMoveRescue.decide(up: true, focusedRow: 3, rowCount: 9, edge: .firstRow) == .row(2))
}

@Test func noRescueOutsideTheRows() {
    #expect(HomeMoveRescue.decide(up: true, focusedRow: nil, rowCount: 9, edge: .heroButtons) == nil)
    #expect(HomeMoveRescue.decide(up: false, focusedRow: 9, rowCount: 9, edge: .heroButtons) == nil)
}

// Review N2: down from the last row reaches the „Reihen & Collections“ button the lazy list had not built yet.
@Test func downFromTheLastRowGoesToTheActionButton() {
    #expect(HomeMoveRescue.decide(up: false, focusedRow: 8, rowCount: 9, edge: .heroButtons) == .actionButton)
    #expect(HomeMoveRescue.decide(up: false, focusedRow: 0, rowCount: 1, edge: .firstRow) == .actionButton)
    #expect(HomeMoveRescue.actionButton.line(up: false, from: 8, fromTitle: "Genres", toTitle: nil)
            == "Runter verschluckt in Reihe 9 (Genres) → Knopf „Reihen & Collections“ fokussiert")
}

@Test func rescueLineNamesBothEnds() {
    #expect(HomeMoveRescue.heroButtons.line(up: true, from: 0, fromTitle: "Weiterschauen", toTitle: nil)
            == "Hoch verschluckt in Reihe 1 (Weiterschauen) → Knopfzeile fokussiert")
    #expect(HomeMoveRescue.row(4).line(up: false, from: 3, fromTitle: "Genres", toTitle: "Streaming-Dienste")
            == "Runter verschluckt in Reihe 4 (Genres) → Reihe 5 (Streaming-Dienste) fokussiert")
}

// Review W2/M1: the row of a dropped press comes from the element that kept the focus (its centre in the list's
// content), not from the row-presence set (a leave is reported 100 ms late).
@Test func rescueRowIsTheRowUnderTheFocusedElement() {
    let spans: [(UUID, HomeRowSpan)] = [(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, HomeRowSpan(minY: 470, maxY: 900)),
                                        (UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, HomeRowSpan(minY: 964, maxY: 1400))]
    #expect(HomeMoveRescue.row(atContentY: 700, spans: spans) == spans[0].0)
    #expect(HomeMoveRescue.row(atContentY: 1000, spans: spans) == spans[1].0)
    // Between rows (gap) or above them (hero buttons): no row, no rescue.
    #expect(HomeMoveRescue.row(atContentY: 930, spans: spans) == nil)
    #expect(HomeMoveRescue.row(atContentY: 200, spans: spans) == nil)
}
