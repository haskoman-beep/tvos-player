import Foundation
import Testing
@testable import PlayerCore

func threeRows() -> HomeLayout {
    HomeLayout(rows: [
        HomeRow(content: .list(.continueWatching), style: .landscape),
        HomeRow(content: .collection(id: "c1")),
        HomeRow(content: .list(.watchlist)),
    ])
}

@Test func moveBounds() {
    let l = threeRows()
    var e = HomeEditor(layout: l, grabbing: l.rows[0].id)
    e.moveUp()
    #expect(e.layout.rows[0].id == l.rows[0].id)
    e.moveDown(); e.moveDown(); e.moveDown()
    #expect(e.layout.rows[2].id == l.rows[0].id)
}

@Test func styleCyclesOnlyAllowed() {
    let l = threeRows()
    var e = HomeEditor(layout: l, grabbing: l.rows[1].id)
    e.nextStyle()
    #expect(e.layout.rows[1].style == .logoTiles)
    e.nextStyle()
    #expect(e.layout.rows[1].style == .collectionTiles)
    e.previousStyle()
    #expect(e.layout.rows[1].style == .logoTiles)
}

@Test func removeAndAdd() {
    let l = threeRows()
    var e = HomeEditor(layout: l, grabbing: l.rows[1].id)
    e.removeGrabbed()
    #expect(e.grabbed == nil && e.layout.rows.count == 2)
    let avail = e.availableToAdd(collections: [MediaCollection(id: "c1", title: "S", folders: [])], extraLists: [.watchlist])
    #expect(avail == [.collection(id: "c1")])
    let id = e.add(.collection(id: "c1"))
    #expect(e.layout.rows.last?.id == id && e.grabbed == id)
    #expect(e.layout.rows.last?.style == .collectionTiles)
}

@Test func cancelRestoresOriginal() {
    let l = threeRows()
    var e = HomeEditor(layout: l, grabbing: l.rows[0].id)
    e.moveDown(); e.nextStyle(); e.removeGrabbed(); e.add(.collection(id: "zz"))
    #expect(e.commit() != l)
    #expect(e.cancel() == l)
}

// MARK: Verwalter (Plan §2.5)

func numberedRows(_ n: Int) -> HomeLayout {
    HomeLayout(rows: (1...n).map { HomeRow(content: .collection(id: "c\($0)")) })
}

@Test func jumpToTopAndBottom() {
    let l = numberedRows(20)
    var e = HomeEditor(layout: l)
    let r20 = l.rows[19].id
    do { let r = e.moveToTop(r20); #expect(r == RowMove(from: 19, to: 0)) }
    #expect(e.layout.rows[0].id == r20 && e.layout.rows[1].id == l.rows[0].id && e.layout.rows.count == 20)
    do { let r = e.moveToTop(r20); #expect(r == nil) }          // schon oben
    do { let r = e.moveToBottom(r20); #expect(r == RowMove(from: 0, to: 19)) }
    #expect(e.layout == l)
    do { let r = e.moveToBottom(UUID()); #expect(r == nil) }     // unbekannt
}

@Test func moveToPositionClamps() {
    let l = numberedRows(5)
    var e = HomeEditor(layout: l)
    do { let r = e.move(l.rows[0].id, to: 2); #expect(r == RowMove(from: 0, to: 2)) }
    #expect(e.layout.rows.map(\.content.key) == ["collection:c2", "collection:c3", "collection:c1", "collection:c4", "collection:c5"])
    do { let r = e.move(l.rows[0].id, to: 99); #expect(r == RowMove(from: 2, to: 4)) }
    #expect(e.layout.rows.last?.id == l.rows[0].id)
    do { let r = e.move(l.rows[0].id, to: -3); #expect(r == RowMove(from: 4, to: 0)) }
    #expect(e.layout == l)
}

@Test func insertDefaultsToBottom() {
    let l = threeRows()
    var e = HomeEditor(layout: l)
    let id = e.insert(.collection(id: "neu"))
    #expect(e.layout.rows.count == 4 && e.layout.rows.last?.id == id)
    #expect(e.isNew(id) && e.grabbed == nil)
    let at1 = e.insert(.collection(id: "zwei"), at: 1, style: .logoTiles)
    #expect(e.layout.rows[1].id == at1 && e.layout.rows[1].style == .logoTiles)
    // Ungültiger Stil fällt auf den ersten erlaubten zurück, Position wird begrenzt.
    let far = e.insert(.list(.upcoming), at: 99, style: .logoTiles)
    #expect(e.layout.rows.last?.id == far && e.layout.rows.last?.style == .poster)
    // Doppelte werden nicht angelegt.
    do { let r = e.insert(.collection(id: "c1")); #expect(r == l.rows[1].id) }
    #expect(e.layout.rows.count == 6)
    #expect(e.added == [id, at1, far])
}

@Test func toggleAddsAtBottomThenRemoves() {
    let l = threeRows()
    var e = HomeEditor(layout: l)
    guard case .added(let id) = e.toggle(.collection(id: "x")) else { Issue.record("nicht hinzugefügt"); return }
    #expect(e.layout.rows.last?.id == id)
    do { let r = e.toggle(.collection(id: "x")); #expect(r == .removed(id)) }
    #expect(e.layout == l && e.added.isEmpty)
    // Vorhandene Reihe: Umschalten nimmt sie weg.
    do { let r = e.toggle(.list(.watchlist)); #expect(r == .removed(l.rows[2].id)) }
    #expect(e.layout.rows.count == 2)
    #expect(e.cancel() == l)
}

@Test func removeByIDClearsGrab() {
    let l = threeRows()
    var e = HomeEditor(layout: l, grabbing: l.rows[1].id)
    let first = e.remove(l.rows[1].id)
    #expect(first)
    #expect(e.grabbed == nil && e.layout.rows.count == 2)
    let second = e.remove(l.rows[1].id)
    #expect(!second)
}

@Test func layoutEditsWithoutEditor() {
    var l = numberedRows(3)
    let last = l.rows[2].id
    do { let r = l.moveToTop(last); #expect(r == RowMove(from: 2, to: 0)) }
    #expect(l.index(of: last) == 0)
    #expect(l.contains(.collection(id: "c2")) && !l.contains(.collection(id: "c9")))
    let id = l.insert(.collection(id: "c9"))
    #expect(l.rows.last?.id == id)
    let r1 = l.remove(id), r2 = l.remove(id)
    #expect(r1 && !r2)
    var empty = HomeLayout()
    do { let r = empty.move(UUID(), to: 0); #expect(r == nil) }
    do { let r = empty.moveToBottom(UUID()); #expect(r == nil) }
}
