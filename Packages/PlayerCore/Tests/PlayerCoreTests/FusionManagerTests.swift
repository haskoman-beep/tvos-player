import Foundation
import Testing
@testable import PlayerCore

// Build 5 (b5f): exports of the Fusion Widget Manager. Hand-written mini examples in the same shape as the manager's
// export (`exportConfigToFusion`), no copied files; all addresses use example.invalid.

private let managerExport = #"""
{"exportType":"fusionWidgets","exportVersion":1,
 "requiredAddons":["https://aio.example.invalid/stremio/secret-config/manifest.json"],
 "widgets":[
  {"id":"catalog.r1","title":"Trending Movies","type":"row.classic","cacheTTL":1800,"limit":20,
   "presentation":{"aspectRatio":"wide","badges":{"providers":false,"ratings":true},"cardStyle":"medium"},
   "dataSource":{"kind":"addonCatalog","payload":{"addonId":"https://aio.example.invalid/stremio/secret-config/manifest.json",
                 "catalogId":"movie::mdblist.123","type":"movie"}}},
  {"id":"catalog.r2","title":"Anime Season","type":"row.classic","cacheTTL":1800,"limit":20,
   "presentation":{"aspectRatio":"poster","badges":{"providers":false,"ratings":true},"cardStyle":"medium"},
   "dataSource":{"kind":"anilistCatalog","payload":{"catalogType":"trending","limit":20}}},
  {"id":"catalog.r3","title":"Unified","type":"row.classic","hideTitle":true,"cacheTTL":1800,"limit":15,
   "presentation":{"aspectRatio":"square","badges":{"providers":false,"ratings":true},"cardStyle":"large"},
   "dataSource":{"kind":"addonCatalog","payload":{"addonId":"YOUR_AIOMETADATA","catalogId":"all::trakt.list.42","type":"series"}}},
  {"id":"collection.c1","title":"Streaming","hideTitle":false,"type":"collection.row",
   "dataSource":{"kind":"collection","payload":{"items":[
    {"id":"i1","title":"Service A","hideTitle":true,"imageAspect":"wide","imageURL":"https://img.example.invalid/a.png",
     "dataSources":[{"kind":"addonCatalog","payload":{"addonId":"YOUR_AIOMETADATA","catalogId":"movie::streaming.a","type":"movie"}},
                    {"kind":"addonCatalog","payload":{"addonId":"YOUR_AIOMETADATA","catalogId":"series::streaming.a","type":"series"}},
                    {"kind":"anilistCatalog","payload":{"catalogType":"popular","limit":20}}]},
    {"id":"i2","title":"Only AniList","hideTitle":false,"imageAspect":"wide",
     "dataSources":[{"kind":"anilistCatalog","payload":{"catalogType":"popular","limit":20}}]},
    {"id":"i3","title":"Trakt","hideTitle":false,"imageAspect":"wide",
     "dataSources":[{"kind":"traktList","payload":{"listName":"Some List","listSlug":"some-list","traktId":7,"username":"someone"}}]}]}}}
 ]}
"""#

@Test func managerAddonCatalogRow() throws {
    let c = try FusionImport.parse(Data(managerExport.utf8), sourceKey: "m")
    #expect(c.rows.map(\.id) == ["fusion.m.catalog.r1", "fusion.m.catalog.r3", "fusion.m.collection.c1"])
    let r1 = c.rows[0]
    #expect(r1.style == .landscape && r1.title == "Trending Movies")
    guard case .list(let s) = r1.body else { Issue.record("keine Liste"); return }
    // Only scheme and host of the addon address are kept (the path carries the user's addon configuration).
    #expect(s.kind == .addon(addonId: "https://aio.example.invalid", catalogId: "mdblist.123", type: "movie"))
    #expect(s.mediaType == .movie && s.limit == 20 && s.title == "Trending Movies")
    let encoded = String(decoding: try JSONEncoder().encode(s), as: UTF8.self)
    #expect(!encoded.contains("secret-config"))
}

@Test func managerPlaceholderAndAllCatalog() throws {
    let c = try FusionImport.parse(Data(managerExport.utf8), sourceKey: "m")
    let r3 = c.rows[1]
    #expect(r3.style == .poster)
    guard case .list(let s) = r3.body else { Issue.record("keine Liste"); return }
    #expect(s.kind == .addon(addonId: AddonCatalogResolver.anyAddon, catalogId: "trakt.list.42", type: "series"))
    #expect(s.mediaType == .series && s.limit == 15)
}

@Test func managerCollectionWithAddonAndAniList() throws {
    let c = try FusionImport.parse(Data(managerExport.utf8), sourceKey: "m")
    let row = c.rows[2]
    guard case .collection(let col) = row.body else { Issue.record("keine Collection"); return }
    #expect(col.folders.map(\.title) == ["Service A", "Trakt"])
    #expect(col.folders[0].sources.map(\.kind) == [
        .addon(addonId: AddonCatalogResolver.anyAddon, catalogId: "streaming.a", type: "movie"),
        .addon(addonId: AddonCatalogResolver.anyAddon, catalogId: "streaming.a", type: "series"),
    ])
    #expect(col.folders[0].sources.map(\.mediaType) == [.movie, .series])
    #expect(Set(col.folders[0].sources.map(\.id)).count == 2)
    #expect(col.folders[0].hideTitle == true && col.folders[0].coverImage == "https://img.example.invalid/a.png")
    #expect(row.imageAspect == "wide")
    #expect(c.warnings["AniList-Katalog übersprungen"] == 3)
    #expect(c.warnings["Kachel ohne Quellen"] == 1)
    // Known manager fields (requiredAddons, cacheTTL, presentation, badges) are no warnings.
    #expect(Set(c.warnings.keys) == ["AniList-Katalog übersprungen", "Kachel ohne Quellen"])
}

@Test func managerEditorFormatAndOddValues() throws {
    // The editor state (`sourceType`, `catalogType`, `name`, `layout`, `backgroundImageURL`) and odd values.
    let json = #"""
    {"exportType":"fusionWidgets","exportVersion":1,"widgets":[
     {"id":"e1","title":"Editor","type":"row.classic","limit":20,"presentation":{"aspectRatio":"poster"},
      "dataSource":{"sourceType":"aiometadata","kind":"addonCatalog","payload":{"addonId":"YOUR_AIOMETADATA","catalogId":"tmdb.top","catalogType":"Series"}}},
     {"id":"e2","title":"Leer","type":"row.classic","dataSource":{"kind":"addonCatalog","payload":{"addonId":"YOUR_AIOMETADATA","catalogId":""}}},
     {"id":"e3","title":"Shows","type":"row.classic","dataSource":{"kind":"addonCatalog","payload":{"addonId":"com.example.addon","catalogId":"Shows::top"}}},
     {"id":"e4","title":"Coll","type":"collection.row","dataSource":{"kind":"collection","payload":{"items":[
      {"id":"x","name":"Tile","layout":"Square","backgroundImageURL":"https://img.example.invalid/t.png",
       "dataSources":[{"sourceType":"aiometadata","kind":"addonCatalog","payload":{"addonId":"YOUR_AIOMETADATA","catalogId":"movie::a.b","catalogType":"movie"}}]}]}}}
    ]}
    """#
    let c = try FusionImport.parse(Data(json.utf8), sourceKey: "e")
    #expect(c.rows.map(\.id) == ["fusion.e.e1", "fusion.e.e3", "fusion.e.e4"])
    guard case .list(let s1) = c.rows[0].body, case .list(let s3) = c.rows[1].body else { Issue.record("keine Liste"); return }
    #expect(s1.kind == .addon(addonId: AddonCatalogResolver.anyAddon, catalogId: "tmdb.top", type: "series"))
    // A plain addon id stays as it is; without a type field the type comes from the prefix.
    #expect(s3.kind == .addon(addonId: "com.example.addon", catalogId: "top", type: "series"))
    #expect(c.warnings["Addon-Katalog ohne ID"] == 1)
    guard case .collection(let col) = c.rows[2].body else { Issue.record("keine Collection"); return }
    #expect(col.folders[0].title == "Tile" && col.folders[0].coverImage == "https://img.example.invalid/t.png")
    #expect(c.rows[2].imageAspect == "square")
}

// MARK: Resolver (which installed addon serves a catalog)

private func addon(_ id: String, _ url: String, _ catalogs: [(String, String)]) -> InstalledAddon {
    InstalledAddon(manifestURL: url, manifest: AddonManifest(id: id, name: id, version: "1", resources: [], types: [],
                                                             catalogs: catalogs.map { CatalogDescriptor(type: $0.0, id: $0.1) }))
}

@Test func resolverPrefersExactManifestID() {
    let a = addon("com.example.a", "https://a.example.invalid/manifest.json", [])
    let r = AddonCatalogResolver.resolve([a], addonId: "com.example.a", catalogId: "x", type: "movie")
    #expect(r?.addon == a && r?.type == "movie")
}

@Test func resolverMatchesHostAndCatalog() {
    let other = addon("com.example.other", "https://other.example.invalid/manifest.json", [("movie", "mdblist.123")])
    let aio = addon("com.example.aio", "https://aio.example.invalid/stremio/cfg/manifest.json", [("movie", "mdblist.123")])
    let r = AddonCatalogResolver.resolve([other, aio], addonId: "https://aio.example.invalid", catalogId: "mdblist.123", type: "movie")
    #expect(r?.addon == aio)
    // Host not installed: any addon that declares the catalog.
    let r2 = AddonCatalogResolver.resolve([other], addonId: "https://gone.example.invalid", catalogId: "mdblist.123", type: "movie")
    #expect(r2?.addon == other)
}

@Test func resolverPlaceholderUsesCatalogType() {
    let a = addon("com.example.a", "https://a.example.invalid/manifest.json", [("movie", "m1")])
    let b = addon("com.example.b", "https://b.example.invalid/manifest.json", [("all", "trakt.list.42"), ("series", "s1")])
    let any = AddonCatalogResolver.anyAddon
    // The manifest's own type wins when the requested one is not declared (`all::` catalogs).
    #expect(AddonCatalogResolver.resolve([a, b], addonId: any, catalogId: "trakt.list.42", type: "series").map { [$0.addon.manifest.id, $0.type] }
            == ["com.example.b", "all"])
    #expect(AddonCatalogResolver.resolve([a, b], addonId: any, catalogId: "s1", type: "series")?.addon == b)
    #expect(AddonCatalogResolver.resolve([a, b], addonId: any, catalogId: "missing", type: "movie") == nil)
    // One declared type: taken for a guessed type; two other types: ambiguous, no match.
    #expect(AddonCatalogResolver.resolve([a], addonId: any, catalogId: "m1", type: "series")?.type == "movie")
    let c = addon("com.example.c", "https://c.example.invalid/manifest.json", [("movie", "d"), ("anime", "d")])
    #expect(AddonCatalogResolver.resolve([c], addonId: any, catalogId: "d", type: "series") == nil)
    #expect(AddonCatalogResolver.resolve([], addonId: any, catalogId: "m1", type: "movie") == nil)
}

@Test func managerOddPresentationKeepsRow() throws {
    let json = #"{"exportType":"fusionWidgets","widgets":[{"id":"p","title":"P","type":"row.classic","presentation":"wide","dataSource":{"kind":"addonCatalog","payload":{"addonId":"YOUR_AIOMETADATA","catalogId":"movie::x"}}}]}"#
    let c = try FusionImport.parse(Data(json.utf8), sourceKey: "p")
    #expect(c.rows.count == 1 && c.rows[0].style == .poster)
}

// MARK: Formats the app cannot import

@Test func managerOtherFormatsAreNamed() {
    let omni = #"{"values":{"main_group_order":["g1"],"main_catalog_groups":{"g1":{"name":"A"}}}}"#
    #expect(CollectionImportFormat.detect(Data(omni.utf8)) == .omniSnapshot)
    #expect(CollectionImportFormat.omniSnapshot.problem == nil && CollectionImportFormat.omniSnapshot.name == "Omni-Snapshot")
    let catalogs = #"{"version":1,"exportedAt":"2026-01-01T00:00:00Z","catalogs":[{"id":"trakt.list.1","type":"movie","name":"L","enabled":true,"source":"trakt"}]}"#
    #expect(CollectionImportFormat.detect(Data(catalogs.utf8)) == .addonConfig)
    #expect(CollectionImportFormat.addonConfig.problem?.contains("AIOMetadata") == true)
    #expect(PhoneImportDetect.detect(omni) == .command(.importCollectionCode(Data(omni.utf8))))
    #expect(PhoneImportDetect.detect(catalogs) == .refused(.addonConfig))
    // A widget export stays a widget export.
    #expect(CollectionImportFormat.detect(Data(managerExport.utf8)) == .widgets)
}

@Test func addonManifestIsNoAddonConfig() {
    let manifest = #"{"id":"com.example.a","version":"1","name":"A","resources":["catalog"],"types":["movie"],"catalogs":[{"type":"movie","id":"x"}]}"#
    #expect(CollectionImportFormat.detect(Data(manifest.utf8)) == .unknown)
}


@Test func importSummaryNamesSkipped() {
    #expect(ImportSummary.note([:]) == "")
    #expect(ImportSummary.note(["AniList-Katalog übersprungen": 3, "Kachel ohne Quellen": 1])
            == " · Hinweise: AniList-Katalog übersprungen ×3, Kachel ohne Quellen ×1")
}


// MARK: Omni/UME snapshot (converted like the manager's convertOmniToFusion)

private func omniSnapshot() -> String {
    // Omni wraps values as base64 JSON in `_data`; one wrapped value is enough to cover the decoding.
    let groups = Data(#"{"Service A":["movie:streaming.a","series:streaming.a"],"Empty":[]}"#.utf8).base64EncodedString()
    return #"""
    {"values":{
      "main_group_order":["g1","g2"],
      "main_catalog_groups":{"g1":{"name":"Streaming","posterType":"landscape","subgroupNames":["Service A","❗️Header","Empty"]},
                             "g2":{"name":"❗️[Discover]","subgroupNames":["Service A"]}},
      "catalog_groups":{"_data":"\#(groups)"},
      "subgroup_order":{"g1":["Empty","Service A"]},
      "catalog_group_image_urls":{"Service A":"https://img.example.invalid/a.png"},
      "catalog_ordering":["movie:mdblist.1","series:aisearch.home.1.series"],
      "selected_catalogs":["movie:mdblist.1","all:trakt.list.5","movie:hdr"],
      "disabled_shelves":["movie:hdr"],
      "custom_catalog_names":{"movie:mdblist.1":"Top Movies","all:trakt.list.5":"My List"}
    }}
    """#
}

@Test func omniSnapshotBecomesRows() throws {
    let data = Data(omniSnapshot().utf8)
    #expect(CollectionImportFormat.detect(data) == .omniSnapshot)
    let c = try FusionImport.parse(data, sourceKey: "o")
    #expect(c.rows.map(\.title) == ["Streaming", "Top Movies", "My List"])
    #expect(c.rows[0].id == "fusion.o.omni.group.g1" && c.rows[0].style == .collectionTiles && c.rows[0].imageAspect == "wide")
    guard case .collection(let col) = c.rows[0].body else { Issue.record("keine Collection"); return }
    #expect(col.folders.map(\.title) == ["Service A"] && col.folders[0].coverImage == "https://img.example.invalid/a.png")
    #expect(col.folders[0].sources.map(\.kind) == [
        .addon(addonId: AddonCatalogResolver.anyAddon, catalogId: "streaming.a", type: "movie"),
        .addon(addonId: AddonCatalogResolver.anyAddon, catalogId: "streaming.a", type: "series"),
    ])
    guard case .list(let top) = c.rows[1].body, case .list(let mine) = c.rows[2].body else { Issue.record("keine Liste"); return }
    #expect(top.kind == .addon(addonId: AddonCatalogResolver.anyAddon, catalogId: "mdblist.1", type: "movie") && top.limit == 20)
    #expect(mine.kind == .addon(addonId: AddonCatalogResolver.anyAddon, catalogId: "trakt.list.5", type: "series"))
    #expect(c.warnings.isEmpty)
    // Same snapshot, same IDs (the manager uses random ones).
    #expect(try FusionImport.parse(data, sourceKey: "o").rows.map(\.id) == c.rows.map(\.id))
}

@Test func omniOddSnapshotNeverThrows() throws {
    let odd = #"{"values":{"main_catalog_groups":{"g":{"name":5}},"catalog_groups":{"_data":"not base64!"},"selected_catalogs":[1,"movie:x"]}}"#
    let c = try FusionImport.parse(Data(odd.utf8), sourceKey: "o")
    #expect(c.rows.map(\.title) == ["x"])
    #expect(OmniImport.normalizedID("Movie:a.b") == "movie::a.b" && OmniImport.normalizedID("series::c") == "series::c")
    #expect(OmniImport.catalogType("tmdb.top.shows") == "series"
            && OmniImport.catalogType("tmdb.top_shows") == "movie" && OmniImport.catalogType("all::x") == "all")
}

// MARK: Rows without a serving addon stay hidden until it is installed

@Test func managerRowsNeedAServingAddon() throws {
    let c = try FusionImport.parse(Data(managerExport.utf8), sourceKey: "m")
    let aio = addon("com.example.aio", "https://aio.example.invalid/stremio/cfg/manifest.json",
                    [("movie", "mdblist.123"), ("movie", "streaming.a"), ("anime", "streaming.a")])
    #expect(c.rows[0].available(traktID: true, traktLogin: true, addons: []) == nil)
    #expect(c.rows[0].available(traktID: true, traktLogin: true, addons: [aio]) == c.rows[0])
    #expect(c.rows[0].available(traktID: true, traktLogin: true) == c.rows[0])   // nil = no addon check
    // Tile row: the series catalog is not declared (and the id has two other types) → that source goes, the tile
    // stays; the Trakt tile is untouched.
    let tiles = try #require(c.rows[2].available(traktID: true, traktLogin: false, addons: [aio]))
    guard case .collection(let col) = tiles.body else { Issue.record("keine Collection"); return }
    #expect(col.folders.map(\.title) == ["Service A", "Trakt"] && col.folders[0].sources.count == 1)

    let src = FusionKitSource(id: "m", title: "M", url: "https://example.invalid/m.json", custom: true)
    var st = FusionKitSettings(enabled: true)
    st.setSelected("fusion.m.catalog.r1", true, source: src)
    var layout = HomeLayout(rows: [])
    var r = FusionKitSync.apply(layout: &layout, settings: &st, contents: ["m": c], traktID: true, traktLogin: true, addons: [])
    #expect(r.hidden == ["fusion.m.catalog.r1"] && layout.rows.isEmpty && st.isSelected("fusion.m.catalog.r1"))
    r = FusionKitSync.apply(layout: &layout, settings: &st, contents: ["m": c], traktID: true, traktLogin: true, addons: [aio])
    #expect(r.added == ["fusion.m.catalog.r1"] && layout.rows.count == 1)
}

@Test func rowCatalogHidesKitRowsWithoutServingAddon() throws {
    let c = try FusionImport.parse(Data(managerExport.utf8), sourceKey: "m")
    let src = FusionKitSource(id: "m", title: "M", url: "https://example.invalid/m.json", custom: true)
    let none = try #require(RowCatalog(layout: HomeLayout(), kitSources: [src], kitContents: ["m": c],
                                       traktID: true, traktLogin: true).group("kit"))
    // Both addon list rows hidden; the tile row keeps its Trakt tile (2 tiles parsed, 1 left).
    #expect(none.hiddenCount == 2 && none.hint == "Kein Addon mit den Katalogen (z. B. AIOMetadata) – 2 Reihen ausgeblendet")
    let tiles = try #require(none.sections.flatMap(\.entries).first { $0.title == "Streaming" })
    #expect(tiles.subtitle.hasPrefix("1 von 2 Kacheln (ohne passendes Addon)"))

    let aio = addon("com.example.aio", "https://aio.example.invalid/manifest.json",
                    [("movie", "mdblist.123"), ("all", "trakt.list.42"), ("movie", "streaming.a"), ("series", "streaming.a")])
    let all = try #require(RowCatalog(layout: HomeLayout(), addons: [aio], kitSources: [src], kitContents: ["m": c],
                                      traktID: true, traktLogin: true).group("kit"))
    #expect(all.hiddenCount == 0 && all.hint == nil)
}

// MARK: Device test 26.11. (github.com page link, widget export with 0 rows)

@Test func githubPageLinkBecomesRawLink() {
    #expect(CollectionImportLink.raw("https://github.com/someone/repo/blob/main/dir/file.json")
            == "https://raw.githubusercontent.com/someone/repo/main/dir/file.json")
    // Review M2: /raw/ links worked before (GitHub redirects) and stay as they are (stored link ids).
    #expect(CollectionImportLink.raw("https://github.com/someone/repo/raw/refs/heads/main/a%20b.json")
            == "https://github.com/someone/repo/raw/refs/heads/main/a%20b.json")
    #expect(CollectionImportLink.raw("https://example.invalid/x.json") == "https://example.invalid/x.json")
    #expect(CollectionImportLink.raw("https://github.com/someone/repo") == "https://github.com/someone/repo")
}

@Test func widgetImportLines() throws {
    // Nothing readable: a reason instead of a silent "0 Reihen".
    #expect(ImportSummary.emptyWidgets(["Quelle mdblist übersprungen": 2])
            == "Import: Widget-Export ohne lesbare Reihen · Hinweise: Quelle mdblist übersprungen ×2")
    #expect(ImportSummary.emptyWidgets([:]) == "Import: Widget-Export ohne lesbare Reihen (keine Widgets gefunden)")
    // Rows that wait for an addon are counted.
    let c = try FusionImport.parse(Data(managerExport.utf8), sourceKey: "m")
    #expect(c.waitingForAddon([]) == 2)
    let aio = addon("com.example.aio", "https://aio.example.invalid/manifest.json", [("movie", "mdblist.123"), ("all", "trakt.list.42")])
    #expect(c.waitingForAddon([aio]) == 0)
    #expect(ImportSummary.addonNote(2) == " · 2 Reihen warten auf ein Addon mit den Katalogen (z. B. AIOMetadata)")
    #expect(ImportSummary.addonNote(1) == " · 1 Reihe wartet auf ein Addon mit den Katalogen (z. B. AIOMetadata)")
    #expect(ImportSummary.addonNote(0) == "")
}


// MARK: Review round (b5f-review.md)

@Test func importNoteCapsKeysAndLength() {
    let long = "Quelle " + String(repeating: "x", count: 5000) + "\nzwei übersprungen"
    let n = ImportSummary.note([long: 1, "Kurz": 2])
    #expect(!n.contains("\n") && n.count <= ImportSummary.maxNoteLength)
    #expect(n.hasPrefix(" · Hinweise: Kurz ×2, Quelle xxx"))
    // Keys are capped when the importer records them, too.
    let json = #"{"exportType":"fusionWidgets","widgets":[{"id":"a","title":"A","type":"row.classic","dataSource":{"kind":"\#(String(repeating: "k", count: 3000))","payload":{}}}]}"#
    let c = try? FusionImport.parse(Data(json.utf8), sourceKey: "w")
    #expect(c.map { $0.warnings.keys.allSatisfy { $0.count <= ImportSummary.maxWarningLength + 20 } } == true)
    #expect(ImportSummary.emptyWidgets([:], format: "Omni-Snapshot") == "Import: Omni-Snapshot ohne lesbare Reihen (keine Widgets gefunden)")
}

@Test func omniLargeSnapshotIsCapped() throws {
    let ids = (0..<(OmniImport.maxRows + 30)).map { "\"movie:cat.\($0)\"" }.joined(separator: ",")
    let json = #"{"values":{"catalog_ordering":["# + ids + "," + ids + #"]}}"#
    let c = try FusionImport.parse(Data(json.utf8), sourceKey: "o")
    #expect(c.rows.count == OmniImport.maxRows)
    #expect(c.warnings["Omni-Kataloge über der Grenze"] == 30)
}

@Test func resolverIndexAndAmbiguousFallback() {
    let any = AddonCatalogResolver.anyAddon
    let cinemeta = addon("com.example.cinemeta", "https://c.example.invalid/manifest.json", [("movie", "top")])
    let tmdb = addon("com.example.tmdb", "https://t.example.invalid/manifest.json", [("movie", "top")])
    // Several addons declare a generic id: no guess …
    #expect(AddonCatalogResolver.resolve([cinemeta, tmdb], addonId: any, catalogId: "top", type: "movie") == nil)
    #expect(AddonCatalogResolver.resolve([cinemeta, tmdb], addonId: "https://gone.example.invalid", catalogId: "top", type: "movie") == nil)
    // … the exact host still decides, and an AIOMetadata addon is preferred for the placeholder.
    #expect(AddonCatalogResolver.resolve([cinemeta, tmdb], addonId: "https://t.example.invalid", catalogId: "top", type: "movie")?.addon == tmdb)
    let aio = addon("com.example.aiometadata", "https://aio.example.invalid/x/manifest.json", [("movie", "top")])
    #expect(AddonCatalogResolver.resolve([cinemeta, aio], addonId: any, catalogId: "top", type: "movie")?.addon == aio)
    // Requested `all` with two declared types (none `all`): ambiguous.
    let two = addon("com.example.two", "https://two.example.invalid/manifest.json", [("movie", "d"), ("series", "d")])
    #expect(AddonCatalogResolver.resolve([two], addonId: any, catalogId: "d", type: "all") == nil)
    // The index gives the same answers as the plain call.
    let idx = AddonCatalogIndex([cinemeta, aio, two])
    #expect(AddonCatalogResolver.resolve(idx, addonId: any, catalogId: "top", type: "movie")?.addon == aio)
    #expect(AddonCatalogResolver.resolve(idx, addonId: any, catalogId: "d", type: "series")?.type == "series")
}
