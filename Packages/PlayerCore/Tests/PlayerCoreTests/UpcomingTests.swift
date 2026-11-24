import Foundation
import Testing
@testable import PlayerCore

private var berlin: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Berlin")!
    return c
}

/// Sa 21.11.2026, 23:30 Berlin (spät am Abend, damit Zeitzonenfehler auffallen).
private var saturday: Date {
    berlin.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 23, minute: 30))!
}

private func ep(_ series: String, _ date: String, s: Int = 1, e: Int = 1) -> UpcomingEpisode {
    UpcomingEpisode(seriesID: "tt-" + series, seriesName: series, season: s, episode: e, airDate: date)
}

@Test func upcomingGroupsYesterdayTodayTomorrowDate() {
    let eps = [ep("Zeta", "2026-11-21"), ep("Alpha", "2026-11-21", e: 2), ep("Mitte", "2026-11-20"),
               ep("Beta", "2026-11-22"), ep("Gamma", "2026-11-25"), ep("Alpha", "2026-11-21", e: 2)]
    let d = Upcoming.days(eps, today: saturday, calendar: berlin)
    #expect(d.map(\.label) == ["Gestern", "Heute", "Morgen", "Mi 25.11."])
    #expect(d[1].items.map(\.seriesName) == ["Alpha", "Zeta"])   // sortiert, Doppelte weg
    #expect(Upcoming.today(eps, today: saturday, calendar: berlin).count == 2)
    #expect(ep("X", "2026-11-25", s: 2, e: 5).label == "S2 F5")
}

@Test func upcomingDropsOutOfRange() {
    let eps = [ep("Alt", "2026-11-19"), ep("Grenze", "2026-12-05"), ep("Zu spät", "2026-12-06"), ep("Kaputt", "bald")]
    let d = Upcoming.days(eps, today: saturday, calendar: berlin)
    #expect(d.map(\.label) == ["Sa 5.12."])
    #expect(d[0].items.map(\.seriesName) == ["Grenze"])
    #expect(Upcoming.lastDay(today: saturday, calendar: berlin) == "2026-12-05")
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

/// Antwortet je URL-Pfad (für Serie + Staffel in einem Ablauf).
final class PathHTTP: HTTPFetching, @unchecked Sendable {
    var urls: [URL] = []
    let bodies: [String: String]
    init(_ bodies: [String: String]) { self.bodies = bodies }
    func data(from url: URL) async throws -> Data {
        urls.append(url)
        guard let b = bodies[url.path] else { throw URLError(.fileDoesNotExist) }
        return Data(b.utf8)
    }
}

private let seasonTwo = #"{"episodes":[{"season_number":2,"episode_number":4,"name":"Vorher","air_date":"2026-11-20"},{"season_number":2,"episode_number":5,"name":"Fünf","air_date":"2026-11-27"},{"season_number":2,"episode_number":6,"name":"Sechs","air_date":"2026-12-04"}]}"#

@Test func nextEpisodesMergesSeasonAndDedupes() async throws {
    let show = #"""
    {"id":42,"name":"Die Serie",
     "last_episode_to_air":{"season_number":2,"episode_number":4,"name":"Vorher","air_date":"2026-11-20"},
     "next_episode_to_air":{"season_number":2,"episode_number":5,"name":"Episode 5","air_date":"2026-11-27"}}
    """#
    let http = PathHTTP(["/3/tv/42": show, "/3/tv/42/season/2": seasonTwo])
    let eps = try await TMDBClient(apiKey: "K", http: http).nextEpisodes(tmdbID: 42, from: "2026-11-20", through: "2026-12-05")
    #expect(eps.map(\.episode) == [4, 5, 6])          // 4 und 5 nicht doppelt
    #expect(eps.allSatisfy { $0.seriesName == "Die Serie" })
    #expect(eps[1].title == nil)                         // aus /tv/{id} ("Episode 5"), Staffel-Duplikat verworfen
}

@Test func nextEpisodesWithoutNextUsesRecentLastSeason() async throws {
    let show = #"{"id":42,"name":"Die Serie","next_episode_to_air":null,"last_episode_to_air":{"season_number":2,"episode_number":4,"air_date":"2026-11-20"}}"#
    let http = PathHTTP(["/3/tv/42": show, "/3/tv/42/season/2": seasonTwo])
    let client = TMDBClient(apiKey: "K", http: http)
    let eps = try await client.nextEpisodes(tmdbID: 42, from: "2026-11-20", through: "2026-12-05")
    #expect(http.urls.map(\.path) == ["/3/tv/42", "/3/tv/42/season/2"])
    #expect(eps.map(\.episode) == [4, 5, 6])
    // Letzte Folge liegt vor gestern → keine Staffel.
    let old = PathHTTP(["/3/tv/42": show])
    let only = try await TMDBClient(apiKey: "K", http: old).nextEpisodes(tmdbID: 42, from: "2026-11-21", through: "2026-12-06")
    #expect(old.urls.count == 1 && only.map(\.episode) == [4])
}

@Test func emptyDaysAndHistory() {
    #expect(Upcoming.days([], today: saturday, calendar: berlin).isEmpty)
    #expect(Upcoming.today([], today: saturday, calendar: berlin).isEmpty)
    #expect(ProgressBook().history().isEmpty)
}

@Test func upcomingRangeAcrossDSTChange() {
    // 27.03.2027 Sa; Sommerzeit beginnt So 28.03.2027 in Berlin (Tag mit 23 h).
    let today = berlin.date(from: DateComponents(year: 2027, month: 3, day: 27, hour: 0, minute: 30))!
    let eps = [ep("Gestern", "2027-03-26"), ep("Morgen", "2027-03-28"), ep("Danach", "2027-03-29"),
               ep("Grenze", "2027-04-10"), ep("Zu spät", "2027-04-11")]
    let d = Upcoming.days(eps, today: today, calendar: berlin)
    #expect(d.map(\.label) == ["Gestern", "Morgen", "Mo 29.3.", "Sa 10.4."])
    #expect(Upcoming.lastDay(today: today, calendar: berlin) == "2027-04-10")
    #expect(Upcoming.firstDay(today: today, calendar: berlin) == "2027-03-26")
}

@Test func localCalendarIsGregorian() {
    #expect(Upcoming.localCalendar.identifier == .gregorian)
    var buddhist = Calendar(identifier: .buddhist); buddhist.timeZone = berlin.timeZone
    // Mit dem Hilfskalender stimmen die Tage auch, wenn das Gerät buddhistisch rechnet.
    #expect(Upcoming.dayOffset("2026-11-22", today: saturday, calendar: berlin) == 1)
    #expect(Upcoming.dayOffset("2026-11-22", today: saturday, calendar: buddhist) != 1)
}

/// A-B-11: the last aired episode lies in the window although the next one is announced later.
@Test func nextEpisodesFetchesLastSeasonWhenNextIsOutsideWindow() async throws {
    let show = #"""
    {"id":42,"name":"Die Serie",
     "last_episode_to_air":{"season_number":1,"episode_number":9,"name":"Neun","air_date":"2026-11-23"},
     "next_episode_to_air":{"season_number":1,"episode_number":10,"name":"Zehn","air_date":"2026-12-24"}}
    """#
    let seasonOne = #"{"episodes":[{"season_number":1,"episode_number":8,"name":"Acht","air_date":"2026-11-23"},{"season_number":1,"episode_number":9,"name":"Neun","air_date":"2026-11-23"}]}"#
    let http = PathHTTP(["/3/tv/42": show, "/3/tv/42/season/1": seasonOne])
    let eps = try await TMDBClient(apiKey: "K", http: http).nextEpisodes(tmdbID: 42, from: "2026-11-23", through: "2026-12-08")
    #expect(http.urls.map(\.path) == ["/3/tv/42", "/3/tv/42/season/1"])
    #expect(Set(eps.filter { $0.airDate == "2026-11-23" }.map(\.episode)) == [8, 9])
}

/// A-B-11: next episode in the window belongs to another season than yesterday's double episode → both seasons.
@Test func nextEpisodesFetchesBothSeasonsWhenLastAndNextDiffer() async throws {
    let show = #"""
    {"id":42,"name":"Die Serie",
     "last_episode_to_air":{"season_number":1,"episode_number":9,"name":"Neun","air_date":"2026-11-23"},
     "next_episode_to_air":{"season_number":2,"episode_number":5,"name":"Fünf","air_date":"2026-11-27"}}
    """#
    let seasonOne = #"{"episodes":[{"season_number":1,"episode_number":8,"name":"Acht","air_date":"2026-11-23"},{"season_number":1,"episode_number":9,"name":"Neun","air_date":"2026-11-23"}]}"#
    let http = PathHTTP(["/3/tv/42": show, "/3/tv/42/season/1": seasonOne, "/3/tv/42/season/2": seasonTwo])
    let eps = try await TMDBClient(apiKey: "K", http: http).nextEpisodes(tmdbID: 42, from: "2026-11-23", through: "2026-12-08")
    #expect(http.urls.count == 3)
    #expect(Set(http.urls.map(\.path)) == ["/3/tv/42", "/3/tv/42/season/1", "/3/tv/42/season/2"])
    #expect(Set(eps.map { "\($0.season)x\($0.episode)" }).isSuperset(of: ["1x8", "1x9", "2x5", "2x6"]))
}

/// A-B-5 / A-B-10: day key for "recompute on day change" (local calendar day, not 24 h).
@Test func upcomingDayChangeWakesRows() {
    let cal = berlin
    let evening = cal.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 23, minute: 50))!
    let later = cal.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 23, minute: 59))!
    let morning = cal.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 0, minute: 10))!
    #expect(Upcoming.dayKey(evening, calendar: cal) == "2026-11-24")
    #expect(Upcoming.dayKey(morning, calendar: cal) == "2026-11-25")
    let day = Upcoming.dayKey(evening, calendar: cal)
    #expect(!Upcoming.wakeNeeded(lastDay: day, now: later, calendar: cal, cacheDue: false))
    #expect(Upcoming.wakeNeeded(lastDay: day, now: later, calendar: cal, cacheDue: true))
    #expect(Upcoming.wakeNeeded(lastDay: day, now: morning, calendar: cal, cacheDue: false))
}
