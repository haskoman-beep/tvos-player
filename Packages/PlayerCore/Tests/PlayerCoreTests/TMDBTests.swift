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
