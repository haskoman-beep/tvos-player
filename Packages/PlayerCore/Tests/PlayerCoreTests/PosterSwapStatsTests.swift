import Foundation
import Testing
@testable import PlayerCore

@Test func posterSwapStatsEmptyWindowLogsNothing() {
    var s = PosterSwapStats()
    let line = s.take()
    #expect(line == nil)
}

@Test func posterSwapStatsFirstSwapOpensWindow() {
    var s = PosterSwapStats()
    let first = s.record(gapMs: nil, waitMs: 120)
    let second = s.record(gapMs: nil, waitMs: 40)
    _ = s.take()
    let afterTake = s.record(gapMs: nil, waitMs: 10)
    #expect(first)
    #expect(!second)
    #expect(afterTake)
}

@Test func posterSwapStatsWithoutGapsSaysZero() {
    var s = PosterSwapStats()
    s.record(gapMs: nil, waitMs: 120)
    s.record(gapMs: nil, waitMs: 340)
    s.record(gapMs: nil, waitMs: 0)
    let line = s.take()
    #expect(line == "Kachelwechsel 3 · mit Lücke 0 · längste Lücke 0 ms · längstes Warten 340 ms")
}

@Test func posterSwapStatsCountsGapsAndLongest() {
    var s = PosterSwapStats()
    s.record(gapMs: 80, waitMs: 80)
    s.record(gapMs: nil, waitMs: 500)
    s.record(gapMs: 0, waitMs: 0)      // a gap, even if shorter than a millisecond
    s.record(gapMs: 230, waitMs: 230)
    let line = s.take()
    #expect(line == "Kachelwechsel 4 · mit Lücke 3 · längste Lücke 230 ms · längstes Warten 500 ms")
}

@Test func posterSwapStatsTakeResets() {
    var s = PosterSwapStats()
    s.record(gapMs: 90, waitMs: 90)
    _ = s.take()
    let empty = s.take()
    #expect(empty == nil)
    s.record(gapMs: nil, waitMs: 5)
    let line = s.take()
    #expect(line == "Kachelwechsel 1 · mit Lücke 0 · längste Lücke 0 ms · längstes Warten 5 ms")
}

@Test func posterSwapStatsNegativeValuesClampToZero() {
    var s = PosterSwapStats()
    s.record(gapMs: -4, waitMs: -9)
    let line = s.take()
    #expect(line == "Kachelwechsel 1 · mit Lücke 1 · längste Lücke 0 ms · längstes Warten 0 ms")
}

@Test func posterSwapStartNeedsAnotherShownAddress() {
    let none1 = PosterSwapStats.start(previous: nil, next: "b", pictureVisible: false)
    let none2 = PosterSwapStats.start(previous: "a", next: "a", pictureVisible: false)
    let none3 = PosterSwapStats.start(previous: nil, next: "b", pictureVisible: true)
    #expect(none1 == nil)
    #expect(none2 == nil)
    #expect(none3 == nil)
}

@Test func posterSwapStartIsGapOnlyWithoutVisiblePicture() {
    let covered = PosterSwapStats.start(previous: "a", next: "b", pictureVisible: true)
    let gap = PosterSwapStats.start(previous: "a", next: "b", pictureVisible: false)
    #expect(covered == .covered)
    #expect(gap == .gap)
}
