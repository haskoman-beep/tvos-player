import Foundation
import Testing
@testable import PlayerCore

private func addon() -> InstalledAddon {
    InstalledAddon(manifestURL: "https://example.invalid/manifest.json", manifest: AddonManifest(
        id: "aio", name: "AIOStreams", version: "1", resources: [], types: ["movie", "series"], catalogs: [
            CatalogDescriptor(type: "series", id: "top", name: "Top 10 Serien"),
            CatalogDescriptor(type: "movie", id: "pop", name: "Beliebte Filme"),
            CatalogDescriptor(type: "movie", id: "kom", name: "Komödie"),
            CatalogDescriptor(type: "anime", id: "ani", name: "Anime neu"),
            CatalogDescriptor(type: "movie", id: "search", name: "Suche", extra: [CatalogExtra(name: "search", isRequired: true)]),
        ]))
}

private func tmdb(_ id: String) -> CatalogSource {
    CatalogSource(id: id, title: id, kind: .tmdbDiscover(filters: [:]), mediaType: .movie)
}

private func traktList(_ id: String) -> CatalogSource {
    CatalogSource(id: id, title: id, kind: .trakt(user: "u", list: "l"), mediaType: .movie)
}

private func kitRow(_ id: String, _ title: String, tiles: Int, trakt: Bool = false) -> FusionKitRow {
    let folders = (0..<tiles).map { Folder(id: "\(id).\($0)", title: "K\($0)", sources: [trakt ? traktList("\(id).\($0)") : tmdb("\(id).\($0)")]) }
    return FusionKitRow(id: id, title: title, style: .collectionTiles, body: .collection(MediaCollection(id: id, title: title, folders: folders)))
}

private let kitA = FusionKitSource(id: "ka", title: "Genres · autorA", url: "u1", custom: false)
private let kitB = FusionKitSource(id: "kb", title: "Genres · autorB", url: "u2", custom: false)
private let kitC = FusionKitSource(id: "kc", title: "Streaming · x", url: "u3", custom: false)
private let kitD = FusionKitSource(id: "kd", title: "Jahrzehnte · y", url: "u4", custom: false)

private let kitContents: [String: FusionKitContent] = [
    "ka": FusionKitContent(rows: [kitRow("fusion.ka.g", "Genres", tiles: 56)]),
    "kb": FusionKitContent(rows: [kitRow("fusion.kb.g", "Genres", tiles: 10)]),
    "kc": FusionKitContent(rows: [kitRow("fusion.kc.s", "Streaming-Dienste", tiles: 24),
                                  kitRow("fusion.kc.t", "Trakt-Listen", tiles: 3, trakt: true)]),
]

private func catalog(layout: HomeLayout = HomeLayout(), traktID: Bool = false, traktLogin: Bool = false) -> RowCatalog {
    RowCatalog(layout: layout, addons: [addon()],
               collections: [MediaCollection(id: "c1", title: "Studios", folders: []), ReadyPackages.streamingDE],
               kitSources: [kitA, kitB, kitC, kitD], kitContents: kitContents,
               traktID: traktID, traktLogin: traktLogin)
}

@Test func groupsBySourceInFixedOrder() {
    let c = catalog()
    #expect(c.groups.map(\.title) == ["AIOStreams", "Meine Collections", "Fusion-Kit", "Trakt", "Sonderlisten", "Fertige Pakete"])
    let aio = c.groups[0]
    #expect(aio.kind == .addon && aio.count == 4)   // Katalog mit Pflicht-Suche fällt weg
    #expect(aio.sections.map(\.title) == ["Filme", "Serien", "Anime"])
    #expect(aio.sections[0].entries.map(\.title) == ["Beliebte Filme", "Komödie"])
    #expect(aio.sections[1].entries[0].subtitle == "Liste · Serie")
    // Gleiche Quellen-ID wie bisher im Hinzufügen-Blatt.
    #expect(aio.sections[0].entries[0].action == .content(.list(RowCatalog.addonSource(addon: addon().manifest,
                                                                                         catalog: CatalogDescriptor(type: "movie", id: "pop", name: "Beliebte Filme")))))
    #expect(aio.sections[0].entries[0].id == "list:addon:aio:movie:pop")
    #expect(c.group("special")?.entries.map(\.title) == ["Weiterschauen", "Merkliste", "Heute neu"])
    // Ein Paket, das schon eigene Collection ist, steht nur unter „Meine Collections“.
    #expect(c.group("collections")?.entries.map(\.title) == ["Studios", "Streaming-Dienste"])
    #expect(c.group("packages")?.entries.map(\.id) == ["collection:" + ReadyPackages.genreCollection.id])
}

@Test func addonWithoutCatalogsHasNoGroup() {
    var a = addon(); a.manifest.catalogs = []
    let c = RowCatalog(layout: HomeLayout(), addons: [a])
    #expect(!c.groups.contains { $0.kind == .addon })
    #expect(c.group("collections")?.count == 0 && c.group("collections")?.sections.isEmpty == true)
}

@Test func statusShowsHomePosition() {
    var l = HomeLayout()
    l.insert(.list(.continueWatching))
    l.insert(.collection(id: "c1"))
    l.insert(.list(RowCatalog.addonSource(addon: addon().manifest, catalog: CatalogDescriptor(type: "series", id: "top", name: "Top 10 Serien"))))
    l.insert(.collection(id: "fusion.kc.s"))
    let c = catalog(layout: l)
    #expect(c.group("special")?.entries[0].status == .onHome(position: 1))
    #expect(c.group("special")?.entries[1].status == .available)
    #expect(c.group("collections")?.entries[0].statusText == "auf der Startseite (2)")
    #expect(c.groups[0].sections[1].entries[0].isOnHome)
    #expect(c.group("kit")?.entries.first { $0.title == "Streaming-Dienste" }?.status == .onHome(position: 4))
    // ▶ springt auf den ersten Eintrag ohne Häkchen.
    #expect(c.group("special")?.firstAvailable?.title == "Merkliste")
}

@Test func kitGroupedByTopicWithCreator() {
    let c = catalog(traktID: true, traktLogin: true)
    let kit = c.group("kit")!
    #expect(kit.sections.map(\.title) == ["Genres", "Streaming"])
    #expect(kit.sections[0].entries.map(\.subtitle) == ["56 Kacheln · autorA", "10 Kacheln · autorB"])
    #expect(kit.count == 4 && kit.hiddenCount == 0 && kit.hint == nil)
    #expect(kit.pendingSources == 1)   // „Jahrzehnte“ noch nicht geladen
    #expect(kit.sections[0].entries[0].action == .kit(rowID: "fusion.ka.g", source: kitA))
}

@Test func kitHidesTraktRowsWithHint() {
    let kit = catalog(traktID: false).group("kit")!
    #expect(kit.count == 3 && kit.hiddenCount == 1)
    #expect(kit.hint == "Trakt Client ID fehlt – 1 Reihe ausgeblendet")
}

@Test func traktNeedsLogin() {
    let off = catalog(traktID: true, traktLogin: false).group("trakt")!
    #expect(off.count == 2)
    #expect(off.entries.allSatisfy { $0.status == .unavailable("braucht Trakt-Anmeldung") })
    #expect(off.firstAvailable?.title == CatalogSource.traktRecommendedMovies.title)
    let on = catalog(traktID: true, traktLogin: true).group("trakt")!
    #expect(on.entries.allSatisfy { $0.status == .available })
}

@Test func searchFoldsCaseAndUmlauts() {
    let c = catalog()
    #expect(c.search("komodie").map(\.title) == ["Komödie"])
    #expect(c.search("KOMÖDIE").map(\.title) == ["Komödie"])
    #expect(RowCatalog.fold("  Straße  ÄÖÜ é ") == "strasse aou e")
    #expect(c.search("strasse").isEmpty)
    #expect(c.search("   ").isEmpty)
    // Mehrere Wörter: alle müssen passen; Quelle zählt mit, Titeltreffer zuerst.
    #expect(c.search("aiostreams beliebte").map(\.title) == ["Beliebte Filme"])
    let genres = c.search("genres")
    #expect(genres.map(\.source) == ["Fusion-Kit", "Fusion-Kit", "Fertige Pakete"])
    #expect(genres.prefix(2).map(\.subtitle) == ["56 Kacheln · autorA", "10 Kacheln · autorB"])
    let serie = c.search("serie")
    #expect(serie.first?.title == "Top 10 Serien")                       // Titeltreffer, Katalogreihenfolge
    #expect(serie.contains { $0.title == CatalogSource.traktRecommendedShows.title })
    let film = c.search("film").map(\.title)
    // „Komödie“ passt nur über den Untertitel „Liste · Film“ und steht deshalb hinter den Titeltreffern.
    #expect(film.first == "Beliebte Filme")
    #expect(film.firstIndex(of: "Komödie")! > film.firstIndex(of: CatalogSource.traktRecommendedMovies.title)!)
}

@Test func kitTopicsInPlanOrderAndSetupsSplit() {
    let titles = ["Preise · a", "Zombies · b", "Komplette Startseite · Zwei", "Regie · c", "Animation · d",
                  "Jahrzehnte · e", "Komplette Startseite · Eins", "Streaming · f", "Genres · g"]
    let sources = titles.enumerated().map { FusionKitSource(id: "s\($0.offset)", title: $0.element, url: "u", custom: false) }
    var contents: [String: FusionKitContent] = [:]
    for (i, _) in titles.enumerated() {
        contents["s\(i)"] = FusionKitContent(rows: [kitRow("fusion.s\(i).a", "R\(i)a", tiles: 1), kitRow("fusion.s\(i).b", "R\(i)b", tiles: 2)])
    }
    let kit = RowCatalog(layout: HomeLayout(), kitSources: sources, kitContents: contents).group("kit")!
    #expect(kit.sections.map(\.title) == ["Genres", "Streaming", "Jahrzehnte", "Regie", "Preise", "Animation",
                                          "Komplette Startseite · Eins", "Komplette Startseite · Zwei", "Zombies"])
    // Jede komplette Startseite bleibt ein eigener Abschnitt; ihr Untertitel nennt nur die Art.
    let eins = kit.sections.first { $0.title == "Komplette Startseite · Eins" }!
    #expect(eins.entries.map(\.title) == ["R6a", "R6b"])
    #expect(eins.entries.map(\.subtitle) == ["1 Kacheln", "2 Kacheln"])
}

@Test func searchTransliteratesUmlauts() {
    let c = catalog()
    for q in ["komoedie", "Komödie", "komodie", "KOMOEDIE"] {
        #expect(c.search(q).map(\.title) == ["Komödie"], "\(q)")
    }
    var a = addon()
    a.manifest.catalogs = [CatalogDescriptor(type: "movie", id: "f", name: "Fuer Kinder"),
                           CatalogDescriptor(type: "movie", id: "s", name: "Straße der Träume")]
    let d = RowCatalog(layout: HomeLayout(), addons: [a], packages: [])
    #expect(d.search("für").map(\.title) == ["Fuer Kinder"])
    #expect(d.search("fuer").map(\.title) == ["Fuer Kinder"])
    #expect(d.search("strasse traeume").map(\.title) == ["Straße der Träume"])
    #expect(d.search("straße träume").map(\.title) == ["Straße der Träume"])
    #expect(RowCatalog.fold("Grüße", transliterate: true) == "gruesse")
}

@Test func traktTextsAndOnHomeWhileLoggedOut() {
    var l = HomeLayout()
    l.insert(.list(.traktRecommendedShows))
    let t = catalog(layout: l, traktID: false, traktLogin: false).group("trakt")!
    #expect(t.entries[0].status == .unavailable("braucht Trakt-Anmeldung und Client ID"))
    #expect(t.entries[1].status == .onHome(position: 1))
}

// F-b2-Review I2: ein in dieser Sitzung angelegtes Paket bleibt in „Fertige Pakete“ (Fokus, nochmal OK).
@Test func touchedPackageStaysInItsGroup() {
    let pkg = ReadyPackages.streamingDE
    var l = HomeLayout(); l.insert(.collection(id: pkg.id))
    let kept = RowCatalog(layout: l, collections: [pkg], keepPackages: [pkg.id]).group("packages")!
    #expect(kept.entries.first { $0.id == "collection:" + pkg.id }?.status == .onHome(position: 1))
    let gone = RowCatalog(layout: l, collections: [pkg]).group("packages")!
    #expect(!gone.entries.contains { $0.id == "collection:" + pkg.id })
}

// F-b2-Review M4: was einer Kit-Reihe fehlt, steht kurz im Untertitel; Ladefehler je Datei an der Gruppe.
@Test func kitEntriesNameMissingKeysAndLoadErrors() {
    let mixed = FusionKitRow(id: "fusion.kc.m", title: "Gemischt", style: .collectionTiles, body: .collection(MediaCollection(
        id: "fusion.kc.m", title: "Gemischt", folders: [Folder(id: "a", title: "A", sources: [tmdb("a")]),
                                                         Folder(id: "b", title: "B", sources: [traktList("b")])])))
    let kit = RowCatalog(layout: HomeLayout(), kitSources: [kitC, kitD],
                         kitContents: ["kc": FusionKitContent(rows: [mixed])], tmdb: false,
                         kitErrors: ["kd": "HTTP 404"]).group("kit")!
    #expect(kit.entries.map(\.subtitle) == ["1 von 2 Kacheln (ohne Trakt Client ID) · braucht TMDB-Schlüssel · x"])
    #expect(kit.failures == ["Jahrzehnte · y: HTTP 404"] && kit.pendingSources == 0)
}
