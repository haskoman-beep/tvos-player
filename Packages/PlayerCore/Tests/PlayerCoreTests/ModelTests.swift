import Foundation
import Testing
@testable import PlayerCore

@Test func profileRoundTrip() throws {
    var p = Profile.makeDefault()
    let src = CatalogSource(id: "s1", title: "Neu", kind: .tmdbDiscover(filters: ["with_watch_providers": "8|1796"]), mediaType: .movie)
    p.collections = [MediaCollection(id: "c1", title: "Streaming", folders: [Folder(id: "f1", title: "Netflix", sources: [src])])]
    p.home.rows.append(HomeRow(content: .collection(id: "c1")))
    let back = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(p))
    #expect(back == p)
}

@Test func defaultProfileValues() {
    let p = Profile.makeDefault()
    #expect(p.audioPriority == ["de", "en", "orig"])
    #expect(p.subtitleMode == .forcedOnly)
    #expect(p.progressSource == .local)
    #expect(p.home.rows.count == 1)
}

@Test func allowedStyles() {
    let list = RowContent.list(.watchlist)
    #expect(!list.allowedStyles.contains(.collectionTiles))
    #expect(RowContent.collection(id: "x").allowedStyles == [.collectionTiles, .logoTiles])
    #expect(HomeRow(content: .collection(id: "x"), style: .hero).style == .collectionTiles)
}
