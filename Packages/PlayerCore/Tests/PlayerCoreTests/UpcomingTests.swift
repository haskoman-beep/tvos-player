import Foundation
import Testing
@testable import PlayerCore

private var berlin: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Berlin")!
    return c
}

/// Fr 21.11.2026, 23:30 Berlin (spät am Abend, damit Zeitzonenfehler auffallen).
private var friday: Date {
    berlin.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 23, minute: 30))!
}

private func ep(_ series: String, _ date: String, s: Int = 1, e: Int = 1) -> UpcomingEpisode {
    UpcomingEpisode(seriesID: "tt-" + series, seriesName: series, season: s, episode: e, airDate: date)
}

@Test func upcomingGroupsYesterdayTodayTomorrowDate() {
    let eps = [ep("Zeta", "2026-11-21"), ep("Alpha", "2026-11-21", e: 2), ep("Mitte", "2026-11-20"),
               ep("Beta", "2026-11-22"), ep("Gamma", "2026-11-25"), ep("Alpha", "2026-11-21", e: 2)]
    let d = Upcoming.days(eps, today: friday, calendar: berlin)
    #expect(d.map(\.label) == ["Gestern", "Heute", "Morgen", "Mi 25.11."])
    #expect(d[1].items.map(\.seriesName) == ["Alpha", "Zeta"])   // sortiert, Doppelte weg
    #expect(Upcoming.today(eps, today: friday, calendar: berlin).count == 2)
    #expect(ep("X", "2026-11-25", s: 2, e: 5).label == "S2 F5")
}

@Test func upcomingDropsOutOfRange() {
    let eps = [ep("Alt", "2026-11-19"), ep("Grenze", "2026-12-05"), ep("Zu spät", "2026-12-06"), ep("Kaputt", "bald")]
    let d = Upcoming.days(eps, today: friday, calendar: berlin)
    #expect(d.map(\.label) == ["Sa 5.12."])
    #expect(d[0].items.map(\.seriesName) == ["Grenze"])
    #expect(Upcoming.lastDay(today: friday, calendar: berlin) == "2026-12-05")
}

@Test func seriesIDsDedupContinueFirstLimit() {
    let show = MetaPreview(id: "tt1", type: "series", name: "Serie 1")
    let film = MetaPreview(id: "tt2", type: "movie", name: "Film")
    let cw = [WatchProgress(id: "tt1:1:2", item: show, season: 1, episode: 2, position: 100, duration: 1000),
              WatchProgress(id: "tt2", item: film, position: 100, duration: 1000)]
    let wl = [MetaPreview(id: "tmdb:5", type: "series", name: "B"), show, film,
              MetaPreview(id: "tt9", type: "series", name: "C")]
    #expect(Upcoming.seriesIDs(continueWatching: cw, watchlist: wl) == ["tt1", "tmdb:5", "tt9"])
    #expect(Upcoming.seriesIDs(continueWatching: cw, watchlist: wl, limit: 2) == ["tt1", "tmdb:5"])
    let many = (0..<80).map { MetaPreview(id: "tt\($0 + 100)", type: "series", name: "S\($0)") }
    #expect(Upcoming.seriesIDs(continueWatching: [], watchlist: many).count == 50)
}

@Test func historyFinishedNewestFirst() {
    var b = ProgressBook()
    let a = MetaPreview(id: "tt1", type: "movie", name: "A")
    let s = MetaPreview(id: "tt2", type: "series", name: "S")
    let c = MetaPreview(id: "tt3", type: "movie", name: "C")
    let t0 = Date(timeIntervalSince1970: 1_000_000)
    b.record(id: "tt1", item: a, position: 990, duration: 1000, now: t0)
    b.record(id: "tt2:1:1", item: s, season: 1, episode: 1, position: 990, duration: 1000, now: t0.addingTimeInterval(10))
    b.record(id: "tt2:1:2", item: s, season: 1, episode: 2, position: 990, duration: 1000, now: t0.addingTimeInterval(20))
    b.record(id: "tt3", item: c, position: 300, duration: 1000, now: t0.addingTimeInterval(30))   // nicht fertig
    let h = b.history()
    #expect(h.map(\.id) == ["tt2:1:2", "tt1"])
    #expect(b.history(limit: 1).map(\.item.id) == ["tt2"])
}

@Test func parseNextEpisodes() async throws {
    let show = #"""
    {"id":42,"name":"Die Serie","poster_path":"/p.jpg","backdrop_path":"/b.jpg",
     "last_episode_to_air":{"season_number":2,"episode_number":4,"name":"Vorher","air_date":"2026-11-20","still_path":"/s4.jpg"},
     "next_episode_to_air":{"season_number":2,"episode_number":5,"name":"Episode 5","air_date":"2026-11-27"}}
    """#
    let parsed = TMDBClient.parseNextEpisodes(Data(show.utf8))
    #expect(parsed.map(\.isNext) == [false, true])
    let next = parsed[1].episode
    #expect(next.seriesID == "tmdb:42" && next.seriesName == "Die Serie")
    #expect(next.season == 2 && next.episode == 5 && next.airDate == "2026-11-27" && next.title == nil)
    #expect(next.poster == "https://image.tmdb.org/t/p/w500/p.jpg")
    #expect(parsed[0].episode.title == "Vorher" && parsed[0].episode.still == "https://image.tmdb.org/t/p/w500/s4.jpg")

    // Leerer Fall: beendete Serie ohne Folgendaten, kaputte Antwort.
    #expect(TMDBClient.parseNextEpisodes(Data(#"{"id":7,"name":"Ende","next_episode_to_air":null}"#.utf8)).isEmpty)
    #expect(TMDBClient.parseNextEpisodes(Data("[]".utf8)).isEmpty)

    let season = #"{"episodes":[{"season_number":2,"episode_number":5,"name":"Fünf","air_date":"2026-11-27"},{"season_number":2,"episode_number":6,"name":"Sechs","air_date":"2026-12-04"},{"season_number":2,"episode_number":7,"name":"Ohne Datum","air_date":null}]}"#
    let eps = TMDBClient.parseSeasonEpisodes(Data(season.utf8), like: next)
    #expect(eps.map(\.episode) == [5, 6] && eps[0].seriesName == "Die Serie")

    // nextEpisodes: Serie + laufende Staffel, ohne Doppelte; Staffel nur, wenn die nächste Folge im Zeitraum liegt.
    let http = RecordingHTTP(show)
    let all = try await TMDBClient(apiKey: "K", http: http).nextEpisodes(tmdbID: 42, through: "2026-12-05")
    #expect(http.urls.map(\.path) == ["/3/tv/42", "/3/tv/42/season/2"])
    #expect(all.map(\.episode) == [4, 5])   // Testantwort hat keine "episodes" → nur Serie
    let late = RecordingHTTP(show)
    _ = try await TMDBClient(apiKey: "K", http: late).nextEpisodes(tmdbID: 42, through: "2026-11-25")
    #expect(late.urls.count == 1)
}
