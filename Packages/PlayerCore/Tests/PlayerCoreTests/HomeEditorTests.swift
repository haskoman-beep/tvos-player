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
