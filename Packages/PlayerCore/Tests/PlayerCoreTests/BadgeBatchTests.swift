import Foundation
import Testing
@testable import PlayerCore

// Build 4 follow-up 2 (P3): source results (badge values) are collected and handed to the cards in one pass:
// `coalesce` after the first one, not before the focus has been quiet for `focusQuiet`, at the latest `maxHold`
// after the first one. The values are the same; they only arrive later and together.

private let t0 = Date(timeIntervalSince1970: 2_000_000)
private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

@Test func badgeBatchLimitsAreDocumented() {
    let l = BadgeBatch.Limits()
    #expect(l.coalesce == 0.5)
    #expect(l.focusQuiet == FocusRest.prefetchQuiet)
    #expect(l.maxHold == 3)
}

@Test func badgeBatchCoalescesArrivalsIntoOnePass() {
    var b = BadgeBatch()
    #expect(b.flushAt == nil)
    #expect(b.take(now: t0) == nil)
    b.add("a", now: t0)
    #expect(b.flushAt == at(0.5))
    b.add("b", now: at(0.25))
    b.add("a", now: at(0.375))
    // The window counts from the first arrival, later ones do not push it (no starvation by a steady stream).
    #expect(b.flushAt == at(0.5))
    #expect(b.take(now: at(0.375)) == nil)
    let f = b.take(now: at(0.5))
    #expect(f == BadgeBatch.Flush(ids: ["a", "b"], waited: 0.5))
    #expect(b.flushAt == nil)
    #expect(b.take(now: at(1)) == nil)
}

@Test func badgeBatchWaitsForFocusQuiet() {
    var b = BadgeBatch()
    b.focusMoved(now: t0)
    b.add("a", now: at(0.25))
    // Focus moved at 0: the pass waits until 1 s of quiet (later than the 0.5 s coalesce window).
    #expect(b.flushAt == at(1))
    b.focusMoved(now: at(0.75))
    #expect(b.flushAt == at(1.75))
    #expect(b.take(now: at(1)) == nil)
    #expect(b.take(now: at(1.75))?.ids == ["a"])
}

@Test func badgeBatchHoldsAtMostMaxHold() {
    var b = BadgeBatch()
    b.add("a", now: t0)
    // The focus keeps moving: the values still arrive at the latest 3 s after the first one.
    b.focusMoved(now: at(2.5))
    #expect(b.flushAt == at(3))
    #expect(b.take(now: at(3)) == BadgeBatch.Flush(ids: ["a"], waited: 3))
}

@Test func badgeBatchFocusMoveWithoutPendingChangesNothingLater() {
    var b = BadgeBatch()
    b.focusMoved(now: t0)
    #expect(b.flushAt == nil)
    // An arrival long after the focus came to rest only waits the coalesce window.
    b.add("a", now: at(5))
    #expect(b.flushAt == at(5.5))
}

@Test func badgeBatchClearDropsPending() {
    var b = BadgeBatch()
    b.add("a", now: t0)
    b.clear()
    #expect(b.flushAt == nil)
    #expect(b.take(now: at(10)) == nil)
}

@Test func badgePassStatsLine() {
    var s = BadgePassStats()
    #expect(BadgePassStats.window == 10)
    #expect(s.take() == nil)
    #expect(s.record(BadgeBatch.Flush(ids: ["a", "b"], waited: 0.5)) == true)    // opens the window
    #expect(s.record(BadgeBatch.Flush(ids: ["c"], waited: 1.75)) == false)
    #expect(s.take() == "Plaketten gebündelt: 2 Durchgänge · 3 Titel · längstes Warten 1750 ms")
    #expect(s.take() == nil)
    #expect(s.record(BadgeBatch.Flush(ids: ["d"], waited: 0.5)) == true)
    #expect(s.take() == "Plaketten gebündelt: 1 Durchgang · 1 Titel · längstes Warten 500 ms")
}
