import Testing
import Foundation
@testable import PlayerCore

// Welle F-g: Collection-Reihen (Phase, Bilder-Zählung), Paket-Bilder, GIF-Ausdünnung, Fokus-GIF im Nuvio-Import.

private func src(_ id: String) -> CatalogSource {
    CatalogSource(id: id, title: id, kind: .tmdbDiscover(filters: [:]), mediaType: .movie)
}

@Test func collectionPhaseTilesAndEmpty() {
    let f = [Folder(id: "a", title: "A", sources: [src("a")])]
    #expect(CollectionRowPhase.of(collectionID: "pkg.genres", folders: f) == .tiles)
    #expect(CollectionRowPhase.of(collectionID: "pkg.genres", folders: []) == .empty)
    // Eigene Collection, die es nicht mehr gibt: keine ewigen Platzhalter.
    #expect(CollectionRowPhase.of(collectionID: "own.1", folders: nil) == .empty)
}

@Test func kitCollectionLoadingThenFailed() {
    let id = "fusion.widgets-genres.collection"
    #expect(CollectionRowPhase.of(collectionID: id, folders: nil) == .loading)
    let failed = CollectionRowPhase.of(collectionID: id, folders: nil, kitErrors: ["widgets-genres": "offline"])
    #expect(failed == .failed(sourceKey: "widgets-genres"))
    #expect(failed.statusText == "Laden fehlgeschlagen – erneut versuchen")
    // Erneuter Versuch läuft: wieder Platzhalter, auch wenn der alte Fehler noch steht.
    let retrying = CollectionRowPhase.of(collectionID: id, folders: nil, kitErrors: ["widgets-genres": "offline"],
                                         kitLoading: ["widgets-genres"])
    #expect(retrying == .loading)
    #expect(retrying.statusText == nil)
    // Fehler einer anderen Datei betrifft diese Reihe nicht.
    #expect(CollectionRowPhase.of(collectionID: id, folders: nil, kitErrors: ["andere": "x"]) == .loading)
}

@Test func artStatsCountImagesAndGifs() {
    let folders = [
        Folder(id: "1", title: "1", coverImage: "c", logo: "l", sources: [], focusGif: "g"),
        Folder(id: "2", title: "2", backdrop: "b", sources: []),
        Folder(id: "3", title: "3", sources: []),
    ]
    let tiles = CollectionArtStats(folders: folders, logoStyle: false)
    #expect(tiles == CollectionArtStats(folders: folders, logoStyle: false))
    #expect(tiles.tiles == 3 && tiles.images == 2 && tiles.gifs == 1)
    #expect(tiles.logLine(title: "Genres") == "Collection Genres: 3 Kacheln, Bilder 2, GIF 1")
    let logos = CollectionArtStats(folders: folders, logoStyle: true)
    #expect(logos.images == 1 && logos.gifs == 0)
}

@Test func readyPackagesShipNoRemoteImages() {
    let all = ReadyPackages.all.flatMap(\.folders)
    #expect(all.allSatisfy { $0.coverImage == nil && $0.logo == nil && $0.focusGif == nil && $0.backdrop == nil })
    // Jede Paket-Kachel hat eine eigene Gestaltung (Symbol + Farbverlauf).
    for f in all {
        let style = ReadyPackages.tileStyle(forFolderID: f.id)
        #expect(style != nil, "\(f.id)")
        #expect((0..<ReadyPackages.toneCount).contains(style?.tone ?? -1))
    }
    #expect(ReadyPackages.tileStyle(forFolderID: "pkg.genres.Drama")?.symbol == "theatermasks")
    #expect(ReadyPackages.tileStyle(forFolderID: "pkg.streaming-de.8")?.symbol == "play.tv")
    #expect(ReadyPackages.tileStyle(forFolderID: "pkg.genres.Unbekannt") == nil)
    #expect(ReadyPackages.tileStyle(forFolderID: "own.1") == nil)
}

private func discover(_ id: String, _ filters: [String: String]) -> CatalogSource {
    CatalogSource(id: id, title: id, kind: .tmdbDiscover(filters: filters), mediaType: .movie)
}

@Test func packageTilesTakeArtFromUserImportOnly() {
    let imported = MediaCollection(id: "nuvio.c", title: "Streaming", folders: [
        Folder(id: "i1", title: "N", coverImage: "https://example.com/n.webp", logo: "https://example.com/n-logo.webp",
               sources: [discover("s1", ["with_watch_providers": "8", "watch_region": "DE"])],
               focusGif: "https://example.com/n.gif"),
        // Mehrere Anbieter in einem Filter: keine eindeutige Kachel, kein Treffer.
        Folder(id: "i2", title: "Mix", coverImage: "https://example.com/mix.webp",
               sources: [discover("s2", ["with_watch_providers": "9|337"])]),
        Folder(id: "i3", title: "Komödie", coverImage: "https://example.com/comedy.webp",
               sources: [discover("s3", ["with_genres": "35"])]),
    ])
    let streaming = ReadyPackages.withImportedArt(ReadyPackages.streamingDE, imported: [imported])
    let netflix = streaming.folders.first { $0.id == "pkg.streaming-de.8" }
    #expect(netflix?.coverImage == "https://example.com/n.webp")
    #expect(netflix?.logo == "https://example.com/n-logo.webp")
    #expect(netflix?.focusGif == "https://example.com/n.gif")
    #expect(streaming.folders.first { $0.id == "pkg.streaming-de.9" }?.coverImage == nil)
    let genres = ReadyPackages.withImportedArt(ReadyPackages.genreCollection, imported: [imported])
    #expect(genres.folders.first { $0.title == "Komödie" }?.coverImage == "https://example.com/comedy.webp")
    #expect(genres.folders.first { $0.title == "Drama" }?.coverImage == nil)
    // Ohne Import: unverändert.
    let none = ReadyPackages.withImportedArt(ReadyPackages.streamingDE, imported: [])
    #expect(none == ReadyPackages.streamingDE)
    // Eigenes Standbild bleibt, und dann kommen auch Logo und GIF nicht dazu.
    var own = ReadyPackages.streamingDE
    own.folders[0].coverImage = "https://example.com/own.png"
    let kept = ReadyPackages.withImportedArt(own, imported: [imported])
    #expect(kept.folders[0].coverImage == "https://example.com/own.png")
    #expect(kept.folders[0].focusGif == nil && kept.folders[0].logo == nil)
    // Fremde Collections bleiben unverändert.
    #expect(ReadyPackages.withImportedArt(imported, imported: [imported]) == imported)
}

@Test func oldFolderJSONDecodesWithoutFocusGif() throws {
    let json = #"{"id":"a","title":"A","sources":[]}"#
    let f = try JSONDecoder().decode(Folder.self, from: Data(json.utf8))
    #expect(f.focusGif == nil)
}

@Test func gifFramePlanThinsEvenly() {
    #expect(GIFFramePlan.indices(frameCount: 0) == [])
    #expect(GIFFramePlan.indices(frameCount: 5, maxFrames: 48) == [0, 1, 2, 3, 4])
    let ninety = GIFFramePlan.indices(frameCount: 90, maxFrames: 48)
    #expect(ninety.count == 48)
    #expect(ninety.first == 0 && ninety.last! < 90)
    #expect(ninety == ninety.sorted() && Set(ninety).count == 48)
    #expect(GIFFramePlan.delay(nil) == 0.1)
    #expect(GIFFramePlan.delay(0.01) == 0.1)
    #expect(GIFFramePlan.delay(0.02) == 0.02)
    #expect(GIFFramePlan.delay(0.06) == 0.06)
    #expect(abs(GIFFramePlan.duration(delays: [0.05, nil, 0.0]) - 0.25) < 1e-9)
}

@Test func nuvioImportKeepsFocusGif() throws {
    let json = #"""
    [{"id":"c","title":"Streaming","folders":[
      {"id":"f1","title":"N","coverImageUrl":"c1","focusGifUrl":"g1","focusGifEnabled":true,
       "sources":[{"provider":"tmdb","tmdbSourceType":"DISCOVER","mediaType":"MOVIE","title":"N"}]},
      {"id":"f2","title":"P","coverImageUrl":"c2","focusGifUrl":"g2","focusGifEnabled":false,
       "sources":[{"provider":"tmdb","tmdbSourceType":"DISCOVER","mediaType":"MOVIE","title":"P"}]}]}]
    """#
    let r = try NuvioImport.parse(Data(json.utf8))
    let folders = r.collections.first?.folders ?? []
    #expect(folders.first { $0.id == "f1" }?.focusGif == "g1")
    #expect(folders.first { $0.id == "f2" }?.focusGif == nil)
}

@Test func packageArtMemoRecomputesOnlyAfterStampChange() {
    let imported = MediaCollection(id: "nuvio.c", title: "Streaming", folders: [
        Folder(id: "i1", title: "N", coverImage: "https://example.com/n.webp",
               sources: [CatalogSource(id: "s1", title: "s1", kind: .tmdbDiscover(filters: ["with_watch_providers": "8"]), mediaType: .movie)]),
    ])
    var memo = PackageArtMemo()
    var calls = 0
    let s1 = PackageArtMemo.Stamp(profile: 1, kit: 1)
    let a = memo.collection(ReadyPackages.streamingDE, stamp: s1) { calls += 1; return [imported] }
    let b = memo.collection(ReadyPackages.streamingDE, stamp: s1) { calls += 1; return [] }
    #expect(calls == 1)
    #expect(a == b)
    #expect(a.folders.first { $0.id == "pkg.streaming-de.8" }?.coverImage == "https://example.com/n.webp")
    // Kit-Stand geändert (Import weg): neu berechnet, Symbol-Kachel ohne Bild.
    let c = memo.collection(ReadyPackages.streamingDE, stamp: PackageArtMemo.Stamp(profile: 1, kit: 2)) { calls += 1; return [] }
    #expect(calls == 2)
    #expect(c.folders.first { $0.id == "pkg.streaming-de.8" }?.coverImage == nil)
}
