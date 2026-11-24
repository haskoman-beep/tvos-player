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
    #expect(s.load(profile: UUID())?.entries.isEmpty == true)
}

@Test func episodeOrderAndNext() {
    let vids = [MetaVideo(id: "a", season: 2, episode: 1), MetaVideo(id: "b", season: 1, episode: 2),
                MetaVideo(id: "c", season: 0, episode: 1), MetaVideo(id: "d", season: 1, episode: 1),
                MetaVideo(id: "e", season: 1, episode: 2)]
    let l = EpisodeRef.list(from: vids)
    #expect(l.map { [$0.season, $0.episode] } == [[1, 1], [1, 2], [2, 1]])
    #expect(EpisodeRef.next(after: 1, 2, in: l) == EpisodeRef(season: 2, episode: 1))
    #expect(EpisodeRef.next(after: 2, 1, in: l) == nil)
}

// Task 3.5 (W-B-10): after a special the next episode is the next special, never S1E1.
@Test func nextAfterSpecialWithoutSpecialsInListIsNone() {
    let l = [EpisodeRef(season: 1, episode: 1), EpisodeRef(season: 1, episode: 2)]
    #expect(EpisodeRef.next(after: 0, 3, in: l) == nil)
}

@Test func nextAfterSpecialStaysInSeasonZero() {
    // Fix round 1: the list the app builds while a special plays (`list(from:includeSpecials:)`).
    let vids = [MetaVideo(id: "s2", season: 0, episode: 2), MetaVideo(id: "s5", season: 0, episode: 5),
                MetaVideo(id: "a", season: 1, episode: 1), MetaVideo(id: "b", season: 1, episode: 2)]
    let l = EpisodeRef.list(from: vids, includeSpecials: true)
    #expect(l.map { [$0.season, $0.episode] } == [[0, 2], [0, 5], [1, 1], [1, 2]])
    #expect(EpisodeRef.next(after: 0, 3, in: l) == EpisodeRef(season: 0, episode: 5))
    #expect(EpisodeRef.next(after: 0, 5, in: l) == nil)
    // Regular episodes are unchanged, also on this list.
    #expect(EpisodeRef.next(after: 1, 1, in: l) == EpisodeRef(season: 1, episode: 2))
}

@Test func episodeListKeepsSpecialsOutByDefault() {
    // Fix round 1: normal playback never sees specials; up-next after a regular episode stays regular.
    let vids = [MetaVideo(id: "s1", season: 0, episode: 1), MetaVideo(id: "a", season: 1, episode: 1),
                MetaVideo(id: "b", season: 1, episode: 2)]
    #expect(EpisodeRef.list(from: vids).allSatisfy { $0.season > 0 })
    #expect(EpisodeRef.list(from: vids, includeSpecials: false).count == 2)
    #expect(EpisodeRef.next(after: 1, 2, in: EpisodeRef.list(from: vids)) == nil)
    // The app's choice: specials only while the playing episode is one.
    #expect(EpisodeRef.includesSpecials(playingSeason: 0))
    #expect(!EpisodeRef.includesSpecials(playingSeason: 3))
    #expect(!EpisodeRef.includesSpecials(playingSeason: nil))
}

@Test func nextStreamPrefersBingeGroup() {
    func s(_ u: String, _ g: String?) -> StreamItem { StreamItem(name: u, url: u, behaviorHints: g.map { StreamBehaviorHints(bingeGroup: $0) }) }
    let list = [StreamItem(name: "t", infoHash: "x"), s("https://a", "g1"), s("https://b", "g2")]
    #expect(nextEpisodeStream(list, bingeGroup: "g2")?.url == "https://b")
    #expect(nextEpisodeStream(list, bingeGroup: "nix")?.url == "https://a")
    #expect(nextEpisodeStream([], bingeGroup: nil) == nil)
}

@Test func nextUpShowsInContinueButKeepsRealProgress() {
    var b = ProgressBook()
    let t0 = Date(timeIntervalSince1970: 1000)
    b.record(id: "tt9:1:1", item: serie, season: 1, episode: 1, position: 2300, duration: 2400, now: t0)
    b.recordNextUp(id: "tt9:1:2", item: serie, season: 1, episode: 2, now: t0.addingTimeInterval(1))
    #expect(b.continueWatching().map(\.id) == ["tt9:1:2"])
    #expect(b.resumePosition(for: "tt9:1:2") == nil)
    #expect(b.latest(forItem: "tt9")?.season == 1 && b.latest(forItem: "tt9")?.episode == 2)
    b.record(id: "tt9:1:2", item: serie, season: 1, episode: 2, position: 500, duration: 2400, now: t0.addingTimeInterval(2))
    b.recordNextUp(id: "tt9:1:2", item: serie, season: 1, episode: 2, now: t0.addingTimeInterval(3))
    #expect(b.resumePosition(for: "tt9:1:2") == 500 && b.entries["tt9:1:2"]?.nextUp == nil)
}
