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
    let http = FakeSender([(200, allItems), (201, "{}"), (200, allItems), (400, "")])
    let s = SimklClient(clientID: "C", http: http)
    let tok = SyncToken(accessToken: "A")
    var q = SyncQueue()
    let add = q.record(.watchlistAdd, item: dune, imdb: dune.id, series: false, services: ["simkl"], now: t0)
    let addBear = q.record(.watchlistAdd, item: bear, imdb: bear.id, series: true, services: ["simkl"], now: t0)
    let w = q.record(.markWatched, item: dune, imdb: dune.id, series: false, services: ["simkl"], now: t0)
    // Add: only when the title is on no Simkl list.
    #expect(await s.apply(add, token: tok) == .confirmed)
    #expect(http.sent[0].url.path == "/sync/all-items" && http.sent[1].url.path == "/sync/add-to-list")
    #expect((jsonBody(http.sent[1])["movies"] as? [[String: Any]])?.first?["to"] as? String == "plantowatch")
    guard case .skipped = await s.apply(addBear, token: tok) else { Issue.record("completed show must not move"); return }
    #expect(http.sent.count == 3)
    // Removal never calls /sync/history/remove.
    let rem = SyncChange(kind: .watchlistRemove, itemID: bear.id, imdb: bear.id, item: bear, series: true, createdAt: t0, pending: ["simkl"])
    guard case .skipped = await s.apply(rem, token: tok) else { Issue.record("removal must be skipped"); return }
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
