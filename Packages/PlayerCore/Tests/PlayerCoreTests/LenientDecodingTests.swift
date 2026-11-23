import Foundation
import Testing
@testable import PlayerCore

// Task 1.2: decoding never throws because of a single value. Unknown enum values fall back to the default and are
// named in the `DecodeReport`; unknown home rows and folder sources are kept as raw JSON and written back.
// All JSON here and in `Fixtures/future-profiles.json` is synthetic.

private func decodeReporting<T: Decodable>(_ type: T.Type, _ json: String) throws -> (value: T, report: DecodeReport) {
    try JSONDecoder().decodeReporting(T.self, from: Data(json.utf8))
}

/// Canonical bytes of a JSON value (sorted keys), so two values can be compared byte for byte.
private func canonical(_ value: Any) throws -> Data {
    try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])
}

private func jsonObject(_ data: Data) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

private let mosaicRow = """
{"id":"00000000-0000-4000-8000-0000000000b2","style":"mosaic","tiles":[1,2.5,-3,null,"x",{"nested":[true,false]}],
 "content":{"list":{"_0":{"id":"builtin.watchlist","title":"Merkliste","kind":{"watchlist":{}},"mediaType":"both"}}}}
"""
private let knownRow = """
{"id":"00000000-0000-4000-8000-0000000000b1","style":"landscape",
 "content":{"list":{"_0":{"id":"builtin.continue","title":"Weiterschauen","kind":{"continueWatching":{}},"mediaType":"both"}}}}
"""

@Test func unknownAccentFallsBackAndIsReported() throws {
    let (a, report) = try decodeReporting(Appearance.self, #"{"accent":"turquoise","heroEnabled":false}"#)
    #expect(a.accent == .blue)
    #expect(a.heroEnabled == false)
    #expect(report.ignored == ["accent"])

    let (p, pReport) = try decodeReporting(Profile.self,
        #"{"id":"00000000-0000-4000-8000-000000000011","name":"Test","appearance":{"accent":"turquoise"}}"#)
    #expect(p.appearance.accent == .blue)
    #expect(pReport.ignored.contains("appearance.accent"))
}

@Test func unknownNavigationCardSizeBadgeStyleLanguageProgressSource() throws {
    let json = """
    {"id":"00000000-0000-4000-8000-000000000012","name":"Test","language":"xx","progressSource":"netflix",
     "subtitleLanguage":"en",
     "appearance":{"navigation":"bottom","cardSize":"giant","accent":"pink","badges":{"style":"neon","hdr":false}}}
    """
    let (p, report) = try decodeReporting(Profile.self, json)
    #expect(p.name == "Test")
    #expect(p.subtitleLanguage == "en")
    #expect(p.language == .de)
    #expect(p.progressSource == .local)
    #expect(p.appearance.navigation == .sidebar)
    #expect(p.appearance.cardSize == .medium)
    #expect(p.appearance.accent == .pink)
    #expect(p.appearance.badges.style == .logo)
    #expect(p.appearance.badges.hdr == false)
    #expect(Set(report.ignored) == ["language", "progressSource", "appearance.navigation", "appearance.cardSize",
                                    "appearance.badges.style"])
}

@Test func unknownRowStyleIsKeptAsRawAndWrittenBack() throws {
    let (layout, report) = try decodeReporting(HomeLayout.self, "{\"rows\":[\(knownRow),\(mosaicRow)]}")
    #expect(layout.rows.count == 1)
    #expect(layout.rows.first?.style == .landscape)
    #expect(layout.unknownRows.count == 1)
    #expect(report.ignored == ["rows[1]"])

    // Written back: known rows first, then the unknown ones in their original order, values unchanged.
    let written = try JSONEncoder().encode(layout)
    let rows = try #require(try jsonObject(written)["rows"] as? [Any])
    #expect(rows.count == 2)
    let original = try JSONSerialization.jsonObject(with: Data(mosaicRow.utf8))
    #expect(try canonical(rows[1]) == canonical(original))

    // And a second round trip keeps everything.
    let again = try JSONDecoder().decode(HomeLayout.self, from: written)
    #expect(again == layout)
}

@Test func oneBrokenProfileDoesNotBreakTheOthers() throws {
    let json = """
    {"schemaVersion":1,"activeProfileID":"00000000-0000-4000-8000-000000000021","profiles":[
     {"id":"00000000-0000-4000-8000-000000000021","name":"Eins"},
     {"name":"Zwei ohne id"},
     {"id":"00000000-0000-4000-8000-000000000023","name":"Drei"}]}
    """
    let store = ProfileStore(directory: tempDir())
    try Data(json.utf8).write(to: store.fileURL)
    let (s, report) = store.load()
    #expect(s.profiles.map(\.name) == ["Eins", "Drei"])
    #expect(s.active?.name == "Eins")
    #expect(report.ignored == ["profiles[1]"])
    #expect(!FileManager.default.fileExists(atPath: store.backupURL.path))
}

@Test func ratingSourcesWrongTypeFallsBack() throws {
    let (t, report) = try decodeReporting(TitleDisplaySettings.self,
                                          #"{"ratingSources":"imdb","addonImages":false,"posterBadges":"bottom"}"#)
    #expect(t.ratingSources == TitleDisplaySettings().ratingSources)
    #expect(t.addonImages == false)
    #expect(t.posterBadges == .bottom)
    #expect(report.ignored == ["ratingSources"])
}

@Test func futureProfilesFixtureLoadsCompletely() throws {
    let data = try fixture("future-profiles.json")
    let (s, report) = try ProfileStore.decodeReporting(data)
    #expect(s.profiles.count == 2)
    #expect(s.active?.name == "Testprofil A")
    let a = s.profiles[0]
    // Known values stay.
    #expect(a.audioPriority == ["en", "orig"])
    #expect(a.subtitleLanguage == "en")
    #expect(a.apiKeys == ["tmdb": "FAKE-KEY-0000"])
    #expect(a.autoplayNext == false)
    #expect(a.stillWatchingAfter == 2)
    #expect(a.appearance.heroEnabled == false)
    #expect(a.appearance.expandPosters == false)
    #expect(a.appearance.prefetchStreams == false)
    #expect(a.appearance.tileAnimationSound == true)
    #expect(a.appearance.badges.hdr == false)
    #expect(a.appearance.titles.ratingSources == ["imdb"])
    #expect(a.appearance.titles.addonImages == false)
    // Unknown values fall back to the default.
    #expect(a.language == .de)
    #expect(a.subtitleMode == .forcedOnly)
    #expect(a.progressSource == .local)
    #expect(a.appearance.navigation == .sidebar)
    #expect(a.appearance.accent == .blue)
    #expect(a.appearance.cardSize == .medium)
    #expect(a.appearance.badges.style == .logo)
    #expect(a.appearance.titles.posterBadges == .off)
    // Rows and sources with unknown style or kind are kept aside.
    #expect(a.home.rows.map(\.style) == [.landscape, .collectionTiles])
    #expect(a.home.unknownRows.count == 2)
    let folder = try #require(a.collections.first?.folders.first)
    #expect(folder.sources.map(\.id) == ["s1"])
    #expect(folder.unknownSources.count == 2)
    #expect(s.profiles[1].appearance.accent == .purple)

    #expect(Set(report.ignored) == [
        "profiles[0].language", "profiles[0].subtitleMode", "profiles[0].progressSource",
        "profiles[0].appearance.navigation", "profiles[0].appearance.accent", "profiles[0].appearance.cardSize",
        "profiles[0].appearance.badges.style", "profiles[0].appearance.titles.posterBadges",
        "profiles[0].home.rows[1]", "profiles[0].home.rows[2]",
        "profiles[0].collections[0].folders[0].sources[1]", "profiles[0].collections[0].folders[0].sources[2]",
    ])

    // Writing back keeps the unknown rows and sources byte for byte (canonical form), after the known ones.
    let written = try JSONEncoder().encode(s)
    let raw = try jsonObject(data), out = try jsonObject(written)
    func profile0(_ o: [String: Any]) throws -> [String: Any] {
        try #require((o["profiles"] as? [[String: Any]])?.first)
    }
    let inRows = try #require((try profile0(raw)["home"] as? [String: Any])?["rows"] as? [Any])
    let outRows = try #require((try profile0(out)["home"] as? [String: Any])?["rows"] as? [Any])
    #expect(outRows.count == 4)
    #expect(try canonical(outRows[2]) == canonical(inRows[1]))
    #expect(try canonical(outRows[3]) == canonical(inRows[2]))
    func sources(_ p: [String: Any]) throws -> [Any] {
        let c = try #require((p["collections"] as? [[String: Any]])?.first)
        let f = try #require((c["folders"] as? [[String: Any]])?.first)
        return try #require(f["sources"] as? [Any])
    }
    let inSources = try sources(profile0(raw)), outSources = try sources(profile0(out))
    #expect(outSources.count == 3)
    #expect(try canonical(outSources[1]) == canonical(inSources[1]))
    #expect(try canonical(outSources[2]) == canonical(inSources[2]))

    let (again, againReport) = try ProfileStore.decodeReporting(written)
    #expect(again == s)
    #expect(againReport.ignored.filter { $0.contains("rows") || $0.contains("sources") }.count == 4)
}

@Test func legacyFixtureStillLoads() throws {
    let (s, report) = try ProfileStore.decodeReporting(fixture("main-profiles-v1.json"))
    #expect(s.profiles.count == 1)
    #expect(s.active?.appearance.accent == .green)
    #expect(s.active?.home.rows.count == 2)
    #expect(s.active?.home.unknownRows.isEmpty == true)
    #expect(report.ignored.isEmpty)
}

@Test func reportIsEmptyForCurrentData() throws {
    var p = Profile.makeDefault(name: "Aktuell")
    p.language = .en; p.progressSource = .simkl; p.subtitleMode = .always
    p.appearance = Appearance(navigation: .top, accent: .orange, cardSize: .small,
                              badges: BadgeSettings(style: .text),
                              titles: TitleDisplaySettings(posterBadges: .bottom, ratingSources: ["imdb", "tomatoes"]))
    let tiles = HomeRow(content: .collection(id: "c1"), style: .logoTiles)
    p.home.rows += RowStyle.allCases.filter { $0 != .logoTiles && $0 != .collectionTiles }
        .map { HomeRow(content: .list(.watchlist), style: $0) } + [tiles]
    p.hiddenRows = [HomeRow(content: .list(.upcoming), style: .poster)]
    p.collections = [MediaCollection(id: "c1", title: "Sammlung", folders: [
        Folder(id: "f1", title: "Ordner", coverImage: "https://img.example/a.jpg", sources: [
            CatalogSource(id: "s1", title: "Liste", kind: .tmdbList(id: "1"), mediaType: .movie, sortBy: "popularity.desc", limit: 5),
            CatalogSource(id: "s2", title: "Trakt", kind: .trakt(user: nil, list: "fake-list"), mediaType: .series),
        ], hideTitle: false),
    ])]
    let s = StoredProfiles(profiles: [p, Profile.makeDefault(name: "Zwei")], activeProfileID: p.id)
    let store = ProfileStore(directory: tempDir())
    let (decoded, report) = try ProfileStore.decodeReporting(store.exportData(s))
    #expect(decoded == s)
    #expect(report.ignored.isEmpty)
    try store.save(s)
    let (loaded, loadReport) = store.load()
    #expect(loaded == s)
    #expect(loadReport == DecodeReport())
}
