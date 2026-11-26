import Foundation
import Testing
@testable import PlayerCore

// Build 5 (b5r): the home backdrop follows the focus only after a longer rest, and never while the user keeps
// pressing in a rhythm (device test 2: a swap every 1–1.5 s while pressing right, each one with crossfade and a hero
// info reload, missed frames mostly at "Hintergrund").

@Test func firstMoveRestsTheBaseTime() {
    var r = BackdropRest()
    #expect(r.moved(at: 10) == BackdropRest.baseMilliseconds)
    #expect(BackdropRest.baseMilliseconds == 800)
    #expect(!r.inBurst)
}

@Test func quickPressesKeepTheBaseRest() {
    var r = BackdropRest()
    _ = r.moved(at: 10)
    // 300 ms apart: 300 + margin is below the base, the base wins.
    #expect(r.moved(at: 10.3) == 800)
    #expect(r.inBurst)
}

@Test func rhythmicPressesRestLongerThanTheirRhythm() {
    var r = BackdropRest()
    _ = r.moved(at: 10)
    // Pressing every 1.2 s: the rest is longer than the rhythm, so no swap lands between two presses.
    #expect(r.moved(at: 11.2) == 1200 + BackdropRest.marginMilliseconds)
    #expect(r.moved(at: 12.4) == 1500)
}

@Test func burstRestUsesTheLongestRecentGapAndIsCapped() {
    var r = BackdropRest()
    _ = r.moved(at: 0)
    _ = r.moved(at: 1.0)    // gap 1000
    #expect(r.moved(at: 1.4) == 1300)   // gap 400, longest recent 1000 → 1300
    #expect(r.moved(at: 1.8) == 1300)   // still within the last three gaps
    #expect(r.moved(at: 2.2) == 800)    // the 1000 ms gap fell out of the last three
    // Never above the cap.
    var c = BackdropRest()
    _ = c.moved(at: 0)
    #expect(c.moved(at: 1.45) == BackdropRest.maxMilliseconds)
}

@Test func longPauseEndsTheBurst() {
    var r = BackdropRest()
    _ = r.moved(at: 0)
    _ = r.moved(at: 1.2)
    // 2 s without a move: the user looked; the next move starts fresh.
    #expect(r.moved(at: 3.2) == 800)
    #expect(!r.inBurst)
}

@Test func resetStartsFreshAndClockGoingBackIsNoBurst() {
    var r = BackdropRest()
    _ = r.moved(at: 0)
    _ = r.moved(at: 1.2)
    r.reset()
    #expect(r.moved(at: 1.3) == 800)
    #expect(!r.inBurst)
    #expect(r.moved(at: 0.5) == 800)
}

@Test func swapCountsTheMovesItSkipped() {
    var r = BackdropRest()
    _ = r.moved(at: 0)
    _ = r.moved(at: 0.4)
    _ = r.moved(at: 0.8)
    // The backdrop swapped after the third move: two moves before it never got a swap.
    #expect(r.swapped() == 2)
    _ = r.moved(at: 3)
    #expect(r.swapped() == 0)
}

@Test func homeStopPrefetchesAfterTheRestAndTheCrossfade() {
    // Base rest: backdrop after 800 ms, prefetch after the 600 ms crossfade (1400 ms after the stop).
    #expect(FocusRest.stop(alreadyShown: false, backdropRest: 800, fadeMilliseconds: 600)
            == FocusRest.Stop(backdropWait: 800, prefetchWait: 600))
    // A short rest keeps the 1 s prefetch rest in all.
    #expect(FocusRest.stop(alreadyShown: false, backdropRest: 300, fadeMilliseconds: 600)
            == FocusRest.Stop(backdropWait: 300, prefetchWait: 700))
    // Shown already: no swap, the full prefetch rest as before.
    #expect(FocusRest.stop(alreadyShown: true, backdropRest: 1500, fadeMilliseconds: 600)
            == FocusRest.Stop(backdropWait: nil, prefetchWait: 1000))
}
