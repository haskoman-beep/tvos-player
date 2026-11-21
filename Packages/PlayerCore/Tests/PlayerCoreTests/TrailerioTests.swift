import Foundation
import Testing
@testable import PlayerCore

/// Antwort von trailerio.cc/de für „The Matrix“ (Aufbau wie real abgerufen, Adressen gekürzt).
private let matrixDE = #"""
{"meta":{"id":"tt0133093","type":"movie","name":"The Matrix","links":[
 {"trailers":"https://video.example.net/video.mp4?cmd=6&fmt=4","provider":"Plex 1080p"},
 {"trailers":"https://play-edge.example.com/hls/playlist.m3u8?cc=DE&l=de-DE","provider":"⭐ Apple TV 4K DV Atmos"},
 {"trailers":"https://cdn.example.net/720p-t-the-matrix.mp4","provider":"MUBI 720p"},
 {"trailers":"https://cdn.example.net/720p-t-the-matrix.mp4","provider":"MUBI 720p"},
 {"trailers":"javascript:alert(1)","provider":"kaputt"},
 {"provider":"ohne Adresse"}]}}
"""#

@Test func trailerioMetaURLLanguages() {
    #expect(TrailerioClient.metaURL(imdb: "tt0133093", series: false, language: "de")?.absoluteString
            == "https://trailerio.cc/de/meta/movie/tt0133093.json")
    #expect(TrailerioClient.metaURL(imdb: "tt0903747", series: true, language: "de-DE")?.absoluteString
            == "https://trailerio.cc/de/meta/series/tt0903747.json")
    // Englisch (und nicht unterstützte Sprachen) liegen an der Wurzel.
    #expect(TrailerioClient.metaURL(imdb: "tt0133093", series: false, language: "en")?.absoluteString
            == "https://trailerio.cc/meta/movie/tt0133093.json")
    #expect(TrailerioClient.metaURL(imdb: "tt0133093", series: false, language: "nl")?.absoluteString
            == "https://trailerio.cc/meta/movie/tt0133093.json")
    // Folgen-ID → Serien-ID; Nicht-IMDb-IDs ergeben keine Adresse.
    #expect(TrailerioClient.metaURL(imdb: "tt0903747:1:2", series: true, language: "de")?.path == "/de/meta/series/tt0903747.json")
    #expect(TrailerioClient.metaURL(imdb: "tmdb:603", series: false, language: "de") == nil)
    #expect(TrailerioClient.metaURL(imdb: "tt", series: false, language: "de") == nil)
}

@Test func trailerioParseOrdersRecommendedFirst() throws {
    let list = TrailerioClient.parse(Data(matrixDE.utf8))
    #expect(list.map(\.provider) == ["Apple TV 4K DV Atmos", "Plex 1080p", "MUBI 720p"])
    let first = try #require(list.first)
    #expect(first.isRecommended && first.isHLS && first.height == 2160)
    #expect(!list[1].isHLS && list[1].height == 1080 && !list[1].isRecommended)
    #expect(list[2].height == 720)
    let s = first.stream
    #expect(s.client == "trailerio" && s.isHLS && s.headers.isEmpty && s.url == first.url)
}

@Test func trailerioParseEmptyAndBroken() {
    #expect(TrailerioClient.parse(Data(#"{"meta":{"id":"tt1","links":[]}}"#.utf8)).isEmpty)
    #expect(TrailerioClient.parse(Data(#"{"meta":{"id":"tt1"}}"#.utf8)).isEmpty)
    #expect(TrailerioClient.parse(Data("kein json".utf8)).isEmpty)
    #expect(TrailerioClient.height("Plex") == nil && TrailerioClient.height("IMDb 480p") == 480)
}

@Test func trailerioFetchUsesProfileLanguage() async {
    let http = RecordingHTTP(matrixDE)
    let list = await TrailerioClient(http: http).trailers(imdb: "tt0133093", series: false, language: "de")
    #expect(http.urls.map(\.absoluteString) == ["https://trailerio.cc/de/meta/movie/tt0133093.json"])
    #expect(list.count == 3 && list[0].isRecommended)
}

@Test func trailerioFetchErrorGivesEmpty() async {
    let list = await TrailerioClient(http: FakeHTTP(routes: [:])).trailers(imdb: "tt0133093", series: false, language: "de")
    #expect(list.isEmpty)
}

private struct SlowHTTP: HTTPFetching {
    func data(from url: URL) async throws -> Data {
        try await Task.sleep(for: .seconds(10))
        return Data(matrixDE.utf8)
    }
}

@Test func trailerioTimeoutFallsBackQuickly() async {
    let start = ContinuousClock.now
    let list = await TrailerioClient(http: SlowHTTP(), timeout: .milliseconds(100))
        .trailers(imdb: "tt0133093", series: false, language: "de")
    #expect(list.isEmpty)
    #expect(ContinuousClock.now - start < .seconds(3))
}
