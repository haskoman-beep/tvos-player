import Foundation
import Testing
@testable import PlayerCore

final class RecordingHTTP: HTTPFetching, @unchecked Sendable {
    var urls: [URL] = []
    let body: String
    init(_ body: String) { self.body = body }
    func data(from url: URL) async throws -> Data { urls.append(url); return Data(body.utf8) }
}

@Test func discoverURLAndResults() async throws {
    let http = RecordingHTTP(#"{"results":[{"id":1,"title":"A","poster_path":"/a.jpg","release_date":"2025-03-01","vote_average":7.25},{"id":2,"title":"B"}]}"#)
    let c = TMDBClient(apiKey: "KEY", http: http)
    let src = CatalogSource(id: "s", title: "Neu", kind: .tmdbDiscover(filters: ["with_watch_providers": "8|1796", "watch_region": "DE"]), mediaType: .movie)
    let items = try await c.items(for: src)
    let u = try #require(http.urls.first?.absoluteString)
    #expect(u.hasPrefix("https://api.themoviedb.org/3/discover/movie?"))
    #expect(u.contains("with_watch_providers=8%7C1796"))
    #expect(u.contains("watch_region=DE") && u.contains("language=de-DE") && u.contains("page=1"))
    #expect(items.count == 2)
    #expect(items[0].id == "tmdb:1" && items[0].type == "movie")
    #expect(items[0].poster == "https://image.tmdb.org/t/p/w500/a.jpg")
    #expect(items[0].releaseInfo == "2025")
}

@Test func bothQueriesMovieAndTV() async throws {
    let http = RecordingHTTP(#"{"results":[{"id":1,"name":"S"}]}"#)
    let src = CatalogSource(id: "s", title: "x", kind: .tmdbDiscover(filters: [:]), mediaType: .both)
    let items = try await TMDBClient(apiKey: "K", http: http).items(for: src)
    #expect(http.urls.count == 2 && items.map(\.type) == ["movie", "series"])
}

@Test func imdbIDLookup() async throws {
    let http = RecordingHTTP(#"{"imdb_id":"tt0903747"}"#)
    let id = try await TMDBClient(apiKey: "K", http: http).imdbID(tmdbID: 1396, type: .series)
    #expect(id == "tt0903747")
    #expect(http.urls[0].path == "/3/tv/1396/external_ids")
}

@Test func missingKeyThrows() async {
    await #expect(throws: TMDBError.missingKey) {
        try await TMDBClient(apiKey: "", http: RecordingHTTP("{}")).items(for: .init(id: "x", title: "x", kind: .tmdbList(id: "1"), mediaType: .movie))
    }
}

// A-B-10: a kit row with releaseStatus "released" is parsed on day 1; fetching on day 2 must use day 2, not the
// date baked in at parse time. The stored filter keeps the literal date (Build 3 reads it unchanged).
private let abDay1 = Date(timeIntervalSince1970: 1_795_262_400)   // 2026-11-21 12:00 UTC
private let abDay2 = abDay1.addingTimeInterval(86_400)            // 2026-11-22 12:00 UTC
private func utcCalendar() -> Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!; return c }

private func releasedKitSource(type: String = "movie") throws -> CatalogSource {
    let json = #"{"exportType":"fusionWidgets","widgets":[{"id":"w","title":"Neu","type":"row.classic","dataSource":{"kind":"tmdbDiscover","payload":{"type":"\#(type)","includeGenres":[28],"releaseStatus":"released"}}}]}"#
    let c = try FusionImport.parse(Data(json.utf8), sourceKey: "s", now: abDay1)
    guard case .list(let s) = try #require(c.rows.first).body else { throw TMDBError.unsupported }
    return s
}

@Test func kitReleasedFetchOnDay2UsesDay2() async throws {
    let src = try releasedKitSource()
    guard case .tmdbDiscover(let f) = src.kind else { Issue.record("kein Discover"); return }
    #expect(f["primary_release_date.lte"] == "2026-11-21")   // stored format unchanged
    let http = RecordingHTTP(#"{"results":[]}"#)
    let c = TMDBClient(apiKey: "K", http: http)
    _ = try await c.items(for: src, now: abDay2, calendar: utcCalendar())
    _ = try await c.page(for: src, page: 2, now: abDay2, calendar: utcCalendar())
    let tv = try releasedKitSource(type: "tv")
    _ = try await c.items(for: tv, now: abDay2, calendar: utcCalendar())
    let u = http.urls.map(\.absoluteString)
    #expect(u.count == 3)
    #expect(u[0].contains("primary_release_date.lte=2026-11-22") && !u[0].contains("2026-11-21"))
    #expect(u[1].contains("primary_release_date.lte=2026-11-22") && u[1].contains("page=2"))
    #expect(u[2].contains("first_air_date.lte=2026-11-22"))
}

@Test func ownDiscoverRowKeepsLiteralDate() async throws {
    let http = RecordingHTTP(#"{"results":[]}"#)
    let src = CatalogSource(id: "own", title: "x", kind: .tmdbDiscover(filters: ["primary_release_date.lte": "1999-12-31"]), mediaType: .movie)
    _ = try await TMDBClient(apiKey: "K", http: http).items(for: src, now: abDay2, calendar: utcCalendar())
    #expect(http.urls[0].absoluteString.contains("primary_release_date.lte=1999-12-31"))
}

// A-B-10 review M2: a movie with a release channel uses `release_date.lte`; it gets the request day too.
@Test func kitReleasedWithChannelUsesReleaseDateKey() async throws {
    let json = #"{"exportType":"fusionWidgets","widgets":[{"id":"w","title":"Neu","type":"row.classic","dataSource":{"kind":"tmdbDiscover","payload":{"type":"movie","releaseChannel":"digital","releaseStatus":"released"}}}]}"#
    let c = try FusionImport.parse(Data(json.utf8), sourceKey: "s", now: abDay1)
    guard case .list(let src) = try #require(c.rows.first).body else { Issue.record("keine Liste"); return }
    let http = RecordingHTTP(#"{"results":[]}"#)
    _ = try await TMDBClient(apiKey: "K", http: http).items(for: src, now: abDay2, calendar: utcCalendar())
    let u = try #require(http.urls.first?.absoluteString)
    #expect(u.contains("release_date.lte=2026-11-22") && !u.contains("primary_release_date"))
}

// A-B-10 review M2: the cut-off is the day in the given (local) calendar, not the UTC day.
@Test func kitReleasedUsesLocalDayNotUTC() {
    var kiritimati = Calendar(identifier: .gregorian)
    kiritimati.timeZone = TimeZone(identifier: "Pacific/Kiritimati")!   // UTC+14: 2026-11-21 12:00 UTC is 22 Nov there
    let f = FusionImport.requestFilters(["primary_release_date.lte": "2026-11-21"], sourceID: "fusion.s.w", now: abDay1,
                                        calendar: kiritimati)
    #expect(f["primary_release_date.lte"] == "2026-11-22")
}
