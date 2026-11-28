import Foundation
import Testing
@testable import PlayerCore

// Nuvio account sync, T4: ids, units and keys between the app and the account. Invented values only.

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private func row(_ content: String, type: String = "movie", season: Int? = nil, episode: Int? = nil,
                 position: Int = 1_800_000, duration: Int = 3_600_000, last: Int = 1_700_000_000_000) -> NuvioProgressRow {
    NuvioProgressRow(contentID: content, contentType: type, videoID: content, season: season, episode: episode,
                     position: position, duration: duration, lastWatched: last)
}

// MARK: Ids

@Test func nuvioRemoteIDForms() {
    #expect(NuvioMapping.remoteID("tt0903747") == .imdb("tt0903747"))
    #expect(NuvioMapping.remoteID("tmdb:1396") == .tmdb(1396))
    #expect(NuvioMapping.remoteID("kitsu:7442") == .other("kitsu:7442"))
    #expect(NuvioMapping.remoteID("") == .other(""))
    #expect(NuvioMapping.remoteID("tt") == .other("tt"))
    #expect(NuvioMapping.remoteID("tmdb:abc") == .other("tmdb:abc"))
    #expect(NuvioMapping.remoteID("tmdb:-5") == .other("tmdb:-5"))
    #expect(NuvioMapping.remoteID(" tt0903747 ") == .imdb("tt0903747"))
}

@Test func nuvioKeysAndVideoIDs() {
    #expect(NuvioMapping.progressKey(contentID: "tmdb:550", season: nil, episode: nil) == "tmdb:550")
    #expect(NuvioMapping.progressKey(contentID: "tmdb:1396", season: 1, episode: 1) == "tmdb:1396_s1e1")
    #expect(NuvioMapping.videoID(contentID: "tmdb:1396", season: 1, episode: 1) == "tmdb:1396:1:1")
    #expect(NuvioMapping.videoID(contentID: "tmdb:550", season: nil, episode: nil) == "tmdb:550")
    #expect(NuvioMapping.localProgressID(itemID: "tt0903747", season: 2, episode: 3) == "tt0903747:2:3")
    #expect(NuvioMapping.localProgressID(itemID: "tt0137523", season: nil, episode: nil) == "tt0137523")
}

@Test func nuvioParsesProgressKeys() {
    let ep = NuvioMapping.parseKey("tmdb:1396_s1e12")
    #expect(ep.contentID == "tmdb:1396" && ep.season == 1 && ep.episode == 12)
    let film = NuvioMapping.parseKey("tmdb:550")
    #expect(film.contentID == "tmdb:550" && film.season == nil && film.episode == nil)
    // Something that only looks a bit like an episode suffix stays a film key.
    let odd = NuvioMapping.parseKey("tt1_sxe1")
    #expect(odd.contentID == "tt1_sxe1" && odd.season == nil)
    #expect(NuvioMapping.parseKey("_s1e1").contentID == "_s1e1")
}

// MARK: Units

@Test func nuvioUnits() {
    #expect(NuvioMapping.seconds(ms: 3_600_000) == 3600)
    #expect(NuvioMapping.ms(seconds: 3600) == 3_600_000)
    #expect(NuvioMapping.ms(seconds: 12.3456) == 12_346)
    #expect(NuvioMapping.ms(seconds: .nan) == nil)
    #expect(NuvioMapping.ms(seconds: .infinity) == nil)
    #expect(NuvioMapping.ms(seconds: -1) == nil)
    #expect(NuvioMapping.ms(seconds: 1e300) == nil)
    #expect(NuvioMapping.epochMS(Date(timeIntervalSince1970: 1_711_600_000)) == 1_711_600_000_000)
    #expect(NuvioMapping.date(ms: 1_711_600_000_500) == Date(timeIntervalSince1970: 1_711_600_000.5))
}

// MARK: Push

@Test func nuvioPushFilmAndEpisode() throws {
    let film = WatchProgress(id: "tt0137523", item: MetaPreview(id: "tt0137523", type: "movie", name: "Film"),
                             position: 1800, duration: 7920, updated: Date(timeIntervalSince1970: 1_711_600_000))
    let p = try #require(NuvioMapping.push(film, contentID: "tt0137523"))
    #expect(p == NuvioProgressPush(contentID: "tt0137523", contentType: "movie", videoID: "tt0137523",
                                   position: 1_800_000, duration: 7_920_000, lastWatched: 1_711_600_000_000))

    let ep = WatchProgress(id: "tt0903747:1:1", item: MetaPreview(id: "tt0903747", type: "series", name: "Serie"),
                           season: 1, episode: 1, position: 1800, duration: 3480, updated: Date(timeIntervalSince1970: 1_711_600_000))
    let q = try #require(NuvioMapping.push(ep, contentID: "tmdb:1396"))
    #expect(q == NuvioProgressPush(contentID: "tmdb:1396", contentType: "series", videoID: "tmdb:1396:1:1",
                                   season: 1, episode: 1, position: 1_800_000, duration: 3_480_000,
                                   lastWatched: 1_711_600_000_000))
}

@Test func nuvioPushNeedsAUsableLength() {
    let item = MetaPreview(id: "tt1", type: "movie", name: "Film")
    for d in [Double.infinity, .nan, 0, -5] {
        var w = WatchProgress(id: "tt1", item: item, position: 10, duration: 100)
        w.duration = d
        #expect(NuvioMapping.push(w, contentID: "tt1") == nil)
    }
    var nanPos = WatchProgress(id: "tt1", item: item, position: 10, duration: 100)
    nanPos.position = .nan
    #expect(NuvioMapping.push(nanPos, contentID: "tt1") == nil)
    // Past the end: the end. Negative: 0.
    var over = WatchProgress(id: "tt1", item: item, position: 10, duration: 100)
    over.position = 250
    #expect(NuvioMapping.push(over, contentID: "tt1")?.position == 100_000)
    var under = WatchProgress(id: "tt1", item: item, position: 10, duration: 100)
    under.position = -3
    #expect(NuvioMapping.push(under, contentID: "tt1")?.position == 0)
    // A series marker (no season, item is a series) is not a pushable row.
    let marker = WatchProgress(id: "tt2", item: MetaPreview(id: "tt2", type: "series", name: "S"), position: 0,
                               duration: 100, finished: true)
    #expect(NuvioMapping.push(marker, contentID: "tt2") == nil)
    #expect(NuvioMapping.push(WatchProgress(id: "tt1", item: item, position: 1, duration: 100), contentID: "") == nil)
}

@Test func nuvioPushOfAFinishedEntryIsTheFullLength() throws {
    // `record` stores a finished entry with position 0; the account must see it as complete (addendum A8).
    let w = WatchProgress(id: "tt1", item: MetaPreview(id: "tt1", type: "movie", name: "Film"), position: 0,
                          duration: 5400, finished: true)
    let p = try #require(NuvioMapping.push(w, contentID: "tt1"))
    #expect(p.position == p.duration && p.duration == 5_400_000)
}

// MARK: Pull

@Test func nuvioEntryFromAFilmRow() throws {
    let e = try #require(NuvioMapping.entry(row("tt0137523"), itemID: "tt0137523", name: "Film", now: now))
    #expect(e.id == "tt0137523" && e.season == nil && e.episode == nil)
    #expect(e.item.id == "tt0137523" && e.item.type == "movie" && e.item.name == "Film")
    #expect(e.item.poster == metahubPoster("tt0137523") && e.item.background == metahubBackground("tt0137523"))
    #expect(e.position == 1800 && e.duration == 3600 && !e.watched)
    #expect(e.updated == Date(timeIntervalSince1970: 1_700_000_000))
}

@Test func nuvioEntryFromAnEpisodeRowKeepsTheLocalID() throws {
    let e = try #require(NuvioMapping.entry(row("tmdb:1396", type: "series", season: 1, episode: 2),
                                            itemID: "tt0903747", name: nil, now: now))
    #expect(e.id == "tt0903747:1:2" && e.season == 1 && e.episode == 2)
    #expect(e.item.id == "tt0903747" && e.item.type == "series" && e.item.name == "")
    // A tmdb item id gets no metahub artwork.
    let t = try #require(NuvioMapping.entry(row("tmdb:1396", type: "series", season: 1, episode: 2),
                                            itemID: "tmdb:1396", name: nil, now: now))
    #expect(t.item.poster == nil && t.id == "tmdb:1396:1:2")
}

@Test func nuvioEntryClampsAFutureTime() throws {
    let future = NuvioMapping.epochMS(now) + 86_400_000
    let e = try #require(NuvioMapping.entry(row("tt1", last: future), itemID: "tt1", name: "F", now: now))
    #expect(e.updated == now)
}

@Test func nuvioEntryUnknownTypeWithEpisodeIsAnEpisode() throws {
    let e = try #require(NuvioMapping.entry(row("tt5", type: "anime-ish", season: 3, episode: 4),
                                            itemID: "tt5", name: "A", now: now))
    #expect(e.id == "tt5:3:4" && e.item.type == "series")
    let film = try #require(NuvioMapping.entry(row("tt6", type: "", season: nil, episode: nil), itemID: "tt6", name: "B", now: now))
    #expect(film.id == "tt6" && film.item.type == "movie")
    // A movie row with stray season fields stays a film.
    let movie = try #require(NuvioMapping.entry(row("tt7", type: "movie", season: 1, episode: 1), itemID: "tt7", name: "C", now: now))
    #expect(movie.id == "tt7" && movie.season == nil)
    // A series row without an episode is not a playable entry.
    #expect(NuvioMapping.entry(row("tt8", type: "series"), itemID: "tt8", name: "D", now: now) == nil)
}

@Test func nuvioEntryRepairsBadNumbers() throws {
    let e = try #require(NuvioMapping.entry(row("tt1", position: -5, duration: -1), itemID: "tt1", name: "F", now: now))
    #expect(e.position == 0 && e.duration == 0)
    let over = try #require(NuvioMapping.entry(row("tt1", position: 9_000_000, duration: 3_600_000), itemID: "tt1", name: "F", now: now))
    #expect(over.position == 3600)
}

@Test func nuvioEntryFromAWatchedItem() throws {
    let film = NuvioWatchedItem(contentID: "tt1", contentType: "movie", title: "Film", watchedAt: 1_700_000_000_000)
    let e = try #require(NuvioMapping.entry(film, itemID: "tt1", now: now))
    #expect(e.watched && e.id == "tt1" && e.item.name == "Film" && e.position == 0 && e.duration == 0)
    let ep = NuvioWatchedItem(contentID: "tmdb:1396", contentType: "series", title: "Serie", season: 2, episode: 5,
                              watchedAt: 1_700_000_000_000)
    let f = try #require(NuvioMapping.entry(ep, itemID: "tt0903747", now: now))
    #expect(f.id == "tt0903747:2:5" && f.watched && f.item.type == "series")
    // A watched row for a whole series (no episode) is skipped (plan section 7.8).
    let whole = NuvioWatchedItem(contentID: "tt9", contentType: "series", title: "S", watchedAt: 1)
    #expect(NuvioMapping.entry(whole, itemID: "tt9", now: now) == nil)
    let future = NuvioWatchedItem(contentID: "tt1", contentType: "movie", watchedAt: NuvioMapping.epochMS(now) + 5000)
    #expect(NuvioMapping.entry(future, itemID: "tt1", now: now)?.updated == now)
}
