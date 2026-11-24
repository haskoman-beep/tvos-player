import Foundation
import Testing
@testable import PlayerCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private let dune = MetaPreview(id: "tt1160419", type: "movie", name: "Dune")
private let bear = MetaPreview(id: "tt14452776", type: "series", name: "The Bear")
private func jsonBody(_ r: APIRequest) -> [String: Any] { (try? JSONSerialization.jsonObject(with: r.body ?? Data())) as? [String: Any] ?? [:] }

@Test func syncQueueCounterpartReplacesAndConfirmExpires() {
    var q = SyncQueue()
    q.record(.watchlistAdd, item: dune, imdb: dune.id, series: false, services: ["trakt", "simkl"], now: t0)
    let c = q.record(.watchlistRemove, item: dune, imdb: dune.id, series: false, services: ["trakt", "simkl"], now: t0.addingTimeInterval(5))
    #expect(q.changes.count == 1 && q.changes[c.id]?.kind == .watchlistRemove)
    #expect(q.due(for: "trakt").map(\.kind) == [.watchlistRemove])
    // A stale confirm (for the replaced add) does nothing.
    q.confirm(c.id, service: "trakt", createdAt: t0, now: t0.addingTimeInterval(6))
    #expect(q.changes[c.id]?.pending == ["trakt", "simkl"])
    q.confirm(c.id, service: "trakt", createdAt: c.createdAt, now: t0.addingTimeInterval(6))
    #expect(q.changes[c.id]?.confirmedAt == nil && q.due(for: "trakt").isEmpty)
    q.confirm(c.id, service: "simkl", createdAt: c.createdAt, now: t0.addingTimeInterval(10))
    #expect(q.changes[c.id]?.confirmedAt == t0.addingTimeInterval(10) && q.pendingCount == 0)
    // Confirmed + past the grace + stale cache: the watchlist tombstone stays and keeps hiding the title.
    #expect(q.prune(now: t0.addingTimeInterval(10 + SyncQueue.confirmedGrace + 3600)) == 0)
    #expect(q.applyWatchlist([dune, bear]).map(\.id) == [bear.id])
    // A pull that started too soon after the confirmation (service cache) does not release it; a later one does.
    #expect(q.notePull(watchlistStartedAt: t0.addingTimeInterval(10 + SyncQueue.confirmedGrace - 1)) == 0)
    #expect(q.notePull(watchlistStartedAt: t0.addingTimeInterval(10 + SyncQueue.confirmedGrace + 1)) == 1 && q.changes.isEmpty)
}

@Test func syncQueueOtherSlotsExpireAfterGrace() {
    var q = SyncQueue()
    let c = q.record(.markWatched, item: dune, imdb: dune.id, series: false, services: ["trakt"], now: t0)
    q.confirm(c.id, service: "trakt", createdAt: c.createdAt, now: t0)
    #expect(q.notePull(watchlistStartedAt: t0.addingTimeInterval(3600)) == 0)
    #expect(q.prune(now: t0.addingTimeInterval(SyncQueue.confirmedGrace - 1)) == 0)
    #expect(q.prune(now: t0.addingTimeInterval(SyncQueue.confirmedGrace + 1)) == 1)
}

@Test func syncQueueTMDBAndIMDbTilesShareOneEntry() {
    var q = SyncQueue()
    let tmdbTile = MetaPreview(id: "tmdb:9", type: "movie", name: "Neu")
    let imdbTile = MetaPreview(id: "tt9", type: "movie", name: "Neu")
    q.record(.watchlistAdd, item: tmdbTile, imdb: "tt9", series: false, services: ["trakt"], now: t0)
    let rem = q.record(.watchlistRemove, item: imdbTile, imdb: "tt9", series: false, services: ["trakt"], now: t0.addingTimeInterval(1))
    #expect(q.changes.count == 1 && rem.id == "watchlist:tt9")
    #expect(q.applyWatchlist([imdbTile]).isEmpty)
    #expect(!q.isOnWatchlist("tt9", remote: true))   // the app looks up by the canonical (IMDb) ID
    // An unresolved TMDB tile entry is replaced once the IMDb ID is known.
    var r = SyncQueue()
    r.record(.markWatched, item: tmdbTile, imdb: nil, series: false, services: [], now: t0)
    r.record(.markUnwatched, item: tmdbTile, imdb: "tt9", series: false, services: ["trakt"], now: t0)
    #expect(r.changes.keys.sorted() == ["watched:tt9"])
}

@Test func syncQueueExpiresUnconfirmedAfter30Days() {
    var q = SyncQueue()
    q.record(.removeFromContinue, item: bear, imdb: bear.id, series: true, services: ["trakt"], now: t0)
    #expect(q.prune(now: t0.addingTimeInterval(29 * 86400)) == 0)
    #expect(q.prune(now: t0.addingTimeInterval(30 * 86400 + 1)) == 1)
}

@Test func syncQueueWithoutServicesOrIMDbIsConfirmedAtOnce() {
    var q = SyncQueue()
    let a = q.record(.markWatched, item: dune, imdb: dune.id, series: false, services: [], now: t0)
    let tmdb = MetaPreview(id: "tmdb:5", type: "movie", name: "X")
    let b = q.record(.markWatched, item: tmdb, imdb: nil, series: false, services: ["trakt"], now: t0)
    #expect(q.changes[a.id]?.confirmedAt == t0 && q.changes[b.id]?.pending.isEmpty == true)
    #expect(q.due(for: "trakt").isEmpty)
}

@Test func syncQueueDropServiceConfirms() {
    var q = SyncQueue()
    let c = q.record(.markUnwatched, item: dune, imdb: dune.id, series: false, services: ["simkl"], now: t0)
    q.drop(service: "simkl", now: t0.addingTimeInterval(1))
    #expect(q.changes[c.id]?.confirmedAt == t0.addingTimeInterval(1))
}

@Test func syncQueueWatchlistOverlay() {
    var q = SyncQueue()
    let other = MetaPreview(id: "tt2", type: "movie", name: "Other")
    let tmdbTile = MetaPreview(id: "tmdb:9", type: "series", name: "Neu")
    q.record(.watchlistRemove, item: dune, imdb: dune.id, series: false, services: ["trakt"], now: t0)
    q.record(.watchlistAdd, item: tmdbTile, imdb: "tt9", series: true, services: ["trakt"], now: t0)
    q.record(.watchlistAdd, item: other, imdb: other.id, series: false, services: ["trakt"], now: t0.addingTimeInterval(-1))
    let pulled = [dune, other, bear]
    #expect(q.applyWatchlist(pulled).map(\.id) == ["tmdb:9", "tt2", "tt14452776"])
    // The add is already on the pulled list under its IMDb ID: no duplicate.
    let withIMDb = [MetaPreview(id: "tt9", type: "series", name: "Neu"), other]
    #expect(q.applyWatchlist(withIMDb).map(\.id) == ["tt9", "tt2"])
    #expect(!q.isOnWatchlist(dune.id, remote: true))
    #expect(q.isOnWatchlist("tmdb:9", remote: false) && q.isOnWatchlist("tt9", remote: false))
    #expect(q.isOnWatchlist(bear.id, remote: true) && !q.isOnWatchlist(bear.id, remote: false))
}

@Test func syncQueueFiltersPulledProgress() {
    var q = SyncQueue()
    q.record(.removeFromContinue, item: bear, imdb: bear.id, series: true, services: ["trakt"], now: t0)
    q.record(.markUnwatched, item: dune, imdb: dune.id, series: false, services: ["trakt"], now: t0)
    q.record(.watchlistRemove, item: MetaPreview(id: "tt3", type: "movie", name: "W"), imdb: "tt3", series: false, services: ["trakt"], now: t0)
    let remote = [
        RemoteProgress(id: "tt14452776:1:2", item: bear, season: 1, episode: 2, fraction: 0.3, updated: t0.addingTimeInterval(-60), playbackID: 11),
        RemoteProgress(id: "tt14452776:1:3", item: bear, season: 1, episode: 3, fraction: 0.1, updated: t0.addingTimeInterval(60), playbackID: 12),
        RemoteProgress(id: dune.id, item: dune, fraction: 0.5, updated: t0.addingTimeInterval(-1), playbackID: 13),
        RemoteProgress(id: "tt3", item: MetaPreview(id: "tt3", type: "movie", name: "W"), fraction: 0.2, updated: t0, playbackID: 14),
    ]
    // Later progress elsewhere passes; watchlist changes never filter progress.
    #expect(q.filterRemote(remote).map(\.id) == ["tt14452776:1:3", "tt3"])
    let c = q.changes.values.first { $0.kind == .removeFromContinue }!
    #expect(SyncQueue.playbackIDs(for: c, in: remote) == [11])
    // Small clock drift: an entry a few seconds "after" the removal still counts as older.
    let drift = RemoteProgress(id: "tt14452776:1:4", item: bear, season: 1, episode: 4, fraction: 0.1, updated: t0.addingTimeInterval(3), playbackID: 15)
    #expect(SyncQueue.playbackIDs(for: c, in: [drift]) == [15] && q.filterRemote([drift]).isEmpty)
}

@Test func syncQueueRoundTripsThroughStore() throws {
    let s = SyncQueueStore(storage: FileBlobStorage(directory: tempDir()))
    let p = UUID()
    var q = SyncQueue()
    q.record(.watchlistAdd, item: bear, imdb: bear.id, series: true, services: ["trakt"], now: t0.addingTimeInterval(0.375))
    try s.save(q, profile: p)
    #expect(s.load(profile: p) == q)
    #expect(s.load(profile: UUID()) == SyncQueue())
}

@Test func syncWriteClassify() {
    #expect(SyncWriteResult.classify(status: 201) == .confirmed)
    #expect(SyncWriteResult.classify(status: 204, deleting: true) == .confirmed)
    #expect(SyncWriteResult.classify(status: 404, deleting: true) == .confirmed)
    #expect(SyncWriteResult.classify(status: 404) == .rejected(404))
    #expect(SyncWriteResult.classify(status: 422) == .rejected(422))
    for s in [0, 401, 408, 429, 500, 503] { #expect(SyncWriteResult.classify(status: s) == .retry) }
}

@Test func progressBookTileActions() {
    var b = ProgressBook()
    b.record(id: "tt14452776:1:2", item: bear, season: 1, episode: 2, position: 600, duration: 1800, now: t0)
    b.record(id: "tt14452776:1:1", item: bear, season: 1, episode: 1, position: 1790, duration: 1800, now: t0)
    b.record(id: dune.id, item: dune, position: 900, duration: 9000, now: t0)
    #expect(b.continueWatching().count == 2)
    // Remove from Continue Watching keeps history.
    #expect(b.removeFromContinueWatching(itemID: bear.id) == 1)
    #expect(b.continueWatching().map(\.item.id) == [dune.id] && b.isWatched("tt14452776:1:1"))
    // Watched movie.
    b.markWatched(item: dune, series: false, now: t0)
    #expect(b.isTileWatched(dune.id) && b.continueWatching().isEmpty && b.cardState(itemID: dune.id)?.watched == true)
    b.markUnwatched(itemID: dune.id)
    #expect(!b.isTileWatched(dune.id) && b.entries[dune.id] == nil)
    // Series marker: unfinished episodes go, finished stay, tile shows watched.
    b.record(id: "tt14452776:1:3", item: bear, season: 1, episode: 3, position: 300, duration: 1800, now: t0)
    b.markWatched(item: bear, series: true, now: t0.addingTimeInterval(10))
    #expect(b.isTileWatched(bear.id) && b.entries["tt14452776:1:3"] == nil && b.entries["tt14452776:1:1"] != nil)
    #expect(b.cardState(itemID: bear.id)?.watched == true)
    // Older remote episode progress does not bring the series back; newer remote progress does.
    b.merge(remote: [RemoteProgress(id: "tt14452776:1:3", item: bear, season: 1, episode: 3, fraction: 0.2, updated: t0)])
    #expect(b.entries["tt14452776:1:3"] == nil && b.isTileWatched(bear.id))
    // Newer episode progress replaces the marker.
    b.record(id: "tt14452776:2:1", item: bear, season: 2, episode: 1, position: 300, duration: 1800, now: t0.addingTimeInterval(20))
    #expect(!b.isTileWatched(bear.id) && b.cardState(itemID: bear.id)?.episode == "S2 F1")
    b.markUnwatched(itemID: bear.id)
    #expect(b.entries.isEmpty)
}

@Test func tileMenuEntries() {
    #expect(TileMenuAction.menu(watchlistAvailable: true, onWatchlist: false, watched: false, inContinueRow: true)
            == [.watchlistAdd, .markWatched, .removeFromContinue, .openDetail])
    #expect(TileMenuAction.menu(watchlistAvailable: true, onWatchlist: true, watched: true, inContinueRow: false)
            == [.watchlistRemove, .markUnwatched, .openDetail])
    #expect(TileMenuAction.menu(watchlistAvailable: false, onWatchlist: true, watched: false, inContinueRow: false)
            == [.markWatched, .openDetail])
    #expect(TileMenuAction.removeFromContinue.title == "Aus „Weiterschauen“ entfernen")
    #expect(TileMenuAction.openDetail.change == nil && TileMenuAction.markUnwatched.change == .markUnwatched)
    #expect(TileMenuAction.removeFromContinue.removesTile(inContinueRow: true, inWatchlistRow: false))
    #expect(TileMenuAction.markWatched.removesTile(inContinueRow: true, inWatchlistRow: false))
    #expect(!TileMenuAction.markWatched.removesTile(inContinueRow: false, inWatchlistRow: true))
    #expect(TileMenuAction.watchlistRemove.removesTile(inContinueRow: false, inWatchlistRow: true))
    #expect(!TileMenuAction.openDetail.removesTile(inContinueRow: true, inWatchlistRow: true))
    #expect(TileMenuAction.neighbour(removing: 0, count: 3) == 1)
    #expect(TileMenuAction.neighbour(removing: 2, count: 3) == 1)
    #expect(TileMenuAction.neighbour(removing: 0, count: 1) == nil)
}

@Test func traktAppliesQueuedChanges() async {
    let playback = #"""
    [{"id":77,"progress":20,"paused_at":"2020-01-01T00:00:00.000Z","type":"episode","episode":{"season":1,"number":2},"show":{"title":"The Bear","ids":{"imdb":"tt14452776"}}},
     {"id":78,"progress":20,"paused_at":"2020-01-01T00:00:00.000Z","type":"movie","movie":{"title":"Dune","ids":{"imdb":"tt1160419"}}}]
    """#
    let http = FakeSender([(201, "{}"), (200, "{}"), (200, playback), (204, ""), (500, "")])
    let t = TraktClient(clientID: "C", clientSecret: "S", http: http)
    let tok = SyncToken(accessToken: "A")
    var q = SyncQueue()
    let add = q.record(.watchlistAdd, item: bear, imdb: bear.id, series: true, services: ["trakt"], now: t0)
    let un = q.record(.markUnwatched, item: dune, imdb: dune.id, series: false, services: ["trakt"], now: t0)
    let cw = q.record(.removeFromContinue, item: bear, imdb: bear.id, series: true, services: ["trakt"], now: t0)
    let w = q.record(.markWatched, item: dune, imdb: dune.id, series: false, services: ["trakt"], now: t0)
    #expect(await t.apply(add, token: tok) == .confirmed)
    #expect(http.sent[0].url.path == "/sync/watchlist" && http.sent[0].method == "POST")
    #expect(((jsonBody(http.sent[0])["shows"] as? [[String: Any]])?.first?["ids"] as? [String: String]) == ["imdb": "tt14452776"])
    #expect(await t.apply(un, token: tok) == .confirmed)
    #expect(http.sent[1].url.path == "/sync/history/remove" && jsonBody(http.sent[1])["movies"] != nil)
    #expect(await t.apply(cw, token: tok) == .confirmed)
    #expect(http.sent[3].method == "DELETE" && http.sent[3].url.path == "/sync/playback/77" && http.sent.count == 4)
    #expect(await t.apply(w, token: tok) == .retry)
    #expect(http.sent[4].url.path == "/sync/history")
}

@Test func simklAppliesQueuedChanges() async {
    let allItems = #"{"shows":[{"status":"completed","show":{"title":"The Bear","ids":{"imdb":"tt14452776"}}}]}"#
    let http = FakeSender([(200, allItems), (201, "{}"), (200, allItems), (400, "")])   // bear: found under shows
    let s = SimklClient(clientID: "C", http: http)
    let tok = SyncToken(accessToken: "A")
    var q = SyncQueue()
    let add = q.record(.watchlistAdd, item: dune, imdb: dune.id, series: false, services: ["simkl"], now: t0)
    let addBear = q.record(.watchlistAdd, item: bear, imdb: bear.id, series: true, services: ["simkl"], now: t0)
    let w = q.record(.markWatched, item: dune, imdb: dune.id, series: false, services: ["simkl"], now: t0)
    // Add: only when the title is on no Simkl list.
    #expect(await s.apply(add, token: tok) == .confirmed)
    #expect(http.sent[0].url.path == "/sync/all-items/movies" && http.sent[1].url.path == "/sync/add-to-list")
    #expect((jsonBody(http.sent[1])["movies"] as? [[String: Any]])?.first?["to"] as? String == "plantowatch")
    guard case .skipped = await s.apply(addBear, token: tok) else { Issue.record("completed show must not move"); return }
    #expect(http.sent.count == 3)
    // Removal never calls /sync/history/remove.
    let rem = SyncChange(kind: .watchlistRemove, itemID: bear.id, imdb: bear.id, item: bear, series: true, createdAt: t0, pending: ["simkl"])
    guard case .unconfirmed = await s.apply(rem, token: tok) else { Issue.record("removal stays local"); return }
    #expect(http.sent[2].url.path == "/sync/all-items/shows")
    #expect(http.sent.count == 3 && !http.sent.contains { $0.url.path == "/sync/history/remove" })
    #expect(await s.apply(w, token: tok) == .rejected(400))
    #expect(http.sent[3].url.path == "/sync/history")
}

@Test func continueRemovalWithoutRemoteEntryStaysUnconfirmed() async {
    let noID = #"[{"progress":20,"paused_at":"2020-01-01T00:00:00.000Z","type":"movie","movie":{"title":"Dune","ids":{"imdb":"tt1160419"}}}]"#
    let strID = #"[{"id":"91","progress":20,"paused_at":"2020-01-01T00:00:00.000Z","type":"movie","movie":{"title":"Dune","ids":{"imdb":"tt1160419"}}}]"#
    let http = FakeSender([(200, "[]"), (200, noID), (200, strID), (204, "")])
    let t = TraktClient(clientID: "C", clientSecret: "S", http: http)
    var q = SyncQueue()
    let c = q.record(.removeFromContinue, item: dune, imdb: dune.id, series: false, services: ["trakt"], now: t0)
    guard case .unconfirmed = await t.apply(c, token: SyncToken(accessToken: "A")) else { Issue.record("nothing found"); return }
    guard case .unconfirmed = await t.apply(c, token: SyncToken(accessToken: "A")) else { Issue.record("no id"); return }
    #expect(await t.apply(c, token: SyncToken(accessToken: "A")) == .confirmed)
    #expect(http.sent.last?.url.path == "/sync/playback/91")
    // Held: kept past the grace time and still blocking the pull, gone only after 30 days.
    q.confirm(c.id, service: "trakt", createdAt: c.createdAt, held: true, now: t0)
    #expect(q.pendingCount == 0 && q.prune(now: t0.addingTimeInterval(SyncQueue.confirmedGrace + 60)) == 0)
    #expect(q.prune(now: t0.addingTimeInterval(SyncQueue.maxAge + 1)) == 1)
}

@Test func simklOnlyWatchlistRemovalStaysHiddenAfterFreshPull() async {
    let s = SimklClient(clientID: "C", http: FakeSender([]))
    var q = SyncQueue()
    let rem = q.record(.watchlistRemove, item: dune, imdb: dune.id, series: false, services: ["simkl"], now: t0)
    guard case .unconfirmed = await s.apply(rem, token: SyncToken(accessToken: "A")) else { Issue.record("held expected"); return }
    q.confirm(rem.id, service: "simkl", createdAt: rem.createdAt, held: true, now: t0)
    // A fresh Simkl pull long after still lists the title: it stays hidden until the 30 days are over.
    #expect(q.notePull(watchlistStartedAt: t0.addingTimeInterval(24 * 3600)) == 0)
    #expect(q.prune(now: t0.addingTimeInterval(24 * 3600)) == 0)
    #expect(q.applyWatchlist([dune, bear]).map(\.id) == [bear.id])
    #expect(q.prune(now: t0.addingTimeInterval(SyncQueue.maxAge + 1)) == 1)
}

@Test func syncQueueStoreReadsFirstBuildFiles() throws {
    let storage = FileBlobStorage(directory: tempDir())
    let p = UUID()
    var q = SyncQueue()
    q.record(.watchlistRemove, item: MetaPreview(id: "tmdb:9", type: "movie", name: "Neu"), imdb: "tt9", series: false, services: ["trakt"], now: t0)
    // Old format: ISO-8601 dates, keyed by the tile ID.
    q.changes = Dictionary(uniqueKeysWithValues: q.changes.values.map { ("watchlist:tmdb:9", $0) })
    let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
    try storage.write("syncqueue-\(p.uuidString).json", try enc.encode(q))
    let back = SyncQueueStore(storage: storage).load(profile: p)
    #expect(back.changes.keys.sorted() == ["watchlist:tt9"])
}

@Test func simklCompletedAnimeGetsNoPlantowatch() async {
    let anime = #"{"anime":[{"status":"completed","show":{"title":"Frieren","ids":{"imdb":"tt22248376"}}}]}"#
    let http = FakeSender([(200, #"{"shows":[]}"#), (200, anime)])
    let s = SimklClient(clientID: "C", http: http)
    let frieren = MetaPreview(id: "tt22248376", type: "series", name: "Frieren")
    var q = SyncQueue()
    let add = q.record(.watchlistAdd, item: frieren, imdb: frieren.id, series: true, services: ["simkl"], now: t0)
    guard case .skipped = await s.apply(add, token: SyncToken(accessToken: "A")) else { Issue.record("anime must not move"); return }
    #expect(http.sent.map(\.url.path) == ["/sync/all-items/shows", "/sync/all-items/anime"])
}

@Test func simklNullListBodyCountsAsNoItems() async {
    let frieren = MetaPreview(id: "tt22248376", type: "series", name: "Frieren")
    var q = SyncQueue()
    let add = q.record(.watchlistAdd, item: frieren, imdb: frieren.id, series: true, services: ["simkl"], now: t0)
    let tok = SyncToken(accessToken: "A")
    let paths = ["/sync/all-items/shows", "/sync/all-items/anime", "/sync/add-to-list"]
    // No anime on the account: `/anime` answers a literal `null`.
    let noAnime = FakeSender([(200, #"{"shows":[]}"#), (200, "null"), (201, "{}")])
    #expect(await SimklClient(clientID: "C", http: noAnime).apply(add, token: tok) == .confirmed)
    #expect(noAnime.sent.map(\.url.path) == paths)
    // No shows either, and other non-object bodies.
    let noShows = FakeSender([(200, "null"), (200, "[]"), (201, "{}")])
    #expect(await SimklClient(clientID: "C", http: noShows).apply(add, token: tok) == .confirmed)
    #expect(noShows.sent.map(\.url.path) == paths)
    // A real HTTP error or broken JSON still waits for the next pass, nothing is added.
    let down = FakeSender([(200, "null"), (500, "")])
    #expect(await SimklClient(clientID: "C", http: down).apply(add, token: tok) == .retry)
    let broken = FakeSender([(200, "<html>")])
    #expect(await SimklClient(clientID: "C", http: broken).apply(add, token: tok) == .retry)
    #expect(broken.sent.count == 1)
}

@Test func syncQueueStoreReportsUnreadableFile() throws {
    let storage = FileBlobStorage(directory: tempDir())
    let p = UUID()
    try storage.write("syncqueue-\(p.uuidString).json", Data("kaputt".utf8))
    var failed = false
    let q = SyncQueueStore(storage: storage).load(profile: p) { failed = true }
    #expect(failed && q.changes.isEmpty)
}

// MARK: Build 2 (Task 2.5): nothing gets lost, nothing blocks

/// The queue as builds 249/250 and Build 1 decode it (synthesized Codable, no `actions`/`attempts`).
private struct OldChange: Codable { var kind: SyncChangeKind; var itemID: String; var imdb: String?; var item: MetaPreview
    var series: Bool; var createdAt: Date; var pending: Set<String>; var confirmedAt: Date?; var held: Bool? }
private struct OldQueue: Codable { var schemaVersion: Int; var changes: [String: OldChange] }

@Test func syncQueueReadsBuild250FixtureAndOldBuildsReadNewQueue() throws {
    let store = SyncQueueStore(storage: FileBlobStorage(directory: tempDir()))
    let p = UUID()
    try store.storage.write("syncqueue-\(p.uuidString).json", try fixture("build250-syncqueue.json"))
    var q = store.load(profile: p)
    #expect(q.changes.count == 2 && q.actions.isEmpty && q.deadLetters.isEmpty)
    #expect(q.changes["watched:tt1160419"]?.attempts == nil && q.due(for: "trakt").count == 1)
    q.enqueue(.scrobbleStop(id: "tt14452776:1:2", progress: 0.85, at: t0), services: ["trakt"], now: t0)
    q.failChange("watched:tt1160419", service: "trakt", createdAt: q.changes["watched:tt1160419"]!.createdAt, result: .retry)
    try store.save(q, profile: p)
    let data = try #require(store.storage.read("syncqueue-\(p.uuidString).json"))
    let old = try JSONDecoder().decode(OldQueue.self, from: data)   // older build: still reads, ignores new keys
    #expect(old.changes.count == 2 && old.changes["watched:tt1160419"]?.pending == ["trakt"])
    #expect(store.load(profile: p) == q)
}

@Test func syncQueueSkipsUnknownActionsInsteadOfFailing() throws {
    let json = #"{"schemaVersion":1,"changes":{},"actions":[{"id":"a","action":{"teleport":{"x":1}},"createdAt":0,"pending":["trakt"]},{"id":"b","action":{"scrobbleStop":{"id":"tt1","progress":0.9,"at":10}},"createdAt":10,"pending":["trakt"]}],"deadLetters":"nonsense"}"#
    let q = try JSONDecoder().decode(SyncQueue.self, from: Data(json.utf8))
    #expect(q.actions.map(\.id) == ["b"] && q.actions[0].attempts == 0 && q.deadLetters.isEmpty)
}

@Test func syncQueueActionGoesToDeadLettersAfterEightAttempts() {
    var q = SyncQueue()
    let e = q.enqueue(.scrobbleStop(id: "tt1160419", progress: 0.9, at: t0), services: ["trakt", "simkl"], now: t0)!
    for _ in 1..<SyncQueue.maxAttempts { let r = q.fail(e.id, service: "trakt", result: .retry); #expect(!r) }
    #expect(q.dueActions(for: "trakt").count == 1 && q.actions[0].attempts == 7)
    let gone = q.fail(e.id, service: "trakt", result: .retry)
    #expect(gone)
    #expect(q.dueActions(for: "trakt").isEmpty && q.dueActions(for: "simkl").count == 1)
    #expect(q.deadLetters.count == 1 && q.deadLetters[0].pending == ["trakt"] && q.deadLetters[0].attempts == 8)
    q.finish(e.id, service: "simkl")
    #expect(q.actions.isEmpty && q.pendingCount == 0)
}

@Test func syncQueuePermanentErrorsDeadLetterAtOnceTransientOnesRetry() {
    var q = SyncQueue()
    let e = q.enqueue(.scrobbleStop(id: "tt1160419", progress: 0.9, at: t0), services: ["trakt"], now: t0)!
    for s in [401, 408, 429, 500, 0] { let r = q.fail(e.id, service: "trakt", result: SyncWriteResult.classify(status: s)); #expect(!r) }
    let gone = q.fail(e.id, service: "trakt", result: SyncWriteResult.classify(status: 422))
    #expect(gone)
    #expect(q.actions.isEmpty && q.deadLetters.first?.lastStatus == 422)
    // Tile changes too: a 404 ends it for that service, the local state stays.
    let c = q.record(.markWatched, item: dune, imdb: dune.id, series: false, services: ["trakt"], now: t0)
    let kept = q.failChange(c.id, service: "trakt", createdAt: c.createdAt, result: .retry)
    #expect(!kept)
    #expect(q.changes[c.id]?.attempts == 1 && q.due(for: "trakt").count == 1)
    let dead = q.failChange(c.id, service: "trakt", createdAt: c.createdAt, result: .rejected(404))
    #expect(dead)
    #expect(q.due(for: "trakt").isEmpty && q.changes[c.id]?.kind == .markWatched)
    #expect(q.deadLetters.count == 2 && { if case .change(let d) = q.deadLetters[1].action { d.id == c.id && d.attempts == 2 } else { false } }())
}

@Test func syncQueueResolveThenSendsOnceTheIMDbIDIsKnown() {
    var q = SyncQueue()
    let tile = MetaPreview(id: "tmdb:136315", type: "series", name: "The Bear")
    // Offline: no IMDb ID yet, the change stays local and an action waits for the lookup.
    q.record(.watchlistAdd, item: tile, imdb: nil, series: true, services: ["trakt"], now: t0)
    q.enqueue(.resolveThen(tmdbID: tile.id, type: "series", action: .watchlistAdd), services: ["trakt"], now: t0)
    #expect(q.due(for: "trakt").isEmpty && q.actions.count == 1)
    let n = q.resolve(tmdbID: tile.id, imdb: "tt14452776", services: ["trakt"])
    #expect(n == 1)
    let due = q.due(for: "trakt")
    #expect(due.count == 1 && due[0].imdb == "tt14452776" && due[0].itemID == tile.id && due[0].createdAt == t0)
    #expect(q.actions.isEmpty && q.isOnWatchlist("tt14452776", remote: false))
    // The local change expired meanwhile (5 min grace): it is rebuilt from the action.
    var r = SyncQueue()
    r.enqueue(.resolveThen(tmdbID: "tmdb:438631", type: "movie", action: .markWatched), services: ["trakt"], now: t0)
    r.resolve(tmdbID: "tmdb:438631", imdb: "tt1160419", services: ["trakt"])
    #expect(r.due(for: "trakt").first?.kind == .markWatched && r.due(for: "trakt").first?.series == false)
}

@Test func traktSendsFailedStopAsHistoryWithWatchedAt() async {
    let http = FakeSender([(200, "[]"), (201, "{}")])
    let t = TraktClient(clientID: "C", clientSecret: "S", http: http)
    let e = SyncQueue.Entry(action: .scrobbleStop(id: "tt14452776:1:2", progress: 0.85, at: t0), createdAt: t0, pending: ["trakt"])
    #expect(await t.apply(e, token: SyncToken(accessToken: "A")) == .confirmed)
    #expect(http.sent.count == 2 && http.sent[0].method == "GET" && http.sent[1].method == "POST" && http.sent[1].url.path == "/sync/history")
    let show = (jsonBody(http.sent[1])["shows"] as? [[String: Any]])?.first
    let ep = ((show?["seasons"] as? [[String: Any]])?.first?["episodes"] as? [[String: Any]])?.first
    #expect((show?["ids"] as? [String: String]) == ["imdb": "tt14452776"] && ep?["number"] as? Int == 2)
    #expect((ep?["watched_at"] as? String).flatMap(TraktClient.date) == t0)
}

/// Answers like Trakt: history by type with a time window; an IMDb ID in the path is no valid Trakt ID (404).
private final class HistoryFake: APISending, @unchecked Sendable {
    var sent: [APIRequest] = []
    let history: String
    init(history: String) { self.history = history }
    func send(_ r: APIRequest) async throws -> (status: Int, data: Data) {
        sent.append(r)
        if r.method == "GET" {
            let path = r.url.path
            guard path == "/sync/history/movies" || path == "/sync/history/episodes",
                  r.url.query?.contains("start_at=") == true, r.url.query?.contains("end_at=") == true else { return (404, Data()) }
            return (200, Data(history.utf8))
        }
        return (201, Data("{}".utf8))
    }
}

@Test func traktQueuedStopChecksHistoryByWindowEvenOnFirstSend() async {
    let at = SyncWriteBody.iso(t0.addingTimeInterval(-40))   // the scrobble's server time lies before the queue time
    let http = HistoryFake(history: #"[{"id":1,"watched_at":"\#(at)","type":"movie","movie":{"ids":{"imdb":"tt1160419"}}}]"#)
    let t = TraktClient(clientID: "C", clientSecret: "S", http: http)
    let e = SyncQueue.Entry(action: .scrobbleStop(id: "tt1160419", progress: 0.95, at: t0), createdAt: t0, pending: ["trakt"])
    #expect(e.attempts == 0)
    #expect(await t.apply(e, token: SyncToken(accessToken: "A")) == .confirmed)   // already there: no second play
    #expect(http.sent.count == 1 && http.sent[0].method == "GET" && http.sent[0].url.path == "/sync/history/movies")
}

@Test func traktHistoryCheckMatchesIMDbAndEpisode() async {
    let at = SyncWriteBody.iso(t0)
    // In the window, but another movie and another episode of the show: not there, so it is sent.
    let other = #"[{"watched_at":"\#(at)","type":"movie","movie":{"ids":{"imdb":"tt0000001"}}},{"watched_at":"\#(at)","type":"episode","episode":{"season":1,"number":3},"show":{"ids":{"imdb":"tt14452776"}}}]"#
    let http = HistoryFake(history: other)
    let t = TraktClient(clientID: "C", clientSecret: "S", http: http)
    let tok = SyncToken(accessToken: "A")
    let movie = SyncQueue.Entry(action: .scrobbleStop(id: "tt1160419", progress: 0.9, at: t0), createdAt: t0, pending: ["trakt"])
    #expect(await t.apply(movie, token: tok) == .confirmed)
    #expect(http.sent.count == 2 && http.sent[1].method == "POST" && http.sent[1].url.path == "/sync/history")
    let ep = SyncQueue.Entry(action: .scrobbleStop(id: "tt14452776:1:2", progress: 0.9, at: t0), createdAt: t0, pending: ["trakt"])
    #expect(await t.apply(ep, token: tok) == .confirmed)
    #expect(http.sent[2].url.path == "/sync/history/episodes" && http.sent[3].method == "POST")
    let hit = HistoryFake(history: other)
    let ep3 = SyncQueue.Entry(action: .scrobbleStop(id: "tt14452776:1:3", progress: 0.9, at: t0), createdAt: t0, pending: ["trakt"])
    #expect(await TraktClient(clientID: "C", clientSecret: "S", http: hit).apply(ep3, token: tok) == .confirmed)
    #expect(hit.sent.count == 1)   // same show and episode in the window: found, nothing posted
    // A resent tile "watched" checks the same way and carries watched_at.
    let w = HistoryFake(history: "[]")
    var q = SyncQueue()
    var c = q.record(.markWatched, item: dune, imdb: dune.id, series: false, services: ["trakt"], now: t0)
    c.attempts = 1
    #expect(await TraktClient(clientID: "C", clientSecret: "S", http: w).apply(c, token: tok) == .confirmed)
    #expect(w.sent.count == 2 && w.sent[0].url.path == "/sync/history/movies" && w.sent[1].url.path == "/sync/history")
    #expect(((jsonBody(w.sent[1])["movies"] as? [[String: Any]])?.first?["watched_at"] as? String).flatMap(TraktClient.date) == t0)
}

@Test func syncQueueOfflineAndRepeatedFailuresInOnePassBurnNoAttempts() {
    var q = SyncQueue()
    let e = q.enqueue(.scrobbleStop(id: "tt1160419", progress: 0.9, at: t0), services: ["trakt", "simkl"], now: t0)!
    for _ in 0..<20 { let r = q.fail(e.id, service: "trakt", result: .offline); #expect(!r) }
    #expect(q.actions[0].attempts == 0 && q.deadLetters.isEmpty)
    #expect(SyncWriteResult.failure(URLError(.notConnectedToInternet)) == .offline && SyncWriteResult.failure(URLError(.timedOut)) == .offline)
    #expect(SyncWriteResult.failure(APIError.status(503)) == .retry && SyncWriteResult.failure(APIError.status(422)) == .rejected(422))
    let a = q.fail(e.id, service: "trakt", result: .retry)
    let b = q.fail(e.id, service: "simkl", result: .retry, countAttempt: false)   // same pass, second service
    #expect(!a && !b && q.actions[0].attempts == 1)
    let c = q.record(.markWatched, item: dune, imdb: dune.id, series: false, services: ["trakt"], now: t0)
    for _ in 0..<20 { let r = q.failChange(c.id, service: "trakt", createdAt: c.createdAt, result: .offline); #expect(!r) }
    let d = q.failChange(c.id, service: "trakt", createdAt: c.createdAt, result: .retry, countAttempt: false)
    #expect(!d && (q.changes[c.id]?.attempts ?? 0) == 0 && q.due(for: "trakt").count == 1)
}

@Test func progressSaveUsesTheScrobbleWatchedThreshold() {
    #expect(ProgressBook.finishedThreshold(syncConnected: true) == 0.8)
    #expect(ProgressBook.finishedThreshold(syncConnected: false) == ProgressBook.finishedAt)
    let show = MetaPreview(id: "tt14452776", type: "series", name: "The Bear")
    var b = ProgressBook()
    b.record(id: "tt14452776:1:2", item: show, season: 1, episode: 2, position: 1500, duration: 1800)
    b.markFinished(id: "tt14452776:1:2")   // the stop ran first …
    // … then the player's close-time save at 85 % with the same threshold keeps it watched.
    b.record(id: "tt14452776:1:2", item: show, season: 1, episode: 2, position: 1530, duration: 1800,
             finishedAt: ProgressBook.finishedThreshold(syncConnected: true))
    #expect(b.isWatched("tt14452776:1:2"))
    b.recordNextUp(id: "tt14452776:1:3", item: show, season: 1, episode: 3)
    #expect(b.continueWatching().first?.id == "tt14452776:1:3")
    // Without a service the local 92 % rule stays.
    var l = ProgressBook()
    l.record(id: "tt1160419", item: dune, position: 85, duration: 100, finishedAt: ProgressBook.finishedThreshold(syncConnected: false))
    #expect(!l.isWatched("tt1160419"))
}

@Test func simklSendsFailedStopAsHistory() async {
    let http = FakeSender([(201, "{}")])
    let s = SimklClient(clientID: "C", http: http)
    let e = SyncQueue.Entry(action: .scrobbleStop(id: "tt1160419", progress: 0.9, at: t0), createdAt: t0, pending: ["simkl"], attempts: 3)
    #expect(await s.apply(e, token: SyncToken(accessToken: "A")) == .confirmed)
    #expect(http.sent.count == 1 && http.sent[0].url.path == "/sync/history")
    #expect(((jsonBody(http.sent[0])["movies"] as? [[String: Any]])?.first?["watched_at"] as? String).flatMap(TraktClient.date) == t0)
}

@Test func scrobbleOneStopWatchedFromEightyNoStartWhilePaused() {
    var t = ScrobbleTracker<String>(finishedAt: 0.92)
    #expect(kinds(t.progress("A", id: "a", fraction: 0.5)) == [.start])
    #expect(kinds(t.pause(id: "a")) == [.pause])
    #expect(kinds(t.progress("A", id: "a", fraction: 0.5)).isEmpty)    // saved while paused: no start
    #expect(kinds(t.progress("A", id: "a", fraction: 0.51)) == [.start])   // playing again
    _ = t.progress("A", id: "a", fraction: 0.85)
    let stop = t.end(id: "a")
    #expect(stop.map(\.action) == [.stop] && stop[0].watched)
    #expect(kinds(t.end(id: "a")).isEmpty && kinds(t.pause(id: "a")).isEmpty)
    var u = ScrobbleTracker<String>(finishedAt: 0.92)
    _ = u.progress("B", id: "b", fraction: 0.3)
    let early = u.end(id: "b")
    #expect(early.map(\.action) == [.stop] && !early[0].watched)
    var w = ScrobbleTracker<String>(finishedAt: 0.92)
    _ = w.progress("C", id: "c", fraction: 0.5)
    #expect(kinds(w.progress("C", id: "c", fraction: 0.95)) == [.stop])
    #expect(kinds(w.pause(id: "c")).isEmpty && kinds(w.end(id: "c")).isEmpty)   // exactly one stop
    var b = ProgressBook()
    b.record(id: "c", item: MetaPreview(id: "c", type: "movie", name: "C"), season: nil, episode: nil, position: 85, duration: 100)
    b.markFinished(id: "c")
    #expect(b.entries["c"]?.finished == true)
}

@Test func deviceLoginKeepsWaitingOnServerErrors() async throws {
    let code = DeviceCode(deviceCode: "D", userCode: "U", verificationURL: "https://example.invalid", expiresIn: 600, interval: 5)
    let trakt = TraktClient(clientID: "C", clientSecret: "S", http: FakeSender([(503, ""), (408, ""), (500, ""), (410, "")]))
    #expect(try await trakt.poll(code) == .pending)
    #expect(try await trakt.poll(code) == .pending)
    #expect(try await trakt.poll(code) == .pending)
    #expect(try await trakt.poll(code) == .expired)
    let simkl = SimklClient(clientID: "C", http: FakeSender([(502, ""), (404, "")]))
    #expect(try await simkl.poll(code) == .pending)
    #expect(try await simkl.poll(code) == .expired)
}
private func kinds(_ e: [ScrobbleEvent<String>]) -> [ScrobbleAction] { e.map(\.action) }

/// Final review I3: errors of the limited HTTP client (total time, connection lost) and a cancelled pass are
/// network trouble, not a failed attempt; a body over the size limit stays a retry.
@Test func syncFailureMapsHTTPClientErrorsToOffline() {
    #expect(SyncWriteResult.failure(HTTPClientError.timedOut) == .offline)
    #expect(SyncWriteResult.failure(HTTPClientError.incomplete) == .offline)
    #expect(SyncWriteResult.failure(CancellationError()) == .offline)
    #expect(SyncWriteResult.failure(HTTPClientError.tooLarge(limit: 1)) == .retry)
}
