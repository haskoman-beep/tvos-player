import Foundation
import Testing
@testable import PlayerCore

// MARK: Home row heading snap (Build 4 follow-up S5: row sits too low on first entry)

@Test func listScrollFromGeometryMeasuresFromTheVeryTop() {
    // contentOffset.y − (−inset.top) = distance from the very top; the end leaves the bottom inset visible.
    let s = HomeListScroll(contentOffsetY: 788, contentHeight: 3000, insetTop: 24, insetBottom: 60, viewportHeight: 600)
    #expect(s.offset == 812)
    #expect(s.maxOffset == 2484)
    // Content shorter than the list: nothing to scroll.
    let short = HomeListScroll(contentOffsetY: 0, contentHeight: 300, insetTop: 0, insetBottom: 60, viewportHeight: 600)
    #expect(short.maxOffset == 0)
}

@Test func rowAtListTopIsInPlaceWithinTolerance() {
    let scroll = HomeListScroll(offset: 812, maxOffset: 2400)
    #expect(HeadingSnap.decide(row: HomeRowSpan(minY: 812, maxY: 1290), scroll: scroll) == .inPlace)
    #expect(HeadingSnap.decide(row: HomeRowSpan(minY: 814, maxY: 1292), scroll: scroll) == .inPlace)
    #expect(HeadingSnap.decide(row: HomeRowSpan(minY: 810, maxY: 1288), scroll: scroll) == .inPlace)
    #expect(HeadingSnap.decide(row: HomeRowSpan(minY: 815, maxY: 1293), scroll: scroll) == .snap(deviation: 3))
}

@Test func rowTooLowOrTooHighSnaps() {
    let scroll = HomeListScroll(offset: 812, maxOffset: 2400)
    // Build 4 device test: the whole row sat lower, its bottom cut at the list edge.
    #expect(HeadingSnap.decide(row: HomeRowSpan(minY: 850, maxY: 1330), scroll: scroll) == .snap(deviation: 38))
    #expect(HeadingSnap.decide(row: HomeRowSpan(minY: 700, maxY: 1180), scroll: scroll) == .snap(deviation: -112))
}

@Test func rowNearContentEndIsInPlaceAtTheLargestOffset() {
    // The last rows cannot reach the top edge: the list stops at its end, a snap would not move anything.
    let row = HomeRowSpan(minY: 2600, maxY: 3000)
    #expect(HeadingSnap.decide(row: row, scroll: HomeListScroll(offset: 2400, maxOffset: 2400)) == .inPlace)
    #expect(HeadingSnap.decide(row: row, scroll: HomeListScroll(offset: 2399, maxOffset: 2400)) == .inPlace)
    #expect(HeadingSnap.decide(row: row, scroll: HomeListScroll(offset: 2300, maxOffset: 2400)) == .snap(deviation: 300))
}

@Test func unknownGeometrySnapsOnlyAtTheFirstCheck() {
    let scroll = HomeListScroll(offset: 812, maxOffset: 2400)
    #expect(HeadingSnap.decide(row: nil, scroll: scroll) == .unknown)
    #expect(HeadingSnap.decide(row: HomeRowSpan(minY: 812, maxY: 1290), scroll: nil) == .unknown)
    // Without a measurement the Build 3 behaviour stays: one blind snap at the first check.
    #expect(HeadingSnap.shouldSnap(.unknown, check: 0))
    #expect(!HeadingSnap.shouldSnap(.unknown, check: 1))
    #expect(!HeadingSnap.shouldSnap(.unknown, check: 2))
    #expect(!HeadingSnap.shouldSnap(.inPlace, check: 0))
    #expect(HeadingSnap.shouldSnap(.snap(deviation: 38), check: 0))
    #expect(HeadingSnap.shouldSnap(.snap(deviation: 38), check: 2))
}

@Test func checksAreBoundedAndEndAfterOneAndAHalfSeconds() {
    #expect(HeadingSnap.checksMs == [400, 900, 1500])
    #expect(HeadingSnap.checksMs == HeadingSnap.checksMs.sorted())
    #expect(HeadingSnap.afterSnapMs < HeadingSnap.checksMs[1] - HeadingSnap.checksMs[0])
}

@Test func headingSnapLogLines() {
    let list = HeadingSnapSample.ListView(offsetY: 788, maxOffsetY: 2460, frameMinY: 470, frameMaxY: 1080,
                                          insetTop: 24, insetBottom: 60, safeTop: 60)
    let before = HeadingSnapSample(row: HomeRowSpan(minY: 850.4, maxY: 1330), scroll: HomeListScroll(offset: 812, maxOffset: 2484),
                                   list: list)
    var after = before
    after.scroll = HomeListScroll(offset: 850, maxOffset: 2484)
    after.list?.offsetY = 826
    // P2 (follow-up 2): `unten` = room between the row's bottom and the list's visible bottom (frame − bottom inset).
    #expect(HeadingSnap.snapLine(title: "Trends", ms: 900, before: before, after: after)
        == "Reihe Trends nach 0,9 s nachgerastet: vorher y 788/max 2460 · Reihe 850…1330 (Abstand +38, unten +8)"
        + " · Liste 470…1080 · Inset 24/60 · Safe 60 · nach Rasten y 826/max 2460 · Reihe 850…1330 (Abstand 0, unten +46)"
        + " · Liste 470…1080 · Inset 24/60 · Safe 60")
    #expect(HeadingSnap.checkLine(title: "Trends", ms: 1500, decision: .inPlace, sample: after)
        == "Reihe Trends nach 1,5 s: an der Oberkante · y 826/max 2460 · Reihe 850…1330 (Abstand 0, unten +46)"
        + " · Liste 470…1080 · Inset 24/60 · Safe 60")
    // Without the list view the bottom is unknown: only the distance.
    let noList = HeadingSnapSample(row: HomeRowSpan(minY: 850, maxY: 1330), scroll: HomeListScroll(offset: 850, maxOffset: 2484),
                                   list: nil)
    #expect(HeadingSnap.checkLine(title: "Trends", ms: 1500, decision: .inPlace, sample: noList)
        == "Reihe Trends nach 1,5 s: an der Oberkante · keine Liste · Reihe 850…1330 (Abstand 0)")
    let unknown = HeadingSnapSample(row: nil, scroll: nil, list: nil)
    #expect(HeadingSnap.checkLine(title: "Trends", ms: 1500, decision: .unknown, sample: unknown)
        == "Reihe Trends nach 1,5 s: Lage unbekannt · keine Liste · Reihe ?")
}

@Test func rowBottomAgainstTheListBottomMatchesTheDeviceLog() {
    // Device log 25.11.: heading at the top edge, but the 580-pt row ends 171 pt below the list's visible bottom.
    let list = HeadingSnapSample.ListView(offsetY: 1284, maxOffsetY: 4918, frameMinY: 627, frameMaxY: 1080,
                                          insetTop: 0, insetBottom: 45, safeTop: 157)
    let cut = HeadingSnapSample(row: HomeRowSpan(minY: 1283, maxY: 1863), scroll: HomeListScroll(offset: 1284, maxOffset: 4918),
                                list: list)
    #expect(HeadingSnap.bottomRoom(cut) == -171)
    // Collapsed info (list from 455): the same row fits.
    var fits = cut
    fits.list?.frameMinY = 455
    #expect(HeadingSnap.bottomRoom(fits) == 1)
    #expect(HeadingSnap.bottomRoom(HeadingSnapSample(row: cut.row, scroll: cut.scroll, list: nil)) == nil)
}

@Test func handoverLogLine() {
    #expect(HeadingSnap.handoverLine(title: "Neu", placeholder: 2, card: 2) == "Reihe Neu: Platzhalter 2 → Karte 2")
    #expect(HeadingSnap.handoverLine(title: "Neu", placeholder: 0, card: nil) == "Reihe Neu: Platzhalter 0 → Statuskachel")
    #expect(HeadingSnap.handoverSkippedLine(title: "Neu") == "Reihe Neu: Übergabe entfällt, Fokus nicht mehr in der Reihe")
}
