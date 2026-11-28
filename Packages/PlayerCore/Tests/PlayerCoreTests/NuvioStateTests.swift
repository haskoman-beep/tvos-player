import Foundation
import Testing
@testable import PlayerCore

// Nuvio account sync, T6: per-profile state blob (`nuvio-<uuid>.json`). Invented values only.

private let t0 = Date(timeIntervalSince1970: 1_750_000_000)
private let profile = UUID(uuidString: "00000000-0000-4000-8000-0000000000AA")!

private final class MemoryBlobs: BlobStorage, BlobNames, @unchecked Sendable {
    private var blobs: [String: Data] = [:]
    private let lock = NSLock()
    func read(_ name: String) -> Data? { lock.withLock { blobs[name] } }
    func write(_ name: String, _ data: Data) throws { lock.withLock { blobs[name] = data } }
    func remove(_ name: String) { _ = lock.withLock { blobs.removeValue(forKey: name) } }
    func blobNames() -> [String] { lock.withLock { Array(blobs.keys) } }
}

private func sample() -> NuvioState {
    var s = NuvioState()
    s.userID = "00000000-0000-4000-8000-000000000001"
    s.profileIndex = 2
    s.profileID = "00000000-0000-4000-8000-000000000102"
    s.progressCursor = 41
    s.watchedCursor = 7
    s.bootstrapDone = true
    s.lastPullAt = t0
    s.remoteIDs = [NuvioIDLink(local: "tt0903747", remote: "tmdb:1396", series: true)]
    s.outbox.note(NuvioProgressPush(contentID: "tmdb:1396", contentType: "series", videoID: "tmdb:1396:1:1", season: 1,
                                    episode: 1, position: 1000, duration: 2000, lastWatched: 5), now: t0)
    s.stage(NuvioStaged(itemID: "tt0903747",
                        row: NuvioProgressRow(contentID: "tmdb:1396", contentType: "series", videoID: "tmdb:1396:1:2",
                                              season: 1, episode: 2, position: 10, duration: 20, lastWatched: 9),
                        stagedAt: t0))
    s.skipped = 3
    s.tombstone(itemID: "tt0137523", kind: .removedFromContinue, at: t0)
    return s
}

private func entry(_ id: String = "tt0137523", item: String? = nil, season: Int? = nil, episode: Int? = nil,
                   position: Double = 1800, duration: Double = 6000, at: Date, watched: Bool = false) -> NuvioProgressEntry {
    NuvioProgressEntry(id: id, item: MetaPreview(id: item ?? id, type: season == nil ? "movie" : "series", name: "T"),
                       season: season, episode: episode, position: position, duration: duration, updated: at,
                       watched: watched)
}

// MARK: Store

@Test func nuvioStateRoundTrip() throws {
    let store = NuvioStateStore(storage: MemoryBlobs())
    let s = sample()
    try store.save(s, profile: profile)
    #expect(store.load(profile) == s)
    #expect(NuvioStateStore.name(profile) == "nuvio-00000000-0000-4000-8000-0000000000AA.json")
}

@Test func nuvioStateLoadsUnknownMissingAndUnreadableFiles() throws {
    let blobs = MemoryBlobs()
    let store = NuvioStateStore(storage: blobs)
    #expect(store.load(profile) == NuvioState())
    try blobs.write(NuvioStateStore.name(profile), Data(#"{"profileIndex":3,"somethingNew":{"a":1},"usesPrimaryAddons":true}"#.utf8))
    let partial = store.load(profile)
    #expect(partial.profileIndex == 3 && partial.outbox.isEmpty && !partial.bootstrapDone && partial.remoteIDs.isEmpty)
    try blobs.write(NuvioStateStore.name(profile), Data(#"{"profileIndex":"three","bootstrapDone":true}"#.utf8))
    let wrongType = store.load(profile)
    #expect(wrongType.profileIndex == nil && wrongType.bootstrapDone)
    try blobs.write(NuvioStateStore.name(profile), Data("not json".utf8))
    #expect(store.load(profile) == NuvioState())
}

@Test func nuvioStateBlobBelongsToItsProfileAndGoesWithIt() throws {
    #expect(ProfileBlocks.belongs(NuvioStateStore.name(profile), to: profile))
    let blobs = MemoryBlobs()
    let store = NuvioStateStore(storage: blobs)
    try store.save(sample(), profile: profile)
    #expect(ProfileBlocks.remove(profile: profile, from: blobs) == [NuvioStateStore.name(profile)])
    #expect(store.load(profile) == NuvioState())
}

@Test func nuvioStateHasNoTokenAndNoTrustedAddonFlag() throws {
    let json = String(decoding: try JSONEncoder().encode(sample()), as: UTF8.self)
    for word in ["accessToken", "refreshToken", "token", "email", "usesPrimaryAddons", "pin"] {
        #expect(!json.contains(word))
    }
}

// MARK: Resets

@Test func nuvioResetForAccountClearsEverythingOfTheOldAccount() {
    var s = sample()
    s.resetForAccount("00000000-0000-4000-8000-000000000002")
    #expect(s.userID == "00000000-0000-4000-8000-000000000002")
    #expect(s.profileIndex == nil && s.profileID == nil)
    #expect(s.progressCursor == nil && s.watchedCursor == nil && !s.bootstrapDone && s.lastPullAt == nil)
    #expect(s.remoteIDs.isEmpty && s.outbox.isEmpty && s.staged.isEmpty && s.skipped == 0)
    // Tombstones are local decisions of this profile, not account data: they stay.
    #expect(s.tombstones.map(\.itemID) == ["tt0137523"])
}

@Test func nuvioResetCursorsKeepsTheProfileChoice() {
    var s = sample()
    s.resetCursors()
    #expect(s.progressCursor == nil && s.watchedCursor == nil && !s.bootstrapDone && s.lastPullAt == nil)
    #expect(s.profileIndex == 2 && s.profileID == "00000000-0000-4000-8000-000000000102")
    #expect(!s.outbox.isEmpty && s.remoteIDs == [NuvioIDLink(local: "tt0903747", remote: "tmdb:1396", series: true)])
}

@Test func nuvioChoosingAnotherProfileStartsOver() {
    var s = sample()
    s.choose(NuvioProfile(id: "00000000-0000-4000-8000-000000000102", profileIndex: 2, name: "B"))
    #expect(s.bootstrapDone && !s.outbox.isEmpty)   // same profile: nothing changes
    s.choose(NuvioProfile(id: "00000000-0000-4000-8000-000000000103", profileIndex: 3, name: "C"))
    #expect(s.profileIndex == 3 && s.profileID == "00000000-0000-4000-8000-000000000103")
    #expect(!s.bootstrapDone && s.progressCursor == nil && s.outbox.isEmpty && s.staged.isEmpty && s.remoteIDs.isEmpty)
    s.clearProfile()
    #expect(s.profileIndex == nil && s.profileID == nil && s.userID == "00000000-0000-4000-8000-000000000001")
}

// MARK: Profile check (addendum A3, decision D3)

@Test func nuvioProfileCheck() {
    var s = NuvioState()
    let p2 = NuvioProfile(id: "00000000-0000-4000-8000-000000000102", profileIndex: 2, name: "B")
    #expect(s.matches([p2]) == .notChosen)
    s.choose(p2)
    #expect(s.matches([p2]) == .ok(p2))
    #expect(s.matches([]) == .missing)
    #expect(s.matches([NuvioProfile(id: "00000000-0000-4000-8000-000000000999", profileIndex: 2, name: "B")]) == .replaced)
    var locked = p2
    locked.pinEnabled = true
    #expect(s.matches([locked]) == .pinProtected)
    // `uses_primary_addons` comes from the fresh list, never from the state.
    var shared = p2
    shared.usesPrimaryAddons = true
    #expect(s.matches([shared]) == .ok(shared))
}

@Test func nuvioProfileCheckWithoutStoredIDOrProfileRows() {
    // An account that never created a profile row: index 1 without an id (plan section 7.10).
    var s = NuvioState()
    s.choose(NuvioProfile(profileIndex: 1, name: "Profil 1"))
    #expect(s.profileID == nil)
    #expect(s.matches([]) == .ok(nil))
    let later = NuvioProfile(id: "00000000-0000-4000-8000-000000000101", profileIndex: 1, name: "A")
    #expect(s.matches([later]) == .ok(later))
    var other = NuvioState()
    other.profileIndex = 2
    #expect(other.matches([]) == .missing)
}

// MARK: Staged

@Test func nuvioStagedIsDedupedAndBounded() {
    var s = NuvioState()
    func row(_ c: String, last: Int) -> NuvioProgressRow {
        NuvioProgressRow(contentID: c, contentType: "movie", videoID: c, position: 1, duration: 2, lastWatched: last)
    }
    s.stage(NuvioStaged(itemID: "tt1", row: row("tt1", last: 10), stagedAt: t0))
    s.stage(NuvioStaged(itemID: "tt1", row: row("tt1", last: 20), stagedAt: t0))
    s.stage(NuvioStaged(itemID: "tt1", row: row("tt1", last: 15), stagedAt: t0))
    #expect(s.staged.count == 1 && s.staged[0].lastWatched == 20)
    // A watched item of the same key is a separate entry.
    s.stage(NuvioStaged(itemID: "tt1", watched: NuvioWatchedItem(contentID: "tt1", contentType: "movie", watchedAt: 30),
                        stagedAt: t0))
    #expect(s.staged.count == 2)
    s.unstage(s.staged[0])
    #expect(s.staged.count == 1)
    // One batch, as a sync pass stages its rows (row by row is the same, see the next test, but quadratic in time).
    #expect(s.stage(contentsOf: (0..<(NuvioState.maxStaged + 10)).map {
        NuvioStaged(itemID: "tt\(100 + $0)", row: row("tt\(100 + $0)", last: 100 + $0), stagedAt: t0)
    }) == 11)
    #expect(s.staged.count == NuvioState.maxStaged)
    // Review 2, finding 6: the dropped rows are counted, never silent (the watched tt1 left over plus 10 rows).
    #expect(s.skipped == 11)
    #expect(s.stage(NuvioStaged(itemID: "tt99", row: row("tt99", last: 1), stagedAt: t0)) == 1 && s.skipped == 12)
    #expect(!s.staged.contains { $0.itemID == "tt100" } && s.staged.contains { $0.itemID == "tt409" })
}

/// The former row-by-row `stage(_:)` (linear search, sort on overflow), kept as the reference for the batch.
private func referenceStage(_ s: NuvioStaged, staged: inout [NuvioStaged], skipped: inout Int) -> Int {
    if let i = staged.firstIndex(where: { $0.id == s.id }) {
        if staged[i].lastWatched > s.lastWatched { return 0 }
        staged.remove(at: i)
    }
    staged.append(s)
    guard staged.count > NuvioState.maxStaged else { return 0 }
    staged.sort { $0.lastWatched != $1.lastWatched ? $0.lastWatched > $1.lastWatched : $0.id < $1.id }
    let n = staged.count - NuvioState.maxStaged
    staged.removeLast(n)
    skipped += n
    return n
}

/// A batch stages exactly like the former code row by row: duplicates (newer, equal, older), a watched item of a
/// staged key, overflow at the limit, a row too old to stay and a dropped id coming back newer.
@Test func nuvioStagedBatchEqualsOneByOne() {
    func row(_ c: String, last: Int) -> NuvioStaged {
        NuvioStaged(itemID: c, row: NuvioProgressRow(contentID: c, contentType: "movie", videoID: c, position: 1, duration: 2,
                                                     lastWatched: last), stagedAt: t0)
    }
    var base = NuvioState()
    base.stage(contentsOf: (0..<(NuvioState.maxStaged - 2)).map { row("tt\(1_000 + $0)", last: 1_000 + $0) })
    let rows = [row("tt1500", last: 9_000), row("tt1501", last: 5), row("tt1502", last: 1_502), row("tt5", last: 9_001),
                NuvioStaged(itemID: "tt5", watched: NuvioWatchedItem(contentID: "tt5", contentType: "movie", watchedAt: 9_002),
                            stagedAt: t0),
                row("tt6", last: 9_003), row("tt7", last: 1), row("tt1000", last: 9_004), row("tt8", last: 9_005),
                row("tt1001", last: 9_006), row("tt6", last: 9_007), row("tt1002", last: 3)]
    var refStaged = base.staged, refSkipped = base.skipped, refDropped = 0
    for r in rows { refDropped += referenceStage(r, staged: &refStaged, skipped: &refSkipped) }
    var batch = base, single = base
    #expect(batch.stage(contentsOf: rows) == refDropped && refDropped > 0)
    #expect(batch.staged == refStaged && batch.skipped == refSkipped && refStaged.count == NuvioState.maxStaged)
    #expect(rows.map { single.stage($0) }.reduce(0, +) == refDropped)
    #expect(single.staged == refStaged && single.skipped == refSkipped)
}

// MARK: Tombstones (addendum A4)

@Test func nuvioTombstoneDropsOlderAndEqualPulledRows() {
    var s = NuvioState()
    s.tombstone(itemID: "tt0137523", kind: .removedFromContinue, at: t0)
    #expect(s.filterPulled([entry(at: t0.addingTimeInterval(-60)), entry(at: t0)]).isEmpty)
    #expect(s.tombstones.count == 1)
    let other = entry("tt2", at: t0.addingTimeInterval(-60))
    #expect(s.filterPulled([other]) == [other])
}

@Test func nuvioStrictlyNewerRowWinsAndClearsTheTombstone() {
    var s = NuvioState()
    s.tombstone(itemID: "tt0903747", kind: .removedFromContinue, at: t0)
    let newer = entry("tt0903747:1:3", item: "tt0903747", season: 1, episode: 3, at: t0.addingTimeInterval(1))
    let older = entry("tt0903747:1:2", item: "tt0903747", season: 1, episode: 2, at: t0.addingTimeInterval(-100))
    // Every row of the batch is judged against the tombstone as it was: the older episode stays out.
    #expect(s.filterPulled([newer, older]) == [newer])
    #expect(s.tombstones.isEmpty)
}

@Test func nuvioContinueTombstoneLetsWatchedRowsPassButUnwatchedDoesNot() {
    var s = NuvioState()
    s.tombstone(itemID: "tt1", kind: .removedFromContinue, at: t0)
    let watched = entry("tt1", position: 0, duration: 0, at: t0.addingTimeInterval(-5), watched: true)
    let finishedByLength = entry("tt1", position: 5900, duration: 6000, at: t0.addingTimeInterval(-5))
    #expect(s.filterPulled([watched]) == [watched])
    #expect(s.filterPulled([finishedByLength]) == [finishedByLength])
    #expect(s.tombstones.count == 1)   // an older row passing does not clear it
    s.tombstone(itemID: "tt1", kind: .markedUnwatched, at: t0)
    #expect(s.tombstones.count == 1 && s.tombstones[0].kind == .markedUnwatched)
    #expect(s.filterPulled([watched, finishedByLength]).isEmpty)
}

@Test func nuvioTombstoneDropsPendingPushesOfTheTitle() {
    var s = NuvioState()
    s.remoteIDs = [NuvioIDLink(local: "tt0903747", remote: "tmdb:1396", series: true)]
    s.outbox.note(NuvioProgressPush(contentID: "tmdb:1396", contentType: "series", videoID: "tmdb:1396:1:1", season: 1,
                                    episode: 1, position: 1, duration: 2, lastWatched: 3), now: t0)
    s.outbox.note(NuvioProgressPush(contentID: "tt5", contentType: "movie", videoID: "tt5", position: 1, duration: 2,
                                    lastWatched: 3), now: t0)
    s.tombstone(itemID: "tt0903747", kind: .markedUnwatched, at: t0)
    #expect(s.outbox.keys == ["tt5"])
}

@Test func nuvioTombstonesAreBounded() {
    var s = NuvioState()
    s.tombstone(itemID: "ttold", kind: .removedFromContinue, at: t0)
    for i in 0..<(NuvioState.maxTombstones + 3) {
        s.tombstone(itemID: "tt\(i)", kind: .markedUnwatched, at: t0.addingTimeInterval(Double(10 + i)))
    }
    #expect(s.tombstones.count == NuvioState.maxTombstones)
    #expect(!s.tombstones.contains { $0.itemID == "ttold" || $0.itemID == "tt0" })
    s.prune(now: t0.addingTimeInterval(NuvioState.tombstoneMaxAge + 20))
    #expect(s.tombstones.allSatisfy { $0.at >= t0.addingTimeInterval(20) })
    #expect(!s.tombstones.contains { $0.itemID == "tt9" } && s.tombstones.contains { $0.itemID == "tt10" })
}

// MARK: Review 2 (finding 17)

@Test func nuvioStateDescriptionHidesAccountAndProfileIDs() {
    let s = sample()
    for text in [String(describing: s), String(reflecting: s), "\(s)", String(describing: Mirror(reflecting: s).children.map(\.value))] {
        for secret in ["00000000-0000-4000-8000-000000000001", "00000000-0000-4000-8000-000000000102", "tmdb:1396", "tt0903747"] {
            #expect(!text.contains(secret), "\(text)")
        }
    }
    #expect(String(describing: s).contains("profileIndex: 2"))
}
