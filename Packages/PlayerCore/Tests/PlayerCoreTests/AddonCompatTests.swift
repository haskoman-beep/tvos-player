import Foundation
import Testing
@testable import PlayerCore

// Wave W-a: addon compatibility. Hand-written fixtures in the shapes aggregator and metadata addons send.

/// Collects the client's log lines.
private final class LogBox: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [(String, String)] = []
    func add(_ c: String, _ m: String) { lock.lock(); items.append((c, m)); lock.unlock() }
    var lines: [(category: String, message: String)] { lock.lock(); defer { lock.unlock() }; return items.map { ($0.0, $0.1) } }
}

private func client(_ routes: [String: String], _ box: LogBox) -> AddonClient {
    AddonClient(http: FakeHTTP(routes: routes), log: { box.add($0, $1) })
}

private func manifest(_ json: String) throws -> AddonManifest {
    try JSONDecoder().decode(AddonManifest.self, from: Data(json.utf8))
}

private func installed(_ base: String, _ json: String) throws -> InstalledAddon {
    InstalledAddon(manifestURL: base + "/manifest.json", manifest: try manifest(json))
}

private func streams(_ json: String) throws -> [StreamItem] {
    try JSONDecoder().decode(StreamsResponse.self, from: Data(json.utf8)).streams
}

private let animeManifest = #"{"id":"com.aio.metadata","name":"AIOMetadata","version":"1","resources":["catalog","meta"],"types":["anime","series","movie"],"catalogs":[{"type":"anime","id":"mal.top","name":"Top Anime"}]}"#
private let errorProjectPage = "https://github.com/someone/AIOStreams"

// MARK: Lenient decoding (L1, L11)

@Test func catalogSurvivesNumbersBrokenAndErrorItems() async throws {
    let box = LogBox()
    let a = try installed("https://meta.example/cfg", animeManifest)
    let body = """
    {"metas":[
      {"id":"mal:1","type":"anime","name":"Eins","releaseInfo":2019,"imdbRating":8.1,"poster":"https://img/1.jpg"},
      {"id":"mal:2","name":"Zwei","releaseInfo":null,"imdbRating":{"x":1},"poster":""},
      {"name":"ohne ID"},
      42,
      {"id":"aiostreamserror.{\\"x\\":1}","type":"anime","name":"[❌] Fehler","description":"Ungültige Konfiguration"},
      {"id":"tt3","type":"movie","name":"Drei","year":2001}
    ]}
    """
    let c = client(["https://meta.example/cfg/catalog/anime/mal.top.json": body], box)
    let page = try await c.catalogPage(a, type: "anime", id: "mal.top")
    #expect(page.items.map(\.id) == ["mal:1", "mal:2", "tt3"])
    #expect(page.skipped == 2)
    #expect(page.notices.count == 1 && page.notices[0].contains("Ungültige Konfiguration"))
    #expect(page.items[0].releaseInfo == "2019" && page.items[0].imdbRating == "8.1")
    #expect(page.items[1].type == "anime" && page.items[1].releaseInfo == nil && page.items[1].imdbRating == nil)
    #expect(page.items[1].poster == nil)
    #expect(page.items[2].releaseInfo == "2001")
    let line = try #require(box.lines.first { $0.category == "katalog" })
    #expect(line.message.contains("2 unlesbare Einträge übersprungen") && line.message.contains("1 Fehlereintrag"))
    // `catalog` gives the same items.
    #expect(try await c.catalog(a, type: "anime", id: "mal.top").map(\.id) == ["mal:1", "mal:2", "tt3"])
}

@Test func catalogWithoutListStillFails() async throws {
    let a = try installed("https://meta.example/cfg", animeManifest)
    let c = client(["https://meta.example/cfg/catalog/anime/mal.top.json": #"{"metas":"nope"}"#], LogBox())
    await #expect(throws: DecodingError.self) { try await c.catalog(a, type: "anime", id: "mal.top") }
}

@Test func metaDecodesNumbersTextAndSkipsBadVideos() throws {
    let json = """
    {"meta":{"id":"kitsu:7","type":"anime","name":"Serie","runtime":24,"releaseInfo":2019,"imdbRating":"7.4",
      "imdb_id":"tt0123","genres":["Action",5,null],"behaviorHints":{"defaultVideoId":"kitsu:7:1","hasScheduledVideos":"true"},
      "videos":[{"id":"kitsu:7:1","season":"1","episode":1.0,"title":"Folge 1","released":"2019-01-01"},
                {"id":"kitsu:7:2","season":1,"episode":"2","name":"Folge 2","description":"Text"},
                {"season":1},"kaputt"]}}
    """
    let m = try JSONDecoder().decode(MetaResponse.self, from: Data(json.utf8)).meta
    #expect(m.runtime == "24" && m.releaseInfo == "2019" && m.imdbRating == "7.4")
    #expect(m.imdbID == "tt0123" && m.defaultVideoId == "kitsu:7:1" && m.behaviorHints?.hasScheduledVideos == true)
    #expect(m.genres == ["Action", "5"])
    #expect(m.videos?.map(\.id) == ["kitsu:7:1", "kitsu:7:2"])
    #expect(m.videos?[0].season == 1 && m.videos?[0].episode == 1)
    #expect(m.videos?[1].episode == 2 && m.videos?[1].overview == "Text")
    // A wrong type in one field never drops the meta.
    let odd = try JSONDecoder().decode(MetaResponse.self, from: Data(#"{"meta":{"id":"tt1","name":"X","runtime":{"a":1},"videos":"x","genres":"Drama"}}"#.utf8)).meta
    #expect(odd.runtime == nil && odd.videos == nil && odd.genres == ["Drama"] && odd.type == "")
}

@Test func metaFillsRequestAndRejectsErrorItems() async throws {
    let box = LogBox()
    let a = try installed("https://meta.example/cfg", animeManifest)
    let c = client([
        "https://meta.example/cfg/meta/anime/mal:5.json": #"{"meta":{"name":"Ohne ID","videos":[]}}"#,
        "https://meta.example/cfg/meta/anime/mal:6.json": #"{"meta":{"id":"aiom.error.timeout","type":"anime","name":"Fehler","description":"Zeitüberschreitung beim Anbieter"}}"#,
    ], box)
    let m = try await c.meta(a, type: "anime", id: "mal:5")
    #expect(m.id == "mal:5" && m.type == "anime" && m.name == "Ohne ID")
    await #expect(throws: AddonNoticeError.self) { try await c.meta(a, type: "anime", id: "mal:6") }
    #expect(box.lines.contains { $0.category == "meta" && $0.message.contains("Zeitüberschreitung beim Anbieter") })
}

@Test func manifestKeepsGoodCatalogsAndReadsExtraDefaults() throws {
    let m = try manifest("""
    {"id":"x","name":"X","version":"1","types":["movie"],"resources":["catalog",{"bogus":1}],
     "catalogs":[{"type":"movie","id":"gen","name":"Genre","extra":[{"name":"genre","isRequired":true,"options":["Action",2019],"default":"Action","optionsLimit":"1"},{"x":1}]},
                 {"type":"movie"},
                 {"type":"movie","id":"plain","name":7}]}
    """)
    #expect(m.resources.map(\.name) == ["catalog"])
    #expect(m.catalogs.map(\.id) == ["gen", "plain"])
    let extra = try #require(m.catalogs[0].extra?.first)
    #expect(extra.name == "genre" && extra.isRequired == true && extra.options == ["Action", "2019"])
    #expect(extra.defaultValue == "Action" && extra.optionsLimit == 1)
    #expect(m.catalogs[0].extra?.count == 1)
    #expect(m.catalogs[1].name == "7")
}

// MARK: Stream notices (L5, L9)

private let noticeStreams = """
{"streams":[
  {"name":"[❌] Comet","description":"Invalid API key","externalUrl":"\(errorProjectPage)"},
  {"name":"Statistik","description":"Addons: 3 · Zeit: 1,2 s","externalUrl":"\(errorProjectPage)"},
  {"name":"\u{1F504}\u{FE0F} Bibliothek","description":"Sync library","url":"https://aio.example/sync/1"},
  {"name":"AIO","description":"Sync debrid account library now","url":"https://aio.example/sync/2"},
  {"name":"AIO","description":"Neu laden","url":"https://aio.example/x","streamData":{"type":"info"}},
  {"name":"Fehler","url":"https://aio.example/err","streamData":{"type":"error"}},
  {"name":"[RD+] 1080p","description":"Sync.Library.2020.1080p.WEB.mkv","url":"https://cdn.example/a.mkv"},
  {"name":"P2P","infoHash":"abc"},
  {"name":"[❌] Komisch","url":"https://cdn.example/b.mkv"}
]}
"""

@Test func classifiesAggregatorNotices() throws {
    let s = try streams(noticeStreams)
    #expect(s.map(\.addonKind) == [.error, .statistic, .action, .action, .action, .error, .stream, .stream, .stream])
    // Only the real http sources stay; a „[❌]“ name with a real video link is still a source.
    #expect(playableStreams(s).map(\.url) == ["https://cdn.example/a.mkv", "https://cdn.example/b.mkv"])
    #expect(!BestChoice.isPlayable(s[2]) && BestChoice.isPlayable(s[6]))
    #expect(!s[3].isPlayableVideo && s[6].isPlayableVideo && !s[7].isPlayableVideo)
}

@Test func bestChoiceNeverPicksActionLink() throws {
    let s = try streams(noticeStreams)
    let list = s.map { (addon: "AIOStreams", stream: $0) }
    let pick = BestChoice.pick(Array(list[2...4]), context: SourceRankContext(primaryLanguage: nil, av1Hardware: false), last: nil, isFailed: { _ in false })
    #expect(pick == nil)
    let real = BestChoice.pick(list, context: SourceRankContext(primaryLanguage: nil, av1Hardware: false), last: nil, isFailed: { _ in false })
    #expect(real?.stream.url == "https://cdn.example/a.mkv" || real?.stream.url == "https://cdn.example/b.mkv")
}

@Test func noticeLogLine() throws {
    let s = try streams(noticeStreams)
    let line = try #require(AddonStreamNotices.logLine(s))
    #expect(line.hasPrefix("AIOStreams Hinweise: 6 ("))
    #expect(line.contains("Fehler „[❌] Comet“: Invalid API key"))
    #expect(line.contains("Statistik „Statistik“") && line.contains("Aktion „🔄 Bibliothek“"))
    #expect(line.contains("+1 weitere"))
    #expect(AddonStreamNotices.logLine(playableStreams(s)) == nil)
    // Long texts are cut.
    let long = StreamItem(name: "[❌] X", description: String(repeating: "a", count: 400), externalUrl: errorProjectPage)
    #expect(AddonStreamNotices.logLine([long])!.count < 260)
}

@Test func searchCountsOnlySourcesAndLogsNoticesOnce() async throws {
    let box = LogBox()
    let a = try installed("https://aio.example/u", #"{"id":"com.aio","name":"AIOStreams","version":"1","resources":["stream"],"types":["movie"],"idPrefixes":["tt"]}"#)
    let c = client(["https://aio.example/u/stream/movie/tt1.json": noticeStreams], box)
    let r = await c.streams(from: [a], type: "movie", id: "tt1", timeout: 5) { p in
        if p.isComplete { #expect(p.statuses.first?.state == .ok(count: 3)) }
    }
    #expect(r.first?.streams.count == 9)
    let lines = box.lines.filter { $0.category == "streams" }
    #expect(lines.count == 1 && lines[0].message.hasPrefix("tt1: AIOStreams Hinweise: 6"))
}

@Test func unreadableStreamEntryIsSkipped() async throws {
    let box = LogBox()
    let a = try installed("https://aio.example/u", #"{"id":"com.aio","name":"AIOStreams","version":"1","resources":["stream"],"types":["movie"]}"#)
    let c = client(["https://aio.example/u/stream/movie/tt1.json": #"{"streams":[{"name":5,"url":"https://a/x"},{"url":"https://a/y.mkv"}]}"#], box)
    let s = try await c.streams(a, type: "movie", id: "tt1")
    #expect(s.map(\.url) == ["https://a/y.mkv"])
    #expect(box.lines.contains { $0.message.contains("1 unlesbarer Eintrag übersprungen") })
}

// MARK: Subtitles (L10, L15 decision)

@Test func errorSubtitlesAreDroppedAndTrackerIsNeverAsked() async throws {
    let box = LogBox()
    let aio = try installed("https://aio.example/u", #"{"id":"com.aio","name":"AIOStreams","version":"1","resources":["subtitles"],"types":["movie"]}"#)
    let tracker = try installed("https://meta.example/cfg", #"{"id":"com.aio.metadata","name":"AIOMetadata","version":"1","resources":["subtitles","meta"],"types":["movie"]}"#)
    let renamed = try installed("https://meta2.example/cfg", #"{"id":"other.id","name":"AIO Metadata (Haus)","version":"1","resources":["subtitles"],"types":["movie"]}"#)
    let c = client([
        "https://aio.example/u/subtitles/movie/tt1.json": """
        {"subtitles":[{"id":"error.os","lang":"[❌] OpenSubtitles - Zeitüberschreitung","url":"\(errorProjectPage)"},
                      {"id":"1","lang":"ger","url":"https://subs.example/1.srt"}]}
        """,
        "https://meta.example/cfg/subtitles/movie/tt1.json": #"{"subtitles":[{"id":"x","lang":"eng","url":"https://subs.example/x.srt"}]}"#,
        "https://meta2.example/cfg/subtitles/movie/tt1.json": #"{"subtitles":[{"id":"y","lang":"eng","url":"https://subs.example/y.srt"}]}"#,
    ], box)
    let subs = await c.subtitles(from: [tracker, aio, renamed], type: "movie", id: "tt1")
    #expect(subs.map(\.id) == ["1"])
    #expect(box.lines.contains { $0.category == "player" && $0.message.contains("1 Fehlereintrag verworfen") && $0.message.contains("Zeitüberschreitung") })
    #expect(!AddonClient.hasSubtitleAddon([tracker, renamed]))
    #expect(AddonClient.hasSubtitleAddon([tracker, aio]))
    #expect(AddonNotices.isErrorSubtitle(id: "7", lang: "eng", url: errorProjectPage + "/issues"))
    #expect(!AddonNotices.isErrorSubtitle(id: "7", lang: "eng", url: "https://subs.example/7.srt"))
}

// MARK: Install links (L6)

@Test func manifestLinkVariants() {
    let cases: [(String, String?, String?)] = [
        (" https://a.b/x/manifest.json ", "https://a.b/x", nil),
        ("https://aio.example/stremio/u/c/manifest.json?v=a,b", "https://aio.example/stremio/u/c", "v=a,b"),
        ("https://aio.example/stremio/u/c/manifest.json?", "https://aio.example/stremio/u/c", nil),
        ("https://aio.example/stremio/u/c/configure", "https://aio.example/stremio/u/c", nil),
        ("https://aio.example/stremio/u/c/configure/?step=2", "https://aio.example/stremio/u/c", nil),
        ("https://aio.example/stremio/configure", "https://aio.example/stremio", nil),
        ("stremio://a.b/x/manifest.json", "https://a.b/x", nil),
        ("Stremio://a.b/x/manifest.json?v=1", "https://a.b/x", "v=1"),
        ("https://a.b/x/manifest.json#top", "https://a.b/x", nil),
        ("https://web.example/#/addons?addon=https%3A%2F%2Fa.b%2Fx%2Fmanifest.json%3Fv%3D2", "https://a.b/x", "v=2"),
        ("https://a.b/x/", "https://a.b/x", nil),
        ("ftp://a", nil, nil),
        ("https://", nil, nil),
    ]
    for (raw, base, query) in cases {
        let p = AddonClient.parseManifest(raw)
        #expect(p?.base == base, "\(raw)")
        #expect(p?.query == query, "\(raw)")
        #expect(AddonClient.baseURL(fromManifest: raw) == base, "\(raw)")
    }
}

@Test func manifestQueryTravelsWithEveryRequest() async throws {
    let json = #"{"id":"com.aio","name":"AIOStreams","version":"1","resources":["stream"],"types":["movie"],"catalogs":[{"type":"movie","id":"top"}]}"#
    let c = AddonClient(http: FakeHTTP(routes: [
        "https://aio.example/u/manifest.json?v=a,b": json,
        "https://aio.example/u/stream/movie/tt1.json?v=a,b": #"{"streams":[{"url":"https://cdn.example/a.mkv"}]}"#,
        "https://cfg.example/x/manifest.json": json,
    ]))
    let a = try await c.install(manifestURL: "stremio://aio.example/u/manifest.json?v=a,b")
    #expect(a.manifestURL == "https://aio.example/u/manifest.json?v=a,b")
    #expect(a.baseURL == "https://aio.example/u" && a.manifestQuery == "v=a,b")
    #expect(try await c.streams(a, type: "movie", id: "tt1").count == 1)
    let u = try c.resourceURL(a, "catalog", type: "movie", id: "top", extra: ["skip": "20"])
    #expect(u.absoluteString == "https://aio.example/u/catalog/movie/top/skip=20.json?v=a,b")
    // A configure-page link installs the manifest next to it.
    let b = try await c.install(manifestURL: "https://cfg.example/x/configure")
    #expect(b.manifestURL == "https://cfg.example/x/manifest.json")
}

// MARK: Metadata addon choice (L16)

private func metaAddon(_ id: String, name: String = "M", prefixes: [String]?) -> InstalledAddon {
    InstalledAddon(manifestURL: "https://\(id).example/manifest.json", manifest: AddonManifest(
        id: id, name: name, version: "1", resources: [AddonResource(name: "meta")], types: ["movie", "series"], idPrefixes: prefixes))
}

@Test func metadataAddonPrefersNamedPrefixes() {
    let wildcard = metaAddon("com.aio", name: "AIOStreams", prefixes: nil)
    let named = metaAddon("tt.meta", prefixes: ["tt"])
    let aiom = metaAddon("com.aio.metadata", name: "AIOMetadata", prefixes: nil)
    let renamed = metaAddon("own.meta", name: "AIO Metadata", prefixes: [])
    #expect(MetaImageChoice.metadataAddon(in: [wildcard, named], type: "movie", id: "tt1")?.manifest.id == "tt.meta")
    #expect(MetaImageChoice.metadataAddon(in: [wildcard, aiom], type: "movie", id: "tt1")?.manifest.id == "com.aio.metadata")
    #expect(MetaImageChoice.metadataAddon(in: [wildcard, renamed], type: "movie", id: "tt1")?.manifest.id == "own.meta")
    #expect(MetaImageChoice.metadataAddon(in: [wildcard], type: "movie", id: "tt1")?.manifest.id == "com.aio")
    // List order within the preferred group.
    #expect(MetaImageChoice.metadataAddon(in: [wildcard, aiom, named], type: "movie", id: "tt1")?.manifest.id == "com.aio.metadata")
    #expect(MetaImageChoice.metadataAddon(in: [named, aiom], type: "movie", id: "tt1")?.manifest.id == "tt.meta")
}

// MARK: Episodic types (L4 helper)

@Test func episodicTypes() {
    #expect(ContentKind.isEpisodic(type: "series") && ContentKind.isEpisodic(type: "anime"))
    #expect(ContentKind.isEpisodic(type: "Anime.Series") && !ContentKind.isEpisodic(type: "anime.movie"))
    #expect(!ContentKind.isEpisodic(type: "movie") && !ContentKind.isEpisodic(type: "movie", hasVideos: true))
    #expect(!ContentKind.isEpisodic(type: "tv") && ContentKind.isEpisodic(type: "tv", hasVideos: true))
    let src = RowCatalog.addonSource(addon: try! manifest(animeManifest), catalog: CatalogDescriptor(type: "anime", id: "mal.top"))
    #expect(src.mediaType == .series)
    #expect(RowCatalog.addonSource(addon: try! manifest(animeManifest), catalog: CatalogDescriptor(type: "anime.movie", id: "m")).mediaType == .movie)
}
