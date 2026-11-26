import Foundation
import Testing
@testable import PlayerCore

// Build 4 follow-up 2 (P3): the source prefetch waits for a longer focus rest than the backdrop, and the visible-tile
// prefetch waits until the focus has been quiet as long, so source searches (and the stored lists, badge passes and
// re-renders after them) no longer land in the backdrop crossfade or while the focus moves on.

private let t0 = Date(timeIntervalSince1970: 1_000_000)
private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

@Test func prefetchRestIsLongerThanTheBackdropRestAndItsCrossfade() {
    #expect(FocusRest.prefetchMilliseconds == 1000)
    #expect(FocusRest.prefetchQuiet == 1.0)
    // b5r: the home stop starts the prefetch after the backdrop rest plus its crossfade (800 + 600 ms).
    let fresh = FocusRest.stop(alreadyShown: false, backdropRest: BackdropRest.baseMilliseconds)
    #expect((fresh.backdropWait ?? 0) + fresh.prefetchWait >= BackdropRest.baseMilliseconds + BackdropRest.fadeMilliseconds)
}

@Test func focusStopOnTheShownTileKeepsTheFullPrefetchRest() {
    // Back on the tile whose backdrop is shown (focus moved away and back before the prefetch): no swap, but the
    // prefetch still gets its full rest.
    let shown = FocusRest.stop(alreadyShown: true, backdropRest: BackdropRest.baseMilliseconds)
    #expect(shown == FocusRest.Stop(backdropWait: nil, prefetchWait: 1000))
}

@Test func visiblePrefetchWaitsForFocusQuiet() {
    var p = VisiblePrefetchPlan()
    _ = p.setTile("a", row: "A", visible: true, now: t0)
    _ = p.setTile("b", row: "A", visible: true, now: t0)
    // Focus moves within the visible tiles (no tile change): the pass waits 1 s after the last move.
    p.focusMoved(now: at(0.25))
    #expect(p.dueAt == at(1.25))
    #expect(p.pass(now: at(0.75)) { _ in .needed }.isEmpty)
    p.focusMoved(now: at(0.75))
    #expect(p.pass(now: at(1.5)) { _ in .needed }.isEmpty)
    #expect(p.pass(now: at(1.75)) { _ in .needed } == ["a", "b"])
}

@Test func visiblePrefetchTileDebounceStillAppliesAfterFocusQuiet() {
    var p = VisiblePrefetchPlan()
    p.focusMoved(now: t0)
    _ = p.setTile("a", row: "A", visible: true, now: at(0.75))
    // Tile change at 0.75 s: its 0.4 s debounce ends after the focus quiet (1.0 s).
    #expect(p.dueAt == at(0.75).addingTimeInterval(0.4))
    #expect(p.pass(now: at(1.1)) { _ in .needed }.isEmpty)
    #expect(p.pass(now: at(1.25)) { _ in .needed } == ["a"])
}

@Test func visiblePrefetchNextPassAtCoversAnEarlyPass() {
    var p = VisiblePrefetchPlan()
    _ = p.setTile("a", row: "A", visible: true, now: t0)
    p.focusMoved(now: at(0.25))
    // A pass that runs before the focus quiet ended starts nothing; the app must look again at the due time.
    #expect(p.pass(now: at(0.5)) { _ in .needed }.isEmpty)
    #expect(p.nextPassAt(now: at(0.5)) == at(1.25))
    #expect(p.pass(now: at(1.25)) { _ in .needed } == ["a"])
    // Due time passed and nothing waits: no further pass.
    #expect(p.nextPassAt(now: at(1.5)) == nil)
}

@Test func visiblePrefetchNextPassAtFallsBackToTheBudget() {
    let limits = VisiblePrefetchPlan.Limits(maxRunning: 10)
    var p = VisiblePrefetchPlan(limits: limits, budget: PrefetchBudget(perMinute: 1, focusReserve: 0))
    _ = p.setTile("a", row: "A", visible: true, now: t0)
    _ = p.setTile("b", row: "A", visible: true, now: t0)
    #expect(p.pass(now: at(1)) { _ in .needed } == ["a"])
    p.finished("a", outcome: .loaded, now: at(2))
    #expect(p.pass(now: at(2)) { _ in .needed }.isEmpty)
    #expect(p.nextPassAt(now: at(2)) == at(61))           // same as nextStartAt once the debounce is over
}
