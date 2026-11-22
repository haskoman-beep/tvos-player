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

@Test func readyPackagesCarryArtwork() {
    let netflix = ReadyPackages.streamingDE.folders.first { $0.title == "Netflix" }
    #expect(netflix?.coverImage?.hasSuffix("streaming_services.netflix.webp?v=7") == true)
    #expect(netflix?.focusGif?.hasSuffix("streaming_services.netflix.focus.gif?v=7") == true)
    #expect(netflix?.logo != nil)
    #expect(netflix?.hideTitle == true)
    // Ohne Bild beim Server: Titel bleibt sichtbar, kein GIF.
    let joyn = ReadyPackages.streamingDE.folders.first { $0.title == "Joyn" }
    #expect(joyn?.coverImage == nil && joyn?.focusGif == nil)
    // Alle Genres haben ein Standbild, keins ein GIF.
    let genres = ReadyPackages.genreCollection.folders
    #expect(genres.count == ReadyPackages.genres.count)
    #expect(genres.allSatisfy { $0.coverImage != nil && $0.focusGif == nil })
    #expect(genres.first { $0.title == "Komödie" }?.coverImage?.contains("genres.comedy.") == true)
}

@Test func storedPackageCopyGetsArtworkOnRead() {
    // Profil-Kopie aus der Zeit vor F-g: Kacheln ohne Bilder.
    var old = ReadyPackages.streamingDE
    old.folders = old.folders.map { var f = $0; f.coverImage = nil; f.logo = nil; f.focusGif = nil; f.hideTitle = nil; return f }
    let filled = ReadyPackages.withArtwork(old)
    #expect(filled == ReadyPackages.streamingDE)
    // Eigenes Bild des Nutzers bleibt.
    var own = old
    own.folders[0].coverImage = "https://example.invalid/own.png"
    let kept = ReadyPackages.withArtwork(own)
    #expect(kept.folders[0].coverImage == "https://example.invalid/own.png")
    #expect(kept.folders[0].focusGif != nil)
    // Fremde Collections bleiben unverändert.
    let other = MediaCollection(id: "x", title: "X", folders: [Folder(id: "x.1", title: "1", sources: [])])
    #expect(ReadyPackages.withArtwork(other) == other)
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
