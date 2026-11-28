import Testing
import Foundation
@testable import PlayerCore

// Phase 0a.1 device test (28.11.): stale row frames after a reorder, and the row jump diagnosis.

private let rows = (0..<11).map { _ in UUID() }

@Test func unchangedOrderKeepsEveryFrame() {
    #expect(HomeRowJump.keptFrames(old: rows, new: rows) == Set(rows))
}

// 09:33:08.663 "Reihe verschoben 5→8: Preise": rows 1–4 and 9–11 keep their place, 5–8 moved.
@Test func aReorderDropsTheFramesBetweenTheChangedIndices() {
    var moved = rows
    let preise = moved.remove(at: 4)
    moved.insert(preise, at: 7)
    let kept = HomeRowJump.keptFrames(old: rows, new: moved)
    #expect(kept == Set(rows[0..<4]).union(rows[8...]))
    #expect(!kept.contains(preise))
    #expect(!kept.contains(rows[6]))   // Genres: one row up
}

// A hidden or deleted row moves every row after it; an added row likewise.
@Test func aRemovedOrAddedRowDropsEveryFrameAfterIt() {
    var hidden = rows
    hidden.remove(at: 3)
    #expect(HomeRowJump.keptFrames(old: rows, new: hidden) == Set(rows[0..<3]))
    let added = rows + [UUID()]
    #expect(HomeRowJump.keptFrames(old: rows, new: added) == Set(rows))
    let addedFront = [UUID()] + rows
    #expect(HomeRowJump.keptFrames(old: rows, new: addedFront).isEmpty)
}

@Test func movingTheLastRowToTheTopDropsEveryFrame() {
    let moved = [rows[10]] + rows[0..<10]
    #expect(HomeRowJump.keptFrames(old: rows, new: moved).isEmpty)
}

@Test func skippedRowsLieBetweenTheEnds() {
    #expect(HomeRowJump.skipped(from: rows[2], to: rows[5], order: rows) == [rows[3], rows[4]])
    #expect(HomeRowJump.skipped(from: rows[5], to: rows[2], order: rows) == [rows[3], rows[4]])
    #expect(HomeRowJump.skipped(from: rows[2], to: rows[3], order: rows).isEmpty)
    #expect(HomeRowJump.skipped(from: rows[2], to: rows[2], order: rows).isEmpty)
    #expect(HomeRowJump.skipped(from: UUID(), to: rows[5], order: rows).isEmpty)
}

@Test func aReportCountsFromShortlyBeforeTheUIKitUpdate() {
    #expect(HomeRowJump.reported(enteredAt: 10, lastReport: 10.1))
    #expect(HomeRowJump.reported(enteredAt: 10, lastReport: 9.9))
    #expect(!HomeRowJump.reported(enteredAt: 10, lastReport: 9.5))
    #expect(!HomeRowJump.reported(enteredAt: 10, lastReport: nil))
}

@Test func jumpLineNamesTheSkippedRowsAndTheScroll() {
    let line = HomeRowJump.jumpLine(from: "Trending", to: "Genres", down: true,
                                    skipped: [.init(title: "In Theaters", span: HomeRowSpan(minY: 2248, maxY: 2874)),
                                              .init(title: "Studios", span: nil)],
                                    offset: 1701.6, flightTarget: 1557, sinceLastMs: 142)
    #expect(line == "Fokus sprang über Reihen (UIKit): Trending → Genres · runter · übersprungen 2: "
            + "In Theaters 2248…2874, Studios ohne Rahmen · Versatz 1702 · Scrollziel 1557 · 142 ms nach dem letzten Schritt")
    let bare = HomeRowJump.jumpLine(from: "Trending", to: "Weiterschauen", down: false,
                                    skipped: [.init(title: "For You", span: nil)], offset: nil, flightTarget: nil,
                                    sinceLastMs: nil)
    #expect(bare == "Fokus sprang über Reihen (UIKit): Trending → Weiterschauen · hoch · übersprungen 1: For You ohne Rahmen")
}

@Test func unreportedLineNamesWhereTheFocusIsNow() {
    #expect(HomeRowJump.unreportedLine(title: "In Theaters", now: "Studios")
            == "Reihe In Theaters hatte den Fokus (UIKit), meldete ihn nicht binnen 250 ms · jetzt in Studios")
    #expect(HomeRowJump.unreportedLine(title: "Genres", now: nil)
            == "Reihe Genres hatte den Fokus (UIKit), meldete ihn nicht binnen 250 ms · jetzt in keiner Reihe")
}
