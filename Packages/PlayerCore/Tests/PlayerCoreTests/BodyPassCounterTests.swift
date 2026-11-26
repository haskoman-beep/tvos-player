import Foundation
import Testing
@testable import PlayerCore

// Build 4 follow-up S4: `metric: home.rowBody` – body passes of the home rows per 5 s window with focus movement.

@Test func bodyPassCounterOpensOneWindowAndReportsOnlyWithFocusMoves() {
    var c = BodyPassCounter()
    #expect(BodyPassCounter.window == 5)
    // Records which events opened a window (the caller closes it after `window`).
    var opened: [Bool] = []
    func pass() { opened.append(c.pass()) }
    func move() { opened.append(c.focusMoved()) }

    pass(); pass(); move(); pass()
    #expect(opened == [true, false, false, false])   // only the first event opens the window
    let w = c.close()
    #expect(w?.passes == 3 && w?.focusMoves == 1)
    #expect(c.close() == nil)                        // closed: nothing left

    // Passes without any focus move (e.g. progress saves during playback): no line.
    opened = []
    pass(); pass()
    #expect(opened == [true, false])
    #expect(c.close() == nil)

    // A focus move may open the window too; after closing, the next event opens a new one.
    opened = []
    move(); pass()
    #expect(opened == [true, false])
    let w2 = c.close()
    #expect(w2?.passes == 1 && w2?.focusMoves == 1)
    opened = []
    pass()
    #expect(opened == [true])
}

// S4 review minor 1: card body passes (PosterCard) in the same window, so the line shows the stable-anchor gain.
@Test func bodyPassCounterCountsCardPassesInTheSameWindow() {
    var c = BodyPassCounter()
    var opened: [Bool] = []
    opened.append(c.cardPass())
    opened.append(c.cardPass())
    opened.append(c.pass())
    opened.append(c.focusMoved())
    opened.append(c.cardPass())
    #expect(opened == [true, false, false, false, false])   // a card pass may open the window too
    let w = c.close()
    #expect(w?.passes == 1 && w?.cards == 3 && w?.focusMoves == 1)
    // Card passes without a focus move: no line, counters start from zero again.
    opened = [c.cardPass()]
    #expect(opened == [true])
    #expect(c.close() == nil)
    _ = c.focusMoved()
    #expect(c.close()?.cards == 0)
}

@Test func homeRowBodyMetricLine() {
    #expect(Metric.line(.homeRowBody, ms: 240, fields: ["fokus": "18"]) == "home.rowBody 240 · fokus 18")
}

// b5r: body passes of the equatable home row cards (`HomeRowCard`, field `zellen`): with the equatable cell a focus
// move should run about two of them (the card losing and the card gaining the focus), not every built card.
@Test func bodyPassCounterCountsCellPassesInTheSameWindow() {
    var c = BodyPassCounter()
    let first = c.cellPass()       // a cell pass may open the window
    let second = c.cellPass()
    #expect(first && !second)
    _ = c.pass()
    _ = c.focusMoved()
    let w = c.close()
    #expect(w?.cells == 2 && w?.passes == 1 && w?.cards == 0 && w?.focusMoves == 1)
    _ = c.focusMoved()
    #expect(c.close()?.cells == 0)  // counters start from zero again
}
