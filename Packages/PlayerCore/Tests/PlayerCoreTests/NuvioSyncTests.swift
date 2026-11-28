import Foundation
import Testing
@testable import PlayerCore

// Nuvio account sync, T7: one pass against a scripted fake of the account. Invented values only.

private let t0 = Date(timeIntervalSince1970: 1_750_000_000)
private let clock = t0.addingTimeInterval(10 * 86400)
private let user = "00000000-0000-4000-8000-000000000001"
private let session = NuvioSession(accessToken: "AT1", refreshToken: "RT1", expiresAt: clock.addingTimeInterval(3600),
                                   userID: user)
private let profile2 = NuvioProfile(id: "00000000-0000-4000-8000-000000000102", userID: user, profileIndex: 2,
                                    name: "Zwei")

private func ms(_ seconds: Double) -> Int { Int(((t0.timeIntervalSince1970 + seconds) * 1000).rounded()) }

private func film(_ cid: String = "tt0137523", position: Int = 600_000, duration: Int = 6_000_000,
                  at: Double = 100) -> NuvioProgressRow {
    NuvioProgressRow(contentID: cid, contentType: "movie", videoID: cid, position: position, duration: duration,
                     lastWatched: ms(at))
}

private func episode(_ cid: String = "tt0903747", season: Int = 1, episode: Int, position: Int = 600_000,
                     at: Double = 100) -> NuvioProgressRow {
    NuvioProgressRow(contentID: cid, contentType: "series", videoID: "\(cid):\(season):\(episode)", season: season,
                     episode: episode, position: position, duration: 3_000_000, lastWatched: ms(at))
}

private func seen(_ cid: String, title: String? = "Titel", season: Int? = nil, episode: Int? = nil,
                  at: Double = 100) -> NuvioWatchedItem {
    NuvioWatchedItem(contentID: cid, contentType: season == nil ? "movie" : "series", title: title, season: season,
                     episode: episode, watchedAt: ms(at))
}

private func upsert(_ id: Int, _ row: NuvioProgressRow) -> NuvioProgressEvent {
    NuvioProgressEvent(eventID: id, operation: .upsert, progressKey: row.progressKey, row: row)
}

private func delete(_ id: Int, _ key: String) -> NuvioProgressEvent {
    NuvioProgressEvent(eventID: id, operation: .delete, progressKey: key, row: nil)
}

private func chosen(bootstrapped: Bool = true, cursor: Int = 0) -> NuvioState {
    var s = NuvioState()
    s.userID = user
    s.choose(profile2)
    if bootstrapped {
        s.bootstrapDone = true
        s.progressCursor = cursor
        s.watchedCursor = cursor
        s.lastPullAt = t0.addingTimeInterval(86400)
    }
    return s
}

private func named(_ id: String, type: String = "movie") -> MetaPreview { MetaPreview(id: id, type: type, name: "Lokal") }

private func push(_ cid: String = "tt0111161", at: Double = 200) -> NuvioProgressPush {
    NuvioProgressPush(contentID: cid, contentType: "movie", videoID: cid, position: 1000, duration: 2000,
                      lastWatched: ms(at))
}

/// A scripted account: snapshot, history, event logs; records every call; can fail chosen calls.
private final class FakeNuvio: NuvioSyncAPI, @unchecked Sendable {
    enum Call: Equatable {
        case profiles, progress, progressCursor, watchedCursor, push(Int)
        case progressDelta(Int), watched(Int), watchedDelta(Int)
    }

    private let lock = NSLock()
    var profileList: [NuvioProfile] = [profile2]
    var snapshot: [NuvioProgressRow] = []
    var history: [NuvioWatchedItem] = []
    var progressEvents: [NuvioProgressEvent] = []
    var watchedEvents: [NuvioWatchedEvent] = []
    /// Cursor values; nil = highest event id.
    var progressCursorValue: Int?
    var watchedCursorValue: Int?
    /// Delta pages in reverse order (the client must sort).
    var reversed = false
    var fail: @Sendable (Call) -> NuvioError? = { _ in nil }
    private(set) var calls: [Call] = []
    private(set) var pushed: [[NuvioProgressPush]] = []

    private func log(_ c: Call) throws {
        lock.withLock { calls.append(c) }
        if let e = fail(c) { throw e }
    }

    func clearCalls() { lock.withLock { calls = [] } }

    func profiles(_ s: NuvioSession) async throws -> [NuvioProfile] { try log(.profiles); return profileList }
    func progress(profile: Int, _ s: NuvioSession) async throws -> NuvioPage<NuvioProgressRow> {
        try log(.progress); return NuvioPage(rows: Array(snapshot.prefix(200)))
    }
    func progressCursor(profile: Int, _ s: NuvioSession) async throws -> Int {
        try log(.progressCursor); return progressCursorValue ?? progressEvents.map(\.eventID).max() ?? 0
    }
    func watchedCursor(profile: Int, _ s: NuvioSession) async throws -> Int {
        try log(.watchedCursor); return watchedCursorValue ?? watchedEvents.map(\.eventID).max() ?? 0
    }
    func push(profile: Int, _ entries: [NuvioProgressPush], _ s: NuvioSession) async throws {
        try log(.push(entries.count))
        lock.withLock { pushed.append(entries) }
    }
    func watched(profile: Int, page: Int, pageSize: Int, _ s: NuvioSession) async throws -> NuvioPage<NuvioWatchedItem> {
        try log(.watched(page))
        let from = (page - 1) * pageSize
        guard from < history.count else { return NuvioPage(rows: []) }
        return NuvioPage(rows: Array(history[from..<min(history.count, from + pageSize)]))
    }
    func progressDelta(profile: Int, since: Int, limit: Int, _ s: NuvioSession) async throws -> NuvioPage<NuvioProgressEvent> {
        try log(.progressDelta(since))
        return page(progressEvents.filter { $0.eventID > since }.sorted { $0.eventID < $1.eventID }, limit, \.eventID)
    }
    func watchedDelta(profile: Int, since: Int, limit: Int, _ s: NuvioSession) async throws -> NuvioPage<NuvioWatchedEvent> {
        try log(.watchedDelta(since))
        return page(watchedEvents.filter { $0.eventID > since }.sorted { $0.eventID < $1.eventID }, limit, \.eventID)
    }
    private func page<R>(_ all: [R], _ limit: Int, _ id: KeyPath<R, Int>) -> NuvioPage<R> {
        var rows = Array(all.prefix(limit))
        let last = rows.map { $0[keyPath: id] }.max()
        if reversed { rows.reverse() }
        return NuvioPage(rows: rows, lastEventID: last)
    }
}

/// Counts lookups and the most that ran at once.
private actor Lookups {
    var calls: [String] = []
    var running = 0
    var peak = 0
    func begin(_ id: String) { calls.append(id); running += 1; peak = max(peak, running) }
    func end() { running -= 1 }
}

private func deps(_ api: FakeNuvio, lookups: Lookups? = nil, imdb: [String: String] = [:],
                  titles: Bool = true) -> NuvioSyncDependencies {
    NuvioSyncDependencies(
        api: api,
        imdbID: { m in imdb[m.id] },
        meta: { m in
            await lookups?.begin(m.id)
            await Task.yield()
            await lookups?.end()
            return titles ? MetaPreview(id: m.id, type: m.type, name: "Name \(m.id)", poster: "https://example.org/x.jpg") : nil
        },
        now: { clock })
}

private func run(_ api: FakeNuvio, book: ProgressBook = ProgressBook(), state: NuvioState,
                 mode: NuvioSyncMode = .full, cooldownUntil: Date? = nil, lookups: Lookups? = nil,
                 imdb: [String: String] = [:], titles: Bool = true) async -> NuvioSyncResult {
    await NuvioSync.run(mode, session: session, book: book, state: state, cooldownUntil: cooldownUntil,
                        using: deps(api, lookups: lookups, imdb: imdb, titles: titles))
}

// MARK: Bootstrap

@Test func nuvioSyncBootstrapOrderPushThenCursorsSnapshotHistoryDelta() async {
    let api = FakeNuvio()
    api.snapshot = [film()]
    api.history = [seen("tt0068646")]
    api.progressCursorValue = 40
    api.watchedCursorValue = 7
    var s = chosen(bootstrapped: false)
    s.outbox.note(push(), now: t0)
    let r = await run(api, state: s)
    #expect(api.calls == [.profiles, .push(1), .progressCursor, .watchedCursor, .progress, .watched(1),
                          .progressDelta(40), .watchedDelta(7)])
    #expect(r.outcome == .ok && r.summary.bootstrapped && r.summary.pushed == 1)
    #expect(r.state.bootstrapDone && r.state.progressCursor == 40 && r.state.watchedCursor == 7)
    #expect(r.state.outbox.isEmpty && r.state.lastPullAt == clock)
    #expect(r.book.entries["tt0137523"]?.item.name == "Name tt0137523")
    #expect(r.book.entries["tt0068646"]?.finished == true)
    #expect(r.profile == profile2)
}

@Test func nuvioSyncHistoryPagingStopsAtShortPageAndAtPageTwenty() async {
    let api = FakeNuvio()
    api.history = (0..<1000).map { seen("tt\(1_000_000 + $0)", at: Double($0)) }
    _ = await run(api, state: chosen(bootstrapped: false))
    #expect(api.calls.filter { if case .watched = $0 { true } else { false } } == [.watched(1), .watched(2), .watched(3)])

    let big = FakeNuvio()
    big.history = (0..<(20 * 500 + 5)).map { seen("tt\(2_000_000 + $0)", at: Double($0)) }
    let r = await run(big, state: chosen(bootstrapped: false))
    #expect(big.calls.filter { if case .watched = $0 { true } else { false } } == (1...20).map { .watched($0) })
    #expect(r.state.bootstrapDone && r.book.entries.count == 10_000 && r.outcome == .ok)
}

@Test func nuvioSyncBootstrapDoneMakesNoSnapshotCall() async {
    let api = FakeNuvio()
    api.snapshot = [film()]
    _ = await run(api, state: chosen())
    #expect(api.calls == [.profiles, .progressDelta(0), .watchedDelta(0)])
}

@Test func nuvioSyncInterruptedBootstrapCommitsNothingAndResumes() async {
    let api = FakeNuvio()
    api.snapshot = [film()]
    api.history = (0..<600).map { seen("tt\(3_000_000 + $0)") }
    api.progressEvents = [upsert(5, film("tt0068646"))]
    api.progressCursorValue = 4
    api.fail = { $0 == .watched(2) ? .offline : nil }
    let first = await run(api, state: chosen(bootstrapped: false))
    #expect(first.outcome == .offline)
    #expect(first.book == ProgressBook() && !first.state.bootstrapDone)
    #expect(first.state.progressCursor == nil && first.state.watchedCursor == nil && first.state.lastPullAt == nil)

    api.fail = { _ in nil }
    let second = await run(api, book: first.book, state: first.state)
    #expect(second.outcome == .ok && second.state.bootstrapDone && second.state.progressCursor == 5)
    #expect(second.book.entries.count == 602)
}

@Test func nuvioSyncFirstConnectUploadsNoLocalProgress() async {
    var book = ProgressBook()
    book.record(id: "tt0111161", item: named("tt0111161"), position: 900, duration: 6000, now: t0)
    let api = FakeNuvio()
    api.snapshot = [film()]
    let r = await run(api, book: book, state: chosen(bootstrapped: false))
    #expect(!api.calls.contains { if case .push = $0 { true } else { false } })
    #expect(api.pushed.isEmpty && r.state.outbox.isEmpty && r.book.entries["tt0111161"] == book.entries["tt0111161"])
}

// MARK: Profile check

@Test func nuvioSyncEachProfileCheckStopsBeforeAnyOtherCall() async {
    var outboxState = chosen()
    outboxState.outbox.note(push(), now: t0)
    var book = ProgressBook()
    book.record(id: "tt0111161", item: named("tt0111161"), position: 900, duration: 6000, now: t0)

    var none = outboxState
    none.clearProfile()
    let api0 = FakeNuvio()
    let r0 = await run(api0, book: book, state: none)
    #expect(r0.outcome == .notChosen && api0.calls.isEmpty)

    let cases: [([NuvioProfile], NuvioSyncOutcome)] = [
        ([NuvioProfile(id: "x1", profileIndex: 1, name: "Eins")], .profileMissing),
        ([NuvioProfile(id: "00000000-0000-4000-8000-0000000009FF", profileIndex: 2, name: "Neu")], .profileReplaced),
        ([NuvioProfile(id: profile2.id, profileIndex: 2, name: "Zwei", pinEnabled: true)], .pinProtected),
    ]
    for (list, expected) in cases {
        let api = FakeNuvio()
        api.profileList = list
        let r = await run(api, book: book, state: outboxState)
        #expect(r.outcome == expected)
        #expect(api.calls == [.profiles])
        #expect(r.state == outboxState && r.book == book && r.changes.isEmpty && r.profile == nil)
    }
}

@Test func nuvioSyncAnotherAccountResetsStateAndStops() async {
    var s = chosen()
    s.userID = "00000000-0000-4000-8000-0000000000BB"
    s.outbox.note(push(), now: t0)
    let api = FakeNuvio()
    let r = await run(api, state: s)
    #expect(r.outcome == .notChosen && api.calls.isEmpty)
    #expect(r.state.userID == user && r.state.outbox.isEmpty && r.state.profileIndex == nil)
}

@Test func nuvioSyncSignedOutAtProfiles() async {
    let api = FakeNuvio()
    api.fail = { $0 == .profiles ? .signedOut : nil }
    let r = await run(api, state: chosen())
    #expect(r.outcome == .signedOut && api.calls == [.profiles])
}

// MARK: Push

@Test func nuvioSyncPushFailureKeepsOutbox() async {
    var s = chosen()
    s.outbox.note(push(), now: t0)
    let api = FakeNuvio()
    api.fail = { if case .push = $0 { .offline } else { nil } }
    let r = await run(api, state: s)
    #expect(r.outcome == .offline && api.calls == [.profiles, .push(1)])
    #expect(r.state.outbox.entries == s.outbox.entries && r.state.outbox.lastAttemptAt == clock)

    let refused = FakeNuvio()
    refused.fail = { if case .push = $0 { .status(500, code: nil) } else { nil } }
    let r2 = await run(refused, state: s)
    #expect(r2.outcome == .partial && r2.summary.pushError == .status(500, code: nil))
    #expect(r2.state.outbox.entries == s.outbox.entries)
    #expect(refused.calls == [.profiles, .push(1), .progressDelta(0), .watchedDelta(0)])
}

@Test func nuvioSyncPushOnlyHonoursThrottleAndPullsNothing() async {
    var s = chosen()
    s.outbox.note(push(), now: t0)
    s.outbox.failed(now: clock.addingTimeInterval(-30))
    let api = FakeNuvio()
    let waiting = await run(api, state: s, mode: .pushOnly(force: false))
    #expect(waiting.outcome == .ok && api.calls.isEmpty && waiting.state == s)
    let forced = await run(api, state: s, mode: .pushOnly(force: true))
    #expect(forced.outcome == .ok && api.calls == [.profiles, .push(1)] && forced.state.outbox.isEmpty)
}

@Test func nuvioSyncPulledRowsAreNeverQueued() async {
    let api = FakeNuvio()
    api.snapshot = [film(), episode(episode: 1)]
    api.progressEvents = [upsert(3, film("tt0068646"))]
    var book = ProgressBook()
    book.record(id: "tt0903747:1:1", item: named("tt0903747", type: "series"), season: 1, episode: 1, position: 100,
                duration: 3000, now: t0)
    let r = await run(api, book: book, state: chosen(bootstrapped: false))
    #expect(r.state.outbox.isEmpty && r.summary.merged >= 2)
    api.clearCalls()
    _ = await run(api, book: r.book, state: r.state)
    #expect(!api.calls.contains { if case .push = $0 { true } else { false } })
}

// MARK: Delta

@Test func nuvioSyncDeltaFullPageAsksForNextAndStoresHighestEvent() async {
    let api = FakeNuvio()
    api.progressEvents = (1...1003).map { upsert($0, film("tt\(4_000_000 + $0)", at: Double($0))) }
    var book = ProgressBook()
    for i in 1...1003 { book.record(id: "tt\(4_000_000 + i)", item: named("tt\(4_000_000 + i)"), position: 1, duration: 6000, now: t0) }
    let r = await run(api, book: book, state: chosen())
    #expect(api.calls.filter { if case .progressDelta = $0 { true } else { false } } == [.progressDelta(0), .progressDelta(1000)])
    #expect(r.state.progressCursor == 1003 && r.outcome == .ok && r.summary.merged == 1003)
}

@Test func nuvioSyncDeltaOutOfOrderIsAppliedAscending() async {
    let api = FakeNuvio()
    api.reversed = true
    api.progressEvents = [upsert(11, film(position: 100_000, at: 500)), delete(12, "tt0137523"),
                          delete(13, "tt0111161"), upsert(14, film("tt0111161", position: 900_000, at: 500)),
                          upsert(15, film("tt0068646", position: 100_000, at: 500)),
                          upsert(16, film("tt0068646", position: 200_000, at: 600))]
    var book = ProgressBook()
    for id in ["tt0137523", "tt0111161", "tt0068646"] {
        book.record(id: id, item: named(id), position: 1, duration: 6000, now: t0)
    }
    let r = await run(api, book: book, state: chosen(cursor: 10))
    #expect(r.book.entries["tt0137523"] == nil)
    #expect(r.book.entries["tt0111161"]?.position == 900)
    #expect(r.book.entries["tt0068646"]?.position == 200)
    #expect(r.state.progressCursor == 16)
}

@Test func nuvioSyncUpsertThenDeleteEndsDeletedAndReverseEndsUpserted() async {
    var book = ProgressBook()
    book.record(id: "tt0137523", item: named("tt0137523"), position: 600, duration: 6000, now: t0)
    let s = chosen()

    let a = FakeNuvio()
    a.progressEvents = [upsert(1, film(position: 900_000, at: 500)), delete(2, "tt0137523")]
    let r1 = await run(a, book: book, state: s)
    #expect(r1.book.entries["tt0137523"] == nil && r1.summary.deleted == 1)

    let b = FakeNuvio()
    b.progressEvents = [delete(1, "tt0137523"), upsert(2, film(position: 900_000, at: 500))]
    let r2 = await run(b, book: book, state: s)
    #expect(r2.book.entries["tt0137523"]?.position == 900 && r2.summary.deleted == 0)
}

@Test func nuvioSyncDeleteKeepsProtectedAndNewerLocalEntries() async {
    var book = ProgressBook()
    book.record(id: "tt0137523", item: named("tt0137523"), position: 600, duration: 6000, now: t0)
    book.record(id: "tt0111161", item: named("tt0111161"), position: 600, duration: 6000, now: t0)
    book.record(id: "tt0068646", item: named("tt0068646"), position: 600, duration: 6000, now: t0.addingTimeInterval(2 * 86400))
    var s = chosen()
    s.outbox.note(push("tt0111161"), now: t0)
    let api = FakeNuvio()
    api.progressEvents = [delete(1, "tt0137523"), delete(2, "tt0111161"), delete(3, "tt0068646")]
    api.fail = { if case .push = $0 { .status(500, code: nil) } else { nil } }
    let r = await run(api, book: book, state: s)
    #expect(r.book.entries["tt0137523"] == nil)
    #expect(r.book.entries["tt0111161"] != nil && r.book.entries["tt0068646"] != nil)
}

@Test func nuvioSyncErrorInSecondPageKeepsCursorAtMergedData() async {
    let api = FakeNuvio()
    api.progressEvents = (1...1500).map { upsert($0, film("tt\(5_000_000 + $0)", at: Double($0))) }
    api.fail = { $0 == .progressDelta(1000) ? .offline : nil }
    var book = ProgressBook()
    for i in 1...1500 { book.record(id: "tt\(5_000_000 + i)", item: named("tt\(5_000_000 + i)"), position: 1, duration: 6000, now: t0) }
    let s = chosen()
    let r = await run(api, book: book, state: s)
    #expect(r.outcome == .offline)
    #expect(r.state.progressCursor == 1000 && r.state.watchedCursor == 0 && r.state.lastPullAt == s.lastPullAt)
    #expect(r.book.entries["tt\(5_000_000 + 1000)"]?.position == 600)
    #expect(r.book.entries["tt\(5_000_000 + 1001)"]?.position == 1)
    #expect(!api.calls.contains { if case .watchedDelta = $0 { true } else { false } })

    api.fail = { _ in nil }
    let again = await run(api, book: r.book, state: r.state)
    #expect(again.outcome == .ok && again.state.progressCursor == 1500)
    #expect(again.book.entries["tt\(5_000_000 + 1500)"]?.position == 600)
}

@Test func nuvioSyncDeltaPageCapLeavesRestForNextPass() async {
    let api = FakeNuvio()
    api.progressEvents = (1...10_500).map { delete($0, "tt\(6_000_000 + $0)") }
    let r = await run(api, state: chosen())
    #expect(api.calls.filter { if case .progressDelta = $0 { true } else { false } }.count == 10)
    #expect(r.outcome == .partial && r.summary.moreToPull && r.state.progressCursor == 10_000)
    api.clearCalls()
    let next = await run(api, book: r.book, state: r.state)
    #expect(api.calls.filter { if case .progressDelta = $0 { true } else { false } } == [.progressDelta(10_000)])
    #expect(next.outcome == .ok && next.state.progressCursor == 10_500)
}

@Test func nuvioSyncUnreadableRowsMoveCursorAndCount() async {
    let api = FakeNuvio()
    api.progressEvents = [upsert(4, film("kitsu:12")), upsert(5, film(at: 300))]
    let r = await run(api, state: chosen())
    #expect(r.summary.skipped == 1 && r.state.skipped == 1 && r.state.progressCursor == 5)
    #expect(r.book.entries.count == 1)
}

// MARK: 429

@Test func nuvioSyncRateLimitStartsCooldownAndCooldownBlocksCalls() async {
    let api = FakeNuvio()
    api.fail = { if case .watchedDelta = $0 { .rateLimited } else { nil } }
    api.progressEvents = [upsert(1, film(at: 300))]
    let r = await run(api, state: chosen())
    let until = clock.addingTimeInterval(NuvioSync.cooldown)
    #expect(r.outcome == .rateLimited(until: until) && r.cooldownUntil == until)
    #expect(r.state.progressCursor == 1 && r.state.watchedCursor == 0 && r.state.staged.count == 1)

    api.clearCalls()
    api.fail = { _ in nil }
    let blocked = await run(api, book: r.book, state: r.state, cooldownUntil: until)
    #expect(blocked.outcome == .rateLimited(until: until) && api.calls.isEmpty && blocked.state == r.state)
    let after = await run(api, book: r.book, state: r.state, cooldownUntil: clock)
    #expect(after.outcome == .ok && !api.calls.isEmpty)
}

// MARK: Ids, titles, tombstones

@Test func nuvioSyncTMDBRowsUseIMDbIdAndRoundTripForDeletes() async {
    let api = FakeNuvio()
    api.progressEvents = [upsert(1, film("tmdb:550", at: 300)), upsert(2, film("tmdb:551", at: 300))]
    let r = await run(api, state: chosen(), imdb: ["tmdb:550": "tt0137523"])
    #expect(r.book.entries["tt0137523"] != nil && r.book.entries["tmdb:551"] != nil)
    #expect(r.state.remoteIDs == ["tt0137523": "tmdb:550"])

    api.progressEvents.append(delete(3, "tmdb:550"))
    var s = r.state
    s.lastPullAt = clock.addingTimeInterval(1)
    let r2 = await run(api, book: r.book, state: s)
    #expect(r2.book.entries["tt0137523"] == nil && r2.summary.deleted == 1)
}

@Test func nuvioSyncNamelessRowsWaitAndLookupsAreBounded() async {
    let api = FakeNuvio()
    api.progressEvents = (1...50).map { upsert($0, film("tt\(7_000_000 + $0)", at: Double($0))) }
    let none = await run(api, state: chosen(), titles: false)
    #expect(none.book.entries.isEmpty && none.state.staged.count == 50 && none.summary.staged == 50)

    let lookups = Lookups()
    let r = await run(api, book: none.book, state: none.state, lookups: lookups)
    let asked = await lookups.calls.count, peak = await lookups.peak
    #expect(asked == 40 && peak <= NuvioSync.lookupWidth)
    #expect(r.book.entries.count == 40 && r.state.staged.count == 10)
    #expect(r.book.entries["tt\(7_000_000 + 50)"]?.item.name == "Name tt7000050")   // newest first
    let rest = await run(api, book: r.book, state: r.state)
    #expect(rest.book.entries.count == 50 && rest.state.staged.isEmpty)
}

@Test func nuvioSyncKnownLocalTitleMergesWithoutLookup() async {
    var book = ProgressBook()
    book.record(id: "tt0903747:1:1", item: MetaPreview(id: "tt0903747", type: "series", name: "Serie"), season: 1,
                episode: 1, position: 100, duration: 3000, now: t0)
    let api = FakeNuvio()
    api.progressEvents = [upsert(1, episode(episode: 2, at: 300))]
    let lookups = Lookups()
    let r = await run(api, book: book, state: chosen(), lookups: lookups)
    let asked = await lookups.calls
    #expect(asked.isEmpty)
    #expect(r.book.entries["tt0903747:1:2"]?.item.name == "Serie")
}

@Test func nuvioSyncTombstonedTitlesStayOut() async {
    var s = chosen(bootstrapped: false)
    s.tombstone(itemID: "tt0137523", kind: .markedUnwatched, at: t0.addingTimeInterval(1000))
    s.tombstone(itemID: "tt0903747", kind: .removedFromContinue, at: t0.addingTimeInterval(1000))
    let api = FakeNuvio()
    api.snapshot = [film(at: 500), episode(episode: 3, at: 500)]
    api.history = [seen("tt0137523", at: 400), seen("tt0903747", season: 1, episode: 1, at: 400)]
    let lookups = Lookups()
    let r = await run(api, state: s, lookups: lookups)
    #expect(r.book.entries["tt0137523"] == nil && r.book.entries["tt0903747:1:3"] == nil)
    #expect(r.book.entries["tt0903747:1:1"]?.finished == true)   // watched history passes a continue-removal
    let asked = await lookups.calls
    #expect(r.state.staged.isEmpty && asked.isEmpty)
    #expect(r.state.tombstones.count == 2)
}

// MARK: Convergence

@Test func nuvioSyncSecondPassChangesNothing() async {
    let api = FakeNuvio()
    api.snapshot = [film(at: 50), film("tmdb:550", at: 60), episode(episode: 1, at: 70), film("kitsu:9", at: 80)]
    api.history = [seen("tt0068646", at: 40), seen("tmdb:1396", title: nil, season: 1, episode: 1, at: 30)]
    api.progressEvents = [upsert(3, film("tt0111161", at: 90)), delete(4, "tt0137523")]
    api.watchedEvents = [NuvioWatchedEvent(eventID: 2, operation: .upsert, item: seen("tt0110912", at: 95))]
    api.progressCursorValue = 2
    api.watchedCursorValue = 1
    var s = chosen(bootstrapped: false)
    s.outbox.note(push("tt0109830"), now: t0)
    let imdb = ["tmdb:550": "tt0120737", "tmdb:1396": "tt0903747"]
    let first = await run(api, state: s, imdb: imdb)
    #expect(first.outcome == .ok && first.summary.merged > 0 && first.summary.skipped == 1)
    let second = await run(api, book: first.book, state: first.state, imdb: imdb)
    #expect(second.outcome == .ok)
    #expect(second.book == first.book && second.state == first.state)
    #expect(second.summary.merged == 0 && second.summary.deleted == 0 && second.summary.pushed == 0)
}

@Test func nuvioSyncChangesReplayOntoLiveValuesKeepWhatChangedMeanwhile() async {
    var s = chosen()
    s.outbox.note(push("tt0109830", at: 200), now: t0)
    let api = FakeNuvio()
    api.progressEvents = [upsert(1, film(at: 300))]
    let r = await run(api, state: s)

    var replayBook = ProgressBook()
    var replayState = s
    r.changes.apply(to: &replayBook, state: &replayState)
    #expect(replayBook == r.book && replayState == r.state)

    // Meanwhile the app recorded a play and noted a newer push for the same key.
    var liveBook = ProgressBook()
    liveBook.record(id: "tt0068646", item: named("tt0068646"), position: 900, duration: 6000, now: clock)
    var liveState = s
    liveState.outbox.note(push("tt0109830", at: 250), now: clock)
    r.changes.apply(to: &liveBook, state: &liveState)
    #expect(liveBook.entries["tt0068646"] != nil && liveBook.entries["tt0137523"] != nil)
    #expect(liveState.outbox.entries.count == 1 && liveState.progressCursor == 1)
}
