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
    #expect(AddonCatalogResolver.resolve([], addonId: any, catalogId: "m1", type: "movie") == nil)
}

@Test func managerOddPresentationKeepsRow() throws {
    let json = #"{"exportType":"fusionWidgets","widgets":[{"id":"p","title":"P","type":"row.classic","presentation":"wide","dataSource":{"kind":"addonCatalog","payload":{"addonId":"YOUR_AIOMETADATA","catalogId":"movie::x"}}}]}"#
    let c = try FusionImport.parse(Data(json.utf8), sourceKey: "p")
    #expect(c.rows.count == 1 && c.rows[0].style == .poster)
}
