import Testing
import Foundation
@testable import PlayerCore

// Welle F-l: Bilder der fertigen Pakete aus Nutzer-Importen und Kit-Dateien (Zuordnung, Vorrang, GIF, Logzeile).

private func tile(_ title: String, _ cover: String?, gif: String? = nil, logo: String? = nil) -> Folder {
    Folder(id: "t.\(title)", title: title, coverImage: cover, logo: logo,
           sources: [CatalogSource(id: "s.\(title)", title: title, kind: .trakt(user: "u", list: title.lowercased()), mediaType: .movie)],
           focusGif: gif)
}

private func art(_ c: MediaCollection, _ id: String) -> Folder? { c.folders.first { $0.id == id } }

@Test func artNamesNormalize() {
    #expect(ReadyPackages.normalizedArtName("Disney+") == "disneyplus")
    #expect(ReadyPackages.normalizedArtName("Apple TV+") == "appletvplus")
    #expect(ReadyPackages.normalizedArtName("Komödie") == "komodie")
    #expect(ReadyPackages.normalizedArtName("Sci-Fi") == "scifi")
    #expect(ReadyPackages.normalizedArtName("Science-Fiction") == "sciencefiction")
    #expect(ReadyPackages.normalizedArtName("  Prime Video ") == "primevideo")
    #expect(ReadyPackages.normalizedArtName("Action & Abenteuer") == "actionandabenteuer")
    #expect(ReadyPackages.normalizedArtName("…") == "")
    #expect(ReadyPackages.artNames(forFolderID: "pkg.streaming-de.337") == ["disneyplus", "disney"])
    #expect(ReadyPackages.artNames(forFolderID: "pkg.genres.Krimi") == ["krimi", "crime", "krimis"])
    #expect(ReadyPackages.artNames(forFolderID: "pkg.genres.Unbekannt") == nil)
    #expect(ReadyPackages.artNames(forFolderID: "own.1") == nil)
}

@Test func streamingTilesMatchKitNamesAndVariants() {
    // Kit-Kacheln: Titel ohne Leerzeichen, Farbvarianten, Listen über Trakt (kein TMDB-Filter).
    let kit = PackageArtSource(id: "fusion.k.s", folders: [
        tile("Netflixdark", "https://example.com/netflix-dark.jpg"),
        tile("Netflixred", "https://example.com/netflix-red.jpg"),
        tile("Primevideo", "https://example.com/prime.jpg"),
        tile("Disney", "https://example.com/disney.jpg"),
        tile("Appletv", "https://example.com/appletv.jpg"),
        tile("Paramount", "https://example.com/paramount.jpg"),
        tile("Hulu", "https://example.com/hulu.jpg"),
        tile("Joyn", nil),   // ohne Standbild: kein Treffer
    ], origin: .kit)
    let out = ReadyPackages.withArt(ReadyPackages.streamingDE, sources: [kit])
    #expect(art(out, "pkg.streaming-de.8")?.coverImage == "https://example.com/netflix-red.jpg")
    #expect(art(out, "pkg.streaming-de.9")?.coverImage == "https://example.com/prime.jpg")
    #expect(art(out, "pkg.streaming-de.337")?.coverImage == "https://example.com/disney.jpg")
    #expect(art(out, "pkg.streaming-de.350")?.coverImage == "https://example.com/appletv.jpg")
    #expect(art(out, "pkg.streaming-de.531")?.coverImage == "https://example.com/paramount.jpg")
    for id in ["pkg.streaming-de.30", "pkg.streaming-de.298", "pkg.streaming-de.304"] { #expect(art(out, id)?.coverImage == nil, "\(id)") }
    // Titel und Reihenfolge der Paket-Kacheln bleiben.
    #expect(out.folders.map(\.title) == ReadyPackages.streamingDE.folders.map(\.title))
    #expect(PackageArtStats(folders: out.folders)?.logLine(row: "Streaming-Dienste") == "Paket-Bilder: Streaming-Dienste 5/8 mit Bild, 0 mit GIF, 0 mit Video")
}

@Test func genreTilesMatchEnglishAndGermanNames() {
    let names = ["Action", "Comedy", "Crime", "Dramas", "Sci-Fi", "Horror", "Thrillers", "Animated", "Documentaries", "Family"]
    let src = PackageArtSource(id: "nuvio.g", folders: names.map { tile($0, "https://example.com/\($0).webp") }, origin: .userImport)
    let out = ReadyPackages.withArt(ReadyPackages.genreCollection, sources: [src])
    #expect(out.folders.allSatisfy { $0.coverImage != nil })
    #expect(art(out, "pkg.genres.Komödie")?.coverImage == "https://example.com/Comedy.webp")
    #expect(art(out, "pkg.genres.Krimi")?.coverImage == "https://example.com/Crime.webp")
    #expect(art(out, "pkg.genres.Science-Fiction")?.coverImage == "https://example.com/Sci-Fi.webp")
    #expect(art(out, "pkg.genres.Dokumentation")?.coverImage == "https://example.com/Documentaries.webp")
    // Deutsche Namen gehen ebenso.
    let de = PackageArtSource(id: "nuvio.de", folders: [tile("Komödie", "https://example.com/k.webp"), tile("Krimi", "https://example.com/kr.webp")], origin: .userImport)
    let outDE = ReadyPackages.withArt(ReadyPackages.genreCollection, sources: [de])
    #expect(art(outDE, "pkg.genres.Komödie")?.coverImage == "https://example.com/k.webp")
    #expect(art(outDE, "pkg.genres.Krimi")?.coverImage == "https://example.com/kr.webp")
    // Ähnliche, aber andere Namen passen nicht („Action-thrillers“ ist nicht „Action“).
    let near = PackageArtSource(id: "k", folders: [tile("Action-thrillers", "https://example.com/at.png")], origin: .kit)
    #expect(art(ReadyPackages.withArt(ReadyPackages.genreCollection, sources: [near]), "pkg.genres.Action")?.coverImage == nil)
}

@Test func artSourcePrecedence() {
    let kitFull = PackageArtSource(id: "kit.full", folders: [
        tile("Netflix", "https://example.com/kit-n.jpg"), tile("Primevideo", "https://example.com/kit-p.jpg"),
        tile("Disney", "https://example.com/kit-d.jpg"),
    ], origin: .kit)
    let kitSmall = PackageArtSource(id: "kit.small", folders: [
        tile("Netflix", "https://example.com/small-n.jpg"), tile("Joyn", "https://example.com/small-j.jpg"),
    ], origin: .kit)
    // Die Kit-Datei mit den meisten Treffern gewinnt, auch wenn sie später kommt; Lücken füllt die nächste.
    let a = ReadyPackages.withArt(ReadyPackages.streamingDE, sources: [kitSmall, kitFull])
    #expect(art(a, "pkg.streaming-de.8")?.coverImage == "https://example.com/kit-n.jpg")
    #expect(art(a, "pkg.streaming-de.304")?.coverImage == "https://example.com/small-j.jpg")
    // Nutzer-Import vor gewähltem Kit vor übrigem Kit, unabhängig von der Trefferzahl.
    let user = PackageArtSource(id: "nuvio.c", folders: [tile("Netflix", "https://example.com/user-n.webp")], origin: .userImport)
    let chosen = PackageArtSource(id: "kit.chosen", folders: [tile("Disney+", "https://example.com/chosen-d.png")], origin: .chosenKit)
    let b = ReadyPackages.withArt(ReadyPackages.streamingDE, sources: [kitFull, chosen, user])
    #expect(art(b, "pkg.streaming-de.8")?.coverImage == "https://example.com/user-n.webp")
    #expect(art(b, "pkg.streaming-de.337")?.coverImage == "https://example.com/chosen-d.png")
    #expect(art(b, "pkg.streaming-de.9")?.coverImage == "https://example.com/kit-p.jpg")
    // Gleich viele Treffer: die Quelle mit GIFs, sonst die erste.
    let still = PackageArtSource(id: "still", folders: [tile("Netflix", "https://example.com/s.jpg")], origin: .kit)
    let moving = PackageArtSource(id: "moving", folders: [tile("Netflix", "https://example.com/m.jpg", gif: "https://example.com/m.gif")], origin: .kit)
    #expect(art(ReadyPackages.withArt(ReadyPackages.streamingDE, sources: [still, moving]), "pkg.streaming-de.8")?.focusGif == "https://example.com/m.gif")
    let still2 = PackageArtSource(id: "still2", folders: [tile("Netflix", "https://example.com/s2.jpg")], origin: .kit)
    #expect(art(ReadyPackages.withArt(ReadyPackages.streamingDE, sources: [still, still2]), "pkg.streaming-de.8")?.coverImage == "https://example.com/s.jpg")
}

@Test func packageArtGifAndLogo() {
    let src = PackageArtSource(id: "nuvio.c", folders: [
        tile("Netflix", "https://example.com/n.webp", gif: "https://example.com/n.gif", logo: "https://example.com/n-logo.png"),
        // Standbild ist selbst ein GIF: spielt beim Fokus.
        tile("Prime Video", "https://example.com/p.GIF"),
        tile("Disney+", "https://example.com/d.webp", gif: ""),
    ], origin: .userImport)
    let out = ReadyPackages.withArt(ReadyPackages.streamingDE, sources: [src])
    #expect(art(out, "pkg.streaming-de.8")?.focusGif == "https://example.com/n.gif")
    #expect(art(out, "pkg.streaming-de.8")?.logo == "https://example.com/n-logo.png")
    #expect(art(out, "pkg.streaming-de.9")?.focusGif == "https://example.com/p.GIF")
    #expect(art(out, "pkg.streaming-de.337")?.focusGif == nil)
    let stats = PackageArtStats(folders: out.folders)
    #expect(stats?.images == 3 && stats?.gifs == 2 && stats?.tiles == 8)
    // Reihen ohne Paket-Kachel: keine Logzeile.
    #expect(PackageArtStats(folders: [tile("x", "c")]) == nil)
}

@Test func kitFileFeedsPackageArt() throws {
    let json = #"""
    {"exportType":"fusionWidgets","exportVersion":1,"widgets":[{"id":"collection.G","title":"Genres","type":"collection.row",
     "dataSource":{"kind":"collection","payload":{"items":[
      {"hideTitle":true,"id":"A","imageAspect":"wide","imageURL":"https://example.com/action-wide.png","title":"Action",
       "dataSources":[{"kind":"traktList","payload":{"listName":"L","listSlug":"l","traktId":1,"username":"u"}}]},
      {"hideTitle":true,"id":"C","imageAspect":"wide","imageURL":"https://example.com/crime-wide.png","title":"Crime",
       "dataSources":[{"kind":"traktList","payload":{"listName":"L2","listSlug":"l2","traktId":2,"username":"u"}}]}]}}}]}
    """#
    let content = try FusionImport.parse(Data(json.utf8), sourceKey: "k1", title: "Genres · test")
    let sources = PackageArtSource.kit(content, origin: .kit)
    #expect(sources.count == 1)
    // Ohne Trakt Client ID wären die Kacheln ausgeblendet; als Bildquelle zählen sie trotzdem.
    #expect(sources.first?.folders.count == 2)
    #expect(sources.first?.aspect == "wide")
    let out = ReadyPackages.withArt(ReadyPackages.genreCollection, sources: sources)
    #expect(art(out, "pkg.genres.Action")?.coverImage == "https://example.com/action-wide.png")
    // Der Name steht im Kit-Bild: kein zweiter Titel über der Kachel.
    #expect(art(out, "pkg.genres.Action")?.hideTitle == true)
    #expect(art(out, "pkg.genres.Action")?.showsTitleOverImage == false)
    #expect(art(out, "pkg.genres.Krimi")?.coverImage == "https://example.com/crime-wide.png")
    #expect(PackageArtStats(folders: out.folders)?.logLine(row: "Genres") == "Paket-Bilder: Genres 2/10 mit Bild, 0 mit GIF, 0 mit Video")
}

@Test func packageArtKitFiles() {
    func entry(_ path: String, custom: Bool = false) -> FusionKitSource {
        var s = FusionKitCatalog.kitSource(path: path, url: "https://example.com/json/" + path)
        s.custom = custom
        return s
    }
    let listing = [
        entry("widgets/widgets-sourced-streaming-wide-b-tinted.json"),
        entry("widgets/widgets-sourced-decades-wide-x.json"),
        entry("widgets/widgets-sourced-genres-wide-a.json"),
        entry("widgets/widgets-sourced-streaming-wide-b-color.json"),
        entry("widgets/widgets-sourced-genres-poster-a.json"),
        entry("setup/setup-x.json"),
        entry("widgets/widgets-sourced-genres-wide-own.json", custom: true),
    ]
    let picked = FusionKitCatalog.packageArtSources(listing)
    #expect(picked.map(\.title) == ["Genres · a", "Streaming · b-color", "Streaming · b-tinted"])
    // Ohne Dateiliste: bekannte Dateien mit denselben IDs wie im Katalog.
    let fallback = FusionKitCatalog.packageArtSources([])
    #expect(fallback.count == 3)
    #expect(Set(fallback.map(\.id)) == Set(FusionKitCatalog.packageArtFallback.map { FusionKitCatalog.kitSource(path: $0).id }))
    #expect(fallback.allSatisfy { !$0.custom && $0.url.hasPrefix("https://") })
}

@Test func krimiTileHasOwnSymbol() {
    #expect(ReadyPackages.tileStyle(forFolderID: "pkg.genres.Krimi")?.symbol == "touchid")
}

@Test func wideArtBeatsOtherFormats() {
    // Poster-Datei mit mehr Treffern verliert gegen die breite; unbekanntes Format zählt als breit.
    let poster = PackageArtSource(id: "kit.poster", folders: [
        tile("Netflix", "https://example.com/p-n.jpg"), tile("Disney", "https://example.com/p-d.jpg"),
        tile("Joyn", "https://example.com/p-j.jpg"),
    ], origin: .chosenKit, aspect: "poster")
    let wide = PackageArtSource(id: "kit.wide", folders: [tile("Netflix", "https://example.com/w-n.jpg")], origin: .kit, aspect: "wide")
    let unknown = PackageArtSource(id: "nuvio.c", folders: [tile("Disney+", "https://example.com/u-d.webp")], origin: .userImport)
    let out = ReadyPackages.withArt(ReadyPackages.streamingDE, sources: [poster, wide, unknown])
    #expect(art(out, "pkg.streaming-de.8")?.coverImage == "https://example.com/w-n.jpg")
    #expect(art(out, "pkg.streaming-de.337")?.coverImage == "https://example.com/u-d.webp")
    // Nur die Poster-Datei kennt Joyn: dann kommt sie zum Zug.
    #expect(art(out, "pkg.streaming-de.304")?.coverImage == "https://example.com/p-j.jpg")
}

@Test func packageArtCopiesTitleSwitch() {
    var shown = tile("Drama", "https://example.com/d.webp")
    shown.hideTitle = false
    var hidden = tile("Horror", "https://example.com/h.webp")
    hidden.hideTitle = true
    let src = PackageArtSource(id: "nuvio.g", folders: [shown, hidden, tile("Action", "https://example.com/a.webp")], origin: .userImport)
    let out = ReadyPackages.withArt(ReadyPackages.genreCollection, sources: [src])
    #expect(art(out, "pkg.genres.Drama")?.showsTitleOverImage == true)
    #expect(art(out, "pkg.genres.Horror")?.showsTitleOverImage == false)
    // Import ohne Angabe: wie dessen eigene Kachel kein Titel über dem Bild.
    #expect(art(out, "pkg.genres.Action")?.hideTitle == nil)
    #expect(art(out, "pkg.genres.Action")?.showsTitleOverImage == false)
    // Ohne Bild bleibt der Titel-Schalter der Paket-Kachel unberührt.
    #expect(art(out, "pkg.genres.Krimi")?.hideTitle == nil)
}

@Test func kitSourcesSkipUnchosenNonPackFiles() {
    func content(_ title: String) -> FusionKitContent {
        FusionKitContent(rows: [FusionKitRow(id: "fusion.\(title).r", title: title, style: .landscape,
            body: .collection(MediaCollection(id: "fusion.\(title).r", title: title, folders: [tile("Netflix", "https://example.com/\(title).jpg")])),
            imageAspect: "wide")])
    }
    let contents = ["pack2": content("pack2"), "pack1": content("pack1"), "poster": content("poster"), "chosen": content("chosen")]
    let titles = ["pack1": "Streaming · a", "pack2": "Genres · b", "poster": "Genres (Poster) · c", "chosen": "Zuletzt gewählt"]
    let out = PackageArtSource.kitSources(contents: contents, titles: titles, chosen: ["chosen"], packFiles: ["pack1", "pack2"])
    // Gewählte zuerst, dann Paket-Bilddateien nach Titel; die ungewählte andere Datei fehlt.
    #expect(out.map(\.id) == ["fusion.chosen.r", "fusion.pack2.r", "fusion.pack1.r"])
    #expect(out.map(\.origin) == [.chosenKit, .kit, .kit])
    #expect(out.allSatisfy { $0.aspect == "wide" })
}
