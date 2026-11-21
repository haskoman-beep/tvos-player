import Foundation
import Testing
@testable import PlayerCore

@Test func readyPackagesHaveUniqueIDsAndDEFilters() {
    let all = ReadyPackages.all
    let ids = all.flatMap { c in [c.id] + c.folders.flatMap { f in [f.id] + f.sources.map(\.id) } }
    #expect(Set(ids).count == ids.count)
    let netflix = try! #require(ReadyPackages.streamingDE.folders.first { $0.title == "Netflix" })
    #expect(netflix.sources.count == 4)
    guard case .tmdbDiscover(let f) = netflix.sources[0].kind else { Issue.record("kind"); return }
    #expect(f["with_watch_providers"] == "8" && f["watch_region"] == "DE")
    // Serien-Genres nutzen TV-IDs (Action = 10759), Horror hat keine Serienquelle.
    let action = ReadyPackages.genreCollection.folders.first { $0.title == "Action" }!
    guard case .tmdbDiscover(let tv) = action.sources[1].kind else { Issue.record("kind"); return }
    #expect(tv["with_genres"] == "10759" && action.sources[1].mediaType == .series)
    #expect(ReadyPackages.genreCollection.folders.first { $0.title == "Horror" }!.sources.count == 1)
}

@Test func tmdbLinkParsing() {
    let l = TMDBLink.source(from: "https://www.themoviedb.org/list/8123-best-heist-films?language=de")
    #expect(l?.kind == .tmdbList(id: "8123") && l?.title == "Best Heist Films")
    #expect(TMDBLink.source(from: " https://www.themoviedb.org/collection/86311-the-avengers-collection ")?.kind == .tmdbCollection(id: "86311"))
    #expect(TMDBLink.source(from: "company:420")?.kind == .tmdbCompany(id: "420"))
    #expect(TMDBLink.source(from: "list:77", title: "Meine")?.title == "Meine")
    #expect(TMDBLink.source(from: "https://www.themoviedb.org/movie/550") == nil)
    #expect(TMDBLink.source(from: "quatsch") == nil)
}

@Test func searchSkipsPeople() async throws {
    let http = RecordingHTTP(#"{"results":[{"id":1,"media_type":"movie","title":"Dune"},{"id":2,"media_type":"person","name":"X"},{"id":3,"media_type":"tv","name":"Dune: Prophecy"}]}"#)
    let r = try await TMDBClient(apiKey: "K", http: http).search("Dune ")
    #expect(r.map(\.id) == ["tmdb:1", "tmdb:3"] && r[1].type == "series")
    let u = http.urls[0].absoluteString
    #expect(u.contains("/search/multi") && u.contains("query=Dune") && !u.contains("Dune%20"))
    #expect(try await TMDBClient(apiKey: "K", http: http).search("  ").isEmpty)
}

private let film = MetaPreview(id: "tt1", type: "movie", name: "Film")
private let serie = MetaPreview(id: "tt9", type: "series", name: "Serie")

@Test func progressResumeAndFinish() {
    var b = ProgressBook()
    b.record(id: "tt1", item: film, position: 30, duration: 6000)
    #expect(b.resumePosition(for: "tt1") == nil)            // unter 1 min: von vorn
    b.record(id: "tt1", item: film, position: 1200, duration: 6000)
    #expect(b.resumePosition(for: "tt1") == 1200)
    b.record(id: "tt1", item: film, position: 5600, duration: 6000)
    #expect(b.isWatched("tt1") && b.resumePosition(for: "tt1") == nil)
    #expect(b.continueWatching().isEmpty)
    b.record(id: "tt1", item: film, position: .nan, duration: 6000)  // ungültig: ignoriert
    #expect(b.isWatched("tt1"))
}

@Test func continueWatchingNewestFirstOnePerSeries() {
    var b = ProgressBook()
    let t0 = Date(timeIntervalSince1970: 1000)
    b.record(id: "tt9:1:1", item: serie, season: 1, episode: 1, position: 600, duration: 2400, now: t0)
    b.record(id: "tt1", item: film, position: 600, duration: 6000, now: t0.addingTimeInterval(10))
    b.record(id: "tt9:1:2", item: serie, season: 1, episode: 2, position: 900, duration: 2400, now: t0.addingTimeInterval(20))
    let c = b.continueWatching()
    #expect(c.map(\.id) == ["tt9:1:2", "tt1"])
}

@Test func progressStoreRoundTrip() throws {
    let s = ProgressStore(directory: tempDir())
    let p = UUID()
    var b = ProgressBook()
    b.record(id: "tt1", item: film, position: 1200, duration: 6000, now: Date(timeIntervalSince1970: 5000))
    try s.save(b, profile: p)
    #expect(s.load(profile: p) == b)
    #expect(s.load(profile: UUID()).entries.isEmpty)
}
