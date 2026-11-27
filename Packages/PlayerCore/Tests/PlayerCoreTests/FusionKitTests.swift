import Foundation
import Testing
@testable import PlayerCore

// Eigene Mini-Beispiele im Fusion-Format (keine Kit-Dateien im Repo – das Kit hat keine Lizenz).

private let widgetsJSON = #"""
{"exportType":"fusionWidgets","exportVersion":1,"widgets":[
 {"id":"trakt.A","title":"Trending Shows","type":"row.classic.numbered","limit":50,"cacheTTL":3600,
  "presentation":{"aspectRatio":"poster"},
  "dataSource":{"kind":"traktList","payload":{"username":"someone","listSlug":"trending-shows","traktId":1,"listName":"Trending Shows"}}},
 {"id":"trakt.B","title":"Watchlist: Series","type":"row.classic",
  "dataSource":{"kind":"traktList","payload":{"username":"__me__","listSlug":"__watchlist_shows__","traktId":-12}}},
 {"id":"trakt.rec.C","title":"Recommended","type":"row.classic","dataSource":{"kind":"traktRecommendations","payload":{"type":"shows"}}},
 {"id":"collection.D","title":"Decades","type":"collection.row","dataSource":{"kind":"collection","payload":{"items":[
   {"id":"I1","title":"1980s","imageURL":"https://img.example/80s.jpg","imageAspect":"wide","hideTitle":true,
    "dataSources":[{"kind":"traktList","payload":{"username":"someone","listSlug":"popular-1980s-movies","listName":"Popular 1980s Movies"}},
                   {"kind":"traktList","payload":{"username":"someone","listSlug":"popular-1980s-shows","listName":"Popular 1980s Shows"}}]},
   {"id":"I2","title":"Leer","imageURL":"https://img.example/leer.jpg","imageAspect":"wide"},
   {"id":"I3","title":"Action","imageURL":"https://img.example/a b.jpg","imageAspect":"poster",
    "dataSources":[{"kind":"tmdbDiscover","payload":{"type":"movie","includeGenres":[28,12],"sortBy":"popularity.desc",
                     "releaseChannel":"digital","releaseStatus":"released"}}]}]}}},
 {"id":"collection.E","title":"Streaming (Color)","type":"collection.row","dataSource":{"kind":"collection","payload":{"items":[
   {"id":"J1","title":"Nur Leer"}]}}},
 {"id":"x.F","title":"Neu","type":"row.fancy","dataSource":{"kind":"mdblist","payload":{}}}
]}
"""#

/// 21.11.2026, 12:00 UTC
private let noon = Date(timeIntervalSince1970: 1_795_262_400)

@Test func fusionWidgetsMapToRows() throws {
    let c = try FusionImport.parse(Data(widgetsJSON.utf8), sourceKey: "src1", now: noon)
    #expect(c.rows.map(\.id) == ["fusion.src1.trakt.A", "fusion.src1.trakt.B", "fusion.src1.trakt.rec.C", "fusion.src1.collection.D"])

    let top = c.rows[0]
    #expect(top.style == .top10 && top.title == "Trending Shows")
    #expect(top.content == .list(CatalogSource(id: "fusion.src1.trakt.A", title: "Trending Shows",
                                               kind: .trakt(user: "someone", list: "trending-shows"), mediaType: .both, limit: 50)))
    #expect(top.needs == .traktID)

    let wl = c.rows[1]
    guard case .list(let ws) = wl.body else { Issue.record("keine Liste"); return }
    #expect(ws.kind == .trakt(user: nil, list: "watchlist/shows") && ws.mediaType == .series && wl.style == .poster)
    #expect(wl.needs == [.traktID, .traktLogin])

    let rec = c.rows[2]
    guard case .list(let rs) = rec.body else { Issue.record("keine Liste"); return }
    #expect(rs.kind == .trakt(user: nil, list: "recommendations/shows") && rs.mediaType == .series)
    #expect(rec.needs == [.traktID, .traktLogin])

    let dec = c.rows[3]
    #expect(dec.title == "Jahrzehnte" && dec.style == .collectionTiles && dec.content == .collection(id: "fusion.src1.collection.D"))
    guard case .collection(let col) = dec.body else { Issue.record("keine Collection"); return }
    #expect(col.folders.map(\.title) == ["1980s", "Action"])   // Kachel ohne Quellen entfällt
    #expect(col.folders[0].id == "fusion.src1.collection.D.I1" && col.folders[0].coverImage == "https://img.example/80s.jpg")
    #expect(col.folders[0].sources.map(\.title) == ["Popular 1980s Movies", "Popular 1980s Shows"])
    #expect(col.folders[1].coverImage == "https://img.example/a%20b.jpg")
    #expect(col.folders[0].hideTitle == true && col.folders[1].hideTitle == nil)
    #expect(!col.folders[0].showsTitleOverImage)
    #expect(dec.needs == [.traktID, .tmdb])
    #expect(dec.imageAspect == "poster" || dec.imageAspect == "wide")

    #expect(c.warnings["traktRecommendations übersprungen"] == nil)
    #expect(c.warnings["Kachel ohne Quellen"] == 2)
    #expect(c.warnings["Collection ohne Kacheln mit Quellen"] == 1)
    #expect(c.warnings["Quelle mdblist übersprungen"] == 1)
    #expect(c.warnings["Reihentyp row.fancy als Poster-Reihe"] == 1)
}

@Test func fusionTMDBDiscoverFilters() throws {
    let c = try FusionImport.parse(Data(widgetsJSON.utf8), sourceKey: "s", now: noon)
    guard case .collection(let col) = c.rows[3].body, case .tmdbDiscover(let f) = col.folders[1].sources[0].kind else {
        Issue.record("kein Discover"); return
    }
    #expect(f == ["with_genres": "28,12", "sort_by": "popularity.desc", "with_release_type": "4", "release_date.lte": "2026-11-21"])
    #expect(col.folders[1].sources[0].mediaType == .movie && col.folders[1].sources[0].title == "Action · Filme")

    let tv = #"{"exportType":"fusionWidgets","widgets":[{"id":"w","title":"T","type":"collection.row","dataSource":{"kind":"collection","payload":{"items":[{"id":"x","title":"Krimi","dataSources":[{"kind":"tmdbDiscover","payload":{"type":"tv","includeGenres":[80],"sortBy":"primary_release_date.desc","releaseStatus":"released"}}]}]}}}]}"#
    let t = try FusionImport.parse(Data(tv.utf8), sourceKey: "s", now: noon)
    guard case .collection(let tc) = t.rows[0].body, case .tmdbDiscover(let tf) = tc.folders[0].sources[0].kind else {
        Issue.record("kein Discover"); return
    }
    #expect(tf == ["with_genres": "80", "sort_by": "first_air_date.desc", "first_air_date.lte": "2026-11-21"])
    #expect(tc.folders[0].sources[0].mediaType == .series)
}

@Test func fusionCollectionListAndOtherFormats() throws {
    let list = #"""
    [{"id":"A","name":"1980s","backgroundImageURL":"https://img.example/80.jpg","layout":"Wide","hideTitle":true,
      "dataSources":[{"kind":"traktList","payload":{"username":"u","listSlug":"l80"}}]},
     {"id":"B","name":"1990s","layout":"Wide","dataSource":{"kind":"traktList","payload":{"username":"u","listSlug":"l90"}}}]
    """#
    let c = try FusionImport.parse(Data(list.utf8), sourceKey: "k", title: "Decades")
    #expect(c.rows.count == 1 && c.rows[0].id == "fusion.k.collection" && c.rows[0].title == "Jahrzehnte")
    guard case .collection(let col) = c.rows[0].body else { Issue.record("keine Collection"); return }
    #expect(col.folders.map(\.title) == ["1980s", "1990s"] && col.folders[0].coverImage == "https://img.example/80.jpg")
    #expect(col.folders[1].sources[0].kind == .trakt(user: "u", list: "l90"))
    #expect(c.rows[0].imageAspect == "wide")

    #expect(throws: FusionImportError.iconPack) {
        try FusionImport.parse(Data(#"[{"name":"IM (IMDb)","url":"https://x/im.png"}]"#.utf8), sourceKey: "k")
    }
    #expect(throws: FusionImportError.unknownFormat) { try FusionImport.parse(Data(#"{"foo":1}"#.utf8), sourceKey: "k") }
}

@Test func fusionAvailabilityWithoutTrakt() throws {
    let c = try FusionImport.parse(Data(widgetsJSON.utf8), sourceKey: "s", now: noon)
    // Ohne Client ID: Trakt-Listen weg, Kachel-Reihe behält nur die TMDB-Kachel.
    #expect(c.rows[0].available(traktID: false, traktLogin: false) == nil)
    #expect(c.rows[2].available(traktID: true, traktLogin: false) == nil)   // Empfehlungen brauchen die Anmeldung
    let dec = try #require(c.rows[3].available(traktID: false, traktLogin: false))
    guard case .collection(let col) = dec.body else { Issue.record("keine Collection"); return }
    #expect(col.folders.map(\.title) == ["Action"])
    // Merkliste braucht zusätzlich die Anmeldung.
    #expect(c.rows[1].available(traktID: true, traktLogin: false) == nil)
    #expect(c.rows[1].available(traktID: true, traktLogin: true) != nil)
    #expect(c.rows[0].available(traktID: true, traktLogin: false) == c.rows[0])
}

@Test func fusionIDsAndTitles() {
    #expect(FusionImport.sourceKey(ofID: "fusion.abc.collection.X") == "abc")
    #expect(FusionImport.sourceKey(ofID: "trakt.x") == nil && FusionImport.sourceKey(ofID: "fusion.") == nil)
    #expect(FusionImport.kitID(of: HomeRow(content: .collection(id: "fusion.a.b"))) == "fusion.a.b")
    #expect(FusionImport.kitID(of: HomeRow(content: .list(.continueWatching))) == nil)
    #expect(FusionImport.germanTitle("Streaming (Tinted)") == "Streaming")
    #expect(FusionImport.germanTitle("Directors") == "Regie")
    #expect(FusionImport.germanTitle("Top (2024)") == "Top (2024)")
}

// MARK: Katalog

@Test func fusionCatalogListing() {
    let listing = #"""
    [{"name":"widgets-sourced-genres-wide-a.b.json","path":"json/widgets/widgets-sourced-genres-wide-a.b.json","type":"file",
      "download_url":"https://raw.githubusercontent.com/itsrenoria/fusion-starter-kit/main/json/widgets/widgets-sourced-genres-wide-a.b.json"},
     {"name":"widgets-genres-wide-a.b.json","path":"json/widgets/widgets-genres-wide-a.b.json","type":"file"},
     {"name":"widgets-sourced-decades-poster-c.json","path":"json/widgets/widgets-sourced-decades-poster-c.json","type":"file"},
     {"name":"widgets-sourced-decades-wide-c.json","path":"json/widgets/widgets-sourced-decades-wide-c.json","type":"file"},
     {"name":"setup-z 🐐.json","path":"json/setup/setup-z 🐐.json","type":"file"},
     {"name":".gitkeep","path":"json/setup/.gitkeep","type":"file"},
     {"name":"sub","path":"json/widgets/sub","type":"dir"}]
    """#
    let s = FusionKitCatalog.parseListing(Data(listing.utf8))
    #expect(s.map(\.title) == ["Genres · a.b", "Jahrzehnte · c", "Komplette Startseite · z 🐐"])
    #expect(s[0].url.hasSuffix("/main/json/widgets/widgets-sourced-genres-wide-a.b.json") && !s[0].custom)
    #expect(s[1].url == "https://raw.githubusercontent.com/itsrenoria/fusion-starter-kit/refs/heads/main/json/widgets/widgets-sourced-decades-wide-c.json")
    #expect(s[2].url.hasSuffix("/json/setup/setup-z%20%F0%9F%90%90.json"))
    #expect(FusionKitCatalog.parseListing(Data("{}".utf8)).isEmpty)

    // „Copy JSON URL“ aus dem Kit → dieselbe Quelle (ID) wie im Katalog.
    let pasted = FusionKitCatalog.source(forURL: " https://raw.githubusercontent.com/itsrenoria/fusion-starter-kit/refs/heads/main/json/setup/setup-z%20%F0%9F%90%90.json ")
    #expect(pasted.id == s[2].id && !pasted.custom && pasted.title == s[2].title)
    let other = FusionKitCatalog.source(forURL: "https://example.org/my.json")
    #expect(other.custom && other.title == "Eigenes Kit · example.org" && other.id != pasted.id)
    #expect(FusionKitCatalog.title(forPath: "widgets/widgets-sourced-streaming-square-x-color.json") == "Streaming (Quadrat) · x-color")
}

// MARK: Abgleich mit der Startseite

private func kit(_ key: String, _ json: String = widgetsJSON) throws -> FusionKitContent {
    try FusionImport.parse(Data(json.utf8), sourceKey: key, now: noon)
}

private func ids(_ l: HomeLayout) -> [String] { l.rows.map { FusionImport.kitID(of: $0) ?? $0.content.key } }

@Test func fusionSyncAddsKeepsAndRemoves() throws {
    let src = FusionKitSource(id: "s", title: "S", url: "https://x", custom: true)
    let contents = ["s": try kit("s")]
    var layout = HomeLayout(rows: [HomeRow(content: .list(.continueWatching), style: .landscape)])
    var st = FusionKitSettings(enabled: true)
    st.setSelected("fusion.s.collection.D", true, source: src)
    st.setSelected("fusion.s.trakt.A", true, source: src)

    var r = FusionKitSync.apply(layout: &layout, settings: &st, contents: contents, traktID: true, traktLogin: false)
    #expect(r.added == ["fusion.s.collection.D", "fusion.s.trakt.A"] && r.layoutChanged)
    #expect(ids(layout) == ["list:builtin.continue", "fusion.s.collection.D", "fusion.s.trakt.A"])
    #expect(layout.rows[1].style == .collectionTiles && layout.rows[2].style == .top10)
    #expect(st.placed == ["fusion.s.collection.D", "fusion.s.trakt.A"] && st.sources == [src])

    // Nutzer schiebt die Liste nach oben und ändert den Stil: bleibt so, nichts wird neu angehängt.
    layout.rows.swapAt(0, 2)
    layout.rows[0].style = .poster
    r = FusionKitSync.apply(layout: &layout, settings: &st, contents: contents, traktID: true, traktLogin: false)
    #expect(!r.layoutChanged && ids(layout) == ["fusion.s.trakt.A", "fusion.s.collection.D", "list:builtin.continue"])
    #expect(layout.rows[0].style == .poster)

    // Ohne Client ID: Trakt-Liste ausgeblendet (Auswahl bleibt), Kachel-Reihe bleibt (TMDB-Kachel).
    r = FusionKitSync.apply(layout: &layout, settings: &st, contents: contents, traktID: false, traktLogin: false)
    // Build 6 (L3): parked with place and style, not removed.
    #expect(r.removed.isEmpty && r.parked == ["fusion.s.trakt.A"] && r.hidden == ["fusion.s.trakt.A"] && r.layoutChanged)
    #expect(st.isSelected("fusion.s.trakt.A") && ids(layout) == ["fusion.s.collection.D", "list:builtin.continue"])
    #expect(st.placed == ["fusion.s.collection.D"] && st.parked.map(\.kitID) == ["fusion.s.trakt.A"])
    // ID wieder da → Reihe kommt an ihren alten Platz (oben) mit ihrem Stil zurück.
    r = FusionKitSync.apply(layout: &layout, settings: &st, contents: contents, traktID: true, traktLogin: false)
    #expect(r.added == ["fusion.s.trakt.A"] && r.restored == ["fusion.s.trakt.A"] && st.parked.isEmpty)
    #expect(ids(layout) == ["fusion.s.trakt.A", "fusion.s.collection.D", "list:builtin.continue"])
    #expect(layout.rows[0].style == .poster)

    // Kit aus: alle Kit-Reihen weg, Auswahl bleibt für später.
    st.enabled = false
    r = FusionKitSync.apply(layout: &layout, settings: &st, contents: contents, traktID: true, traktLogin: false)
    #expect(ids(layout) == ["list:builtin.continue"] && st.placed.isEmpty && st.selected.count == 2)
    st.enabled = true
    r = FusionKitSync.apply(layout: &layout, settings: &st, contents: contents, traktID: true, traktLogin: false)
    #expect(r.added.count == 2)
}

@Test func fusionSyncEditorRemovalAndUnloadedSources() throws {
    let src = FusionKitSource(id: "s", title: "S", url: "https://x", custom: true)
    var layout = HomeLayout()
    var st = FusionKitSettings(enabled: true)
    st.setSelected("fusion.s.collection.D", true, source: src)
    st.setSelected("fusion.s.trakt.A", true, source: src)
    _ = FusionKitSync.apply(layout: &layout, settings: &st, contents: ["s": try kit("s")], traktID: true, traktLogin: true)
    #expect(layout.rows.count == 2)

    // Quelle noch nicht geladen (Start ohne Netz): Reihen bleiben stehen.
    var r = FusionKitSync.apply(layout: &layout, settings: &st, contents: [:], traktID: true, traktLogin: true)
    #expect(!r.layoutChanged && layout.rows.count == 2)

    // Im Editor entfernt → abgewählt, kommt nicht wieder.
    layout.rows.removeAll { FusionImport.kitID(of: $0) == "fusion.s.trakt.A" }
    r = FusionKitSync.apply(layout: &layout, settings: &st, contents: ["s": try kit("s")], traktID: true, traktLogin: true)
    #expect(r.deselected == ["fusion.s.trakt.A"] && r.added.isEmpty && st.selected == ["fusion.s.collection.D"])
    #expect(st.placed == ["fusion.s.collection.D"])

    // Reihe verschwindet aus dem Kit → von der Startseite entfernt.
    let empty = #"{"exportType":"fusionWidgets","widgets":[]}"#
    r = FusionKitSync.apply(layout: &layout, settings: &st, contents: ["s": try kit("s", empty)], traktID: true, traktLogin: true)
    #expect(r.removed == ["fusion.s.collection.D"] && layout.rows.isEmpty)

    // Eigene Quelle entfernen nimmt ihre Auswahl mit.
    st.removeSource("s")
    #expect(st.sources.isEmpty && st.selected.isEmpty)
}

@Test func fusionSettingsDecodeDefaultsAndAddAll() throws {
    let st = try JSONDecoder().decode(FusionKitSettings.self, from: Data(#"{"enabled":true}"#.utf8))
    #expect(st == FusionKitSettings(enabled: true))
    var s = FusionKitSettings()
    let src = FusionKitSource(id: "s", title: "S", url: "https://x", custom: true)
    s.addAll(try kit("s"), source: src)
    #expect(s.enabled && s.selected.count == 4 && s.sources == [src])   // mit Trakt-Empfehlungen (Welle C-d)
}

// MARK: Handy-Seite und Trakt

@Test func phoneKitURLBecomesCommand() {
    let page = PhoneInputPage()
    let body = "kit_url=+https%3A%2F%2Fraw.githubusercontent.com%2Fa%2Fb.json+"
    let raw = "POST /submit?t=tok HTTP/1.1\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
    guard case .complete(let r) = HTTPRequest.parse(Data(raw.utf8)) else { Issue.record("parse"); return }
    let (_, cmds) = page.handle(r, profileName: "Ich") { Data() }
    #expect(cmds == [.importFusionURL("https://raw.githubusercontent.com/a/b.json")])
    let html = page.page(profileName: "Ich", note: nil)
    #expect(html.contains("name=kit_url") && html.contains("https://kit.betterer.cc"))
}

@Test func traktWatchlistByTypeAndPublicList() async throws {
    let item = #"[{"type":"show","show":{"title":"The Bear","year":2022,"ids":{"imdb":"tt14452776"}}}]"#
    let http = FakeSender([(200, item), (200, item)])
    let t = TraktClient(clientID: "C", clientSecret: "", http: http)
    let w = try await t.list(user: nil, slug: "watchlist/shows", token: SyncToken(accessToken: "A"))
    #expect(w.map(\.id) == ["tt14452776"])
    #expect(http.sent[0].url.absoluteString == "https://api.trakt.tv/users/me/watchlist/shows")
    // Öffentliche Liste ohne Anmeldung: nur der Client-ID-Kopf.
    _ = try await t.list(user: "someone", slug: "popular-1980s-movies", token: nil)
    #expect(http.sent[1].url.absoluteString == "https://api.trakt.tv/users/someone/lists/popular-1980s-movies/items")
    #expect(http.sent[1].headers["trakt-api-key"] == "C" && http.sent[1].headers["Authorization"] == nil)
}

// MARK: Nachtrag: robuste Datei, sichere Trakt-Namen

@Test func fusionBrokenEntriesCostOnlyThemselves() throws {
    // Reihe 2 hat einen Titel als Zahl, Kachel 2 ein kaputtes Bild-Feld, Quelle 2 eine kaputte Nutzlast.
    let json = #"""
    {"exportType":"fusionWidgets","widgets":[
     {"id":"ok","title":"Gut","type":"row.classic","dataSource":{"kind":"traktList","payload":{"username":"u","listSlug":"a"}}},
     {"id":"bad","title":5,"type":"row.classic","dataSource":{"kind":"traktList","payload":{"username":"u","listSlug":"b"}}},
     {"id":"col","title":"Kacheln","type":"collection.row","dataSource":{"kind":"collection","payload":{"items":[
       {"id":"k1","title":"Eins","dataSources":[{"kind":"traktList","payload":{"username":"u","listSlug":"c"}},
                                              {"kind":"tmdbDiscover","payload":{"includeGenres":"kaputt"}}]},
       {"id":"k2","title":"Zwei","imageURL":{"x":1},"dataSources":[{"kind":"traktList","payload":{"username":"u","listSlug":"d"}}]}]}}},
     "keine Reihe"
    ]}
    """#
    let c = try FusionImport.parse(Data(json.utf8), sourceKey: "s")
    #expect(c.rows.map(\.id) == ["fusion.s.ok", "fusion.s.col"])
    #expect(c.warnings["Reihe unlesbar"] == 2 && c.warnings["Kachel unlesbar"] == 1 && c.warnings["Quelle unlesbar"] == 1)
    guard case .collection(let col) = c.rows[1].body else { Issue.record("keine Collection"); return }
    #expect(col.folders.map(\.title) == ["Eins"] && col.folders[0].sources.count == 1)

    // `widgets` keine Liste: leer mit Hinweis statt Fehler; flache Liste mit kaputtem Eintrag ebenso.
    let w = try FusionImport.parse(Data(#"{"exportType":"fusionWidgets","widgets":{"a":1}}"#.utf8), sourceKey: "s")
    #expect(w.rows.isEmpty && w.warnings["widgets unlesbar"] == 1)
    let flat = #"[{"id":"A","name":7},{"id":"B","name":"Gut","dataSources":[{"kind":"traktList","payload":{"username":"u","listSlug":"x"}}]}]"#
    let f = try FusionImport.parse(Data(flat.utf8), sourceKey: "s", title: "T")
    #expect(f.rows.count == 1 && f.warnings["Kachel unlesbar"] == 1)
}

@Test func fusionAndTraktRejectUnsafeNames() async throws {
    let json = #"""
    {"exportType":"fusionWidgets","widgets":[
     {"id":"a","title":"A","dataSource":{"kind":"traktList","payload":{"username":"u/../x","listSlug":"l"}}},
     {"id":"b","title":"B","dataSource":{"kind":"traktList","payload":{"username":"u","listSlug":"l?x=1"}}},
     {"id":"c","title":"C","dataSource":{"kind":"traktList","payload":{"username":"..","listSlug":"l"}}},
     {"id":"d","title":"D","dataSource":{"kind":"traktList","payload":{"username":"Some_User.1","listSlug":"top-10_list.v2"}}}
    ]}
    """#
    let c = try FusionImport.parse(Data(json.utf8), sourceKey: "s")
    #expect(c.rows.map(\.id) == ["fusion.s.d"] && c.warnings["Trakt-Liste mit ungültigem Namen"] == 3)

    #expect(TraktClient.isSafeName("abc-1.x_y") && !TraktClient.isSafeName("") && !TraktClient.isSafeName("..")
            && !TraktClient.isSafeName("a b") && !TraktClient.isSafeName("ä") && !TraktClient.isSafeName("a/b"))
    let http = FakeSender([])
    let t = TraktClient(clientID: "C", clientSecret: "", http: http)
    await #expect(throws: TraktNameError(name: "x/../y")) { try await t.list(user: "x/../y", slug: "l", token: nil) }
    await #expect(throws: TraktNameError(name: "l#a")) { try await t.list(user: "u", slug: "l#a", token: nil) }
    #expect(http.sent.isEmpty)
}

// MARK: Build 6 (L3): waiting rows keep place and style

private let traktSrc = FusionKitSource(id: "s", title: "S", url: "https://x.example.invalid", custom: true)
private let userA = HomeRow(content: .list(.continueWatching), style: .landscape)
private let userB = HomeRow(content: .list(CatalogSource(id: "u.b", title: "B", kind: .tmdbList(id: "1"), mediaType: .movie)))

/// Layout [userA, trakt.A (landscape), collection.D, userB] with all three kit rows placed.
private func placedLayout(_ st: inout FusionKitSettings, _ contents: [String: FusionKitContent]) -> HomeLayout {
    st = FusionKitSettings(enabled: true)
    st.setSelected("fusion.s.trakt.A", true, source: traktSrc)
    st.setSelected("fusion.s.collection.D", true, source: traktSrc)
    var layout = HomeLayout(rows: [userA])
    _ = FusionKitSync.apply(layout: &layout, settings: &st, contents: contents, traktID: true, traktLogin: true)
    layout.rows.append(userB)
    layout.rows[1].style = .landscape
    return layout
}

@Test func fusionWaitingRowKeepsIndexStyleAndID() throws {
    let contents = ["s": try kit("s")]
    var st = FusionKitSettings()
    var layout = placedLayout(&st, contents)
    #expect(ids(layout) == ["list:builtin.continue", "fusion.s.trakt.A", "fusion.s.collection.D", "list:u.b"])
    let rowID = layout.rows[1].id

    // No Client ID: the list leaves the start page (no empty row), the tile row stays.
    var r = FusionKitSync.apply(layout: &layout, settings: &st, contents: contents, traktID: false, traktLogin: false)
    #expect(r.parked == ["fusion.s.trakt.A"] && r.removed.isEmpty)
    #expect(ids(layout) == ["list:builtin.continue", "fusion.s.collection.D", "list:u.b"])
    // Still waiting: nothing changes, the parked entry stays as it was.
    let parked = st.parked
    r = FusionKitSync.apply(layout: &layout, settings: &st, contents: contents, traktID: false, traktLogin: false)
    #expect(!r.layoutChanged && r.parked.isEmpty && st.parked == parked)
    // Source not loaded (start without network): the entry stays too.
    r = FusionKitSync.apply(layout: &layout, settings: &st, contents: [:], traktID: true, traktLogin: true)
    #expect(st.parked == parked && ids(layout).count == 3)

    r = FusionKitSync.apply(layout: &layout, settings: &st, contents: contents, traktID: true, traktLogin: true)
    #expect(r.restored == ["fusion.s.trakt.A"] && st.parked.isEmpty)
    #expect(ids(layout) == ["list:builtin.continue", "fusion.s.trakt.A", "fusion.s.collection.D", "list:u.b"])
    #expect(layout.rows[1].style == .landscape && layout.rows[1].id == rowID)
    #expect(st.placed == ["fusion.s.trakt.A", "fusion.s.collection.D"])
}

@Test func fusionWaitingRowsFollowUserReordering() throws {
    let contents = ["s": try kit("s")]
    var st = FusionKitSettings()
    var layout = placedLayout(&st, contents)
    _ = FusionKitSync.apply(layout: &layout, settings: &st, contents: contents, traktID: false, traktLogin: false)
    // The user moves the row above it to the end while it waits: it comes back below that row.
    layout.rows.append(layout.rows.removeFirst())
    #expect(ids(layout) == ["fusion.s.collection.D", "list:u.b", "list:builtin.continue"])
    _ = FusionKitSync.apply(layout: &layout, settings: &st, contents: contents, traktID: true, traktLogin: true)
    #expect(ids(layout) == ["fusion.s.collection.D", "list:u.b", "list:builtin.continue", "fusion.s.trakt.A"])

    // The row above it is deleted while it waits: the next remembered row above, else the old index.
    layout = placedLayout(&st, contents)
    layout.rows.insert(HomeRow(content: .list(CatalogSource(id: "u.c", title: "C", kind: .tmdbList(id: "2"), mediaType: .series))), at: 1)
    // [userA, C, trakt.A, D, userB]
    _ = FusionKitSync.apply(layout: &layout, settings: &st, contents: contents, traktID: false, traktLogin: false)
    layout.rows.removeAll { $0.content.key == "list:u.c" }
    _ = FusionKitSync.apply(layout: &layout, settings: &st, contents: contents, traktID: true, traktLogin: true)
    #expect(ids(layout) == ["list:builtin.continue", "fusion.s.trakt.A", "fusion.s.collection.D", "list:u.b"])

    // Two neighbours wait (both need Trakt): they come back in their old order, whatever order they return in.
    st = FusionKitSettings(enabled: true)
    st.setSelected("fusion.s.trakt.B", true, source: traktSrc)
    st.setSelected("fusion.s.trakt.A", true, source: traktSrc)
    layout = HomeLayout(rows: [userA])
    _ = FusionKitSync.apply(layout: &layout, settings: &st, contents: contents, traktID: true, traktLogin: true)
    layout.rows.append(userB)
    layout.rows.swapAt(1, 2)   // [userA, trakt.A, trakt.B, userB]; selection order is B, A
    let before = ids(layout)
    _ = FusionKitSync.apply(layout: &layout, settings: &st, contents: contents, traktID: false, traktLogin: false)
    #expect(ids(layout) == ["list:builtin.continue", "list:u.b"] && st.parked.count == 2)
    _ = FusionKitSync.apply(layout: &layout, settings: &st, contents: contents, traktID: true, traktLogin: true)
    #expect(ids(layout) == before)
}

@Test func fusionWaitingRowDroppedWithKit() throws {
    let contents = ["s": try kit("s")]
    var st = FusionKitSettings()
    var layout = placedLayout(&st, contents)
    _ = FusionKitSync.apply(layout: &layout, settings: &st, contents: contents, traktID: false, traktLogin: false)
    #expect(st.parked.count == 1)

    // Removing the kit source forgets it.
    var copy = st
    copy.removeSource("s")
    #expect(copy.parked.isEmpty)
    // Deselected while it waits: forgotten, it does not come back.
    copy = st
    var l = layout
    copy.setSelected("fusion.s.trakt.A", false, source: traktSrc)
    _ = FusionKitSync.apply(layout: &l, settings: &copy, contents: contents, traktID: true, traktLogin: true)
    #expect(copy.parked.isEmpty && !ids(l).contains("fusion.s.trakt.A"))
    // Kit off: forgotten as well; turned on again it is a new row at the end.
    st.enabled = false
    _ = FusionKitSync.apply(layout: &layout, settings: &st, contents: contents, traktID: true, traktLogin: true)
    #expect(st.parked.isEmpty && ids(layout) == ["list:builtin.continue", "list:u.b"])
    // Row gone from the kit file while it waits: forgotten.
    var st2 = FusionKitSettings()
    var l2 = placedLayout(&st2, contents)
    _ = FusionKitSync.apply(layout: &l2, settings: &st2, contents: contents, traktID: false, traktLogin: false)
    let empty = #"{"exportType":"fusionWidgets","widgets":[]}"#
    _ = FusionKitSync.apply(layout: &l2, settings: &st2, contents: ["s": try kit("s", empty)], traktID: true, traktLogin: true)
    #expect(st2.parked.isEmpty)
}

@Test func fusionRowWaitingForAddonKeepsPlace() throws {
    let json = #"{"exportType":"fusionWidgets","widgets":[{"id":"p","title":"P","type":"row.classic","dataSource":{"kind":"addonCatalog","payload":{"addonId":"YOUR_AIOMETADATA","catalogId":"movie::x","type":"movie"}}}]}"#
    let contents = ["s": try FusionImport.parse(Data(json.utf8), sourceKey: "s")]
    let aio = InstalledAddon(manifestURL: "https://aio.example.invalid/manifest.json",
                             manifest: AddonManifest(id: "com.example.aio", name: "AIOMetadata", version: "1", resources: [], types: [],
                                                     catalogs: [CatalogDescriptor(type: "movie", id: "x")]))
    var st = FusionKitSettings(enabled: true)
    st.setSelected("fusion.s.p", true, source: traktSrc)
    var layout = HomeLayout(rows: [userA])
    _ = FusionKitSync.apply(layout: &layout, settings: &st, contents: contents, traktID: true, traktLogin: true, addons: [aio])
    layout.rows.insert(layout.rows.removeLast(), at: 0)
    layout.rows[0].style = .hero
    layout.rows.append(userB)   // [p (hero), userA, userB]

    // Addon removed: the row waits off the start page.
    var r = FusionKitSync.apply(layout: &layout, settings: &st, contents: contents, traktID: true, traktLogin: true, addons: [])
    #expect(r.parked == ["fusion.s.p"] && ids(layout) == ["list:builtin.continue", "list:u.b"])
    r = FusionKitSync.apply(layout: &layout, settings: &st, contents: contents, traktID: true, traktLogin: true, addons: [aio])
    #expect(r.restored == ["fusion.s.p"] && ids(layout) == ["fusion.s.p", "list:builtin.continue", "list:u.b"])
    #expect(layout.rows[0].style == .hero)
}

@Test func fusionSettingsParkedRoundTrip() throws {
    var st = FusionKitSettings(enabled: true)
    st.parked = [FusionKitParkedRow(row: HomeRow(content: .list(CatalogSource(id: "fusion.s.x", title: "X", kind: .tmdbList(id: "1"), mediaType: .movie)),
                                                 style: .hero), above: ["list:builtin.continue"], index: 1)]
    let back = try JSONDecoder().decode(FusionKitSettings.self, from: JSONEncoder().encode(st))
    #expect(back == st && back.parked.first?.kitID == "fusion.s.x")
    // Older settings without `parked` (and an unreadable value) decode to none.
    let bad = try JSONDecoder().decode(FusionKitSettings.self, from: Data(#"{"enabled":true,"parked":7}"#.utf8))
    #expect(bad.parked.isEmpty && bad.enabled)
}
