import Foundation
import Testing
@testable import PlayerCore

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private let day = 86_400.0
private let show = MetaPreview(id: "tt900", type: "series", name: "Serie")

/// Book with `finished` watched episodes and `open` started ones; entry i is i days old (+ `offset` days).
private func book(finished: Int, open: Int = 0, offset: Double = 0) -> ProgressBook {
    var b = ProgressBook()
    for i in 0..<finished {
        let id = "tt900:1:\(i)"
        b.entries[id] = WatchProgress(id: id, item: show, season: 1, episode: i, position: 0, duration: 2400,
                                      updated: now.addingTimeInterval(-(offset + Double(i)) * day), finished: true)
    }
    for i in 0..<open {
        let id = "tt\(5000 + i)"
        b.entries[id] = WatchProgress(id: id, item: MetaPreview(id: id, type: "movie", name: "F\(i)"),
                                      position: 600, duration: 6000,
                                      updated: now.addingTimeInterval(-(offset + Double(i)) * day))
    }
    return b
}

@Test func prunedDropsOnlyOldFinishedBeyondQuota() {
    // 2000 watched episodes, the oldest are far beyond 18 months: the newest 1500 stay.
    let b = book(finished: 2000)
    let p = b.pruned(now: now)
    #expect(p.entries.count == 1500)
    #expect(p.entries["tt900:1:0"] != nil)
    #expect(p.entries["tt900:1:1499"] != nil)
    #expect(p.entries["tt900:1:1500"] == nil)
}

@Test func prunedNeverDropsEntriesYoungerThan18Months() {
    // 1700 watched episodes, all within the last 18 months: over quota, but nothing is old enough.
    var b = ProgressBook()
    for i in 0..<1700 {
        let id = "tt900:2:\(i)"
        b.entries[id] = WatchProgress(id: id, item: show, season: 2, episode: i, position: 0, duration: 2400,
                                      updated: now.addingTimeInterval(-Double(i) * 0.25 * day), finished: true)
    }
    #expect(b.pruned(now: now) == b)
    // Small books stay unchanged however old they are.
    let small = book(finished: 10, open: 10, offset: 3000)
    #expect(small.pruned(now: now) == small)
}

@Test func prunedNeverDropsOpenEntriesOrSeriesMarkers() {
    // 700 started films and 1600 watched episodes, all older than 18 months: only finished episodes are pruned.
    var b = book(finished: 1600, open: 700, offset: 600)
    // Series marker ("whole series watched"), the oldest finished entry of all.
    b.entries["tt900"] = WatchProgress(id: "tt900", item: show, position: 0, duration: 0,
                                       updated: now.addingTimeInterval(-5000 * day), finished: true)
    b.rememberSource(StreamItem(name: "Q", title: "datei.mkv"), addon: "A", for: "tt5000", now: now)
    let p = b.pruned(now: now)
    #expect(p.entries.values.filter { !$0.finished }.count == 700)
    #expect(p.entries.values.filter { $0.finished && $0.season != nil }.count == 1500)
    #expect(p.entries["tt900"]?.finished == true)
    #expect(p.sources == b.sources)
    #expect(p.schemaVersion == b.schemaVersion)
}

@Test func storeSavePrunesAndReportsCount() throws {
    let s = MemoryBlobStorageForPrune()
    let counts = PruneCounts()
    let store = ProgressStore(storage: s, onPruned: { counts.add($0) })
    let profile = UUID()
    try store.save(book(finished: 1600, offset: 600), profile: profile, now: now)
    let loaded = try #require(store.load(profile: profile))
    #expect(loaded.entries.count == 1500)
    #expect(counts.all == [100])
    // Nothing to prune: no report.
    try store.save(loaded, profile: profile, now: now)
    #expect(counts.all == [100])
    // Contract for the app: prune once (also at load), keep the result, later saves report nothing again.
    let kept = store.prune(book(finished: 1550, offset: 600), now: now)
    #expect(kept.entries.count == 1500 && counts.all == [100, 50])
    let written = try store.save(kept, profile: profile, now: now)
    #expect(written == kept && counts.all == [100, 50])
}

@Test func progressFallingOutOfDefaultsIsReported() throws {
    let names = PruneNames()
    let kv = MemoryKeyValueBlobs()
    let s = TieredBlobStorage(defaults: kv, directories: [FileBlobStorage(directory: tempDir())],
                              onProgressFileOnly: { names.add($0) })
    try s.write("progress-a.json", Data(repeating: 1, count: 1000))
    #expect(names.all.isEmpty)
    try s.write("trackmemory-a.json", Data(repeating: 2, count: TieredBlobStorage.smallLimit + 1))
    #expect(names.all.isEmpty)
    try s.write("progress-a.json", Data(repeating: 3, count: TieredBlobStorage.smallLimit + 1))
    #expect(names.all == ["progress-a.json"])
    try s.write("progress-a.json.bak", Data(repeating: 4, count: 10))
    #expect(names.all == ["progress-a.json"])
    // No folder writable: nothing was saved, so no "only as a file" report (StorageFull is thrown instead).
    let blockedFile = tempDir().appendingPathComponent("datei")
    try Data("x".utf8).write(to: blockedFile)
    let none = TieredBlobStorage(defaults: MemoryKeyValueBlobs(),
                                 directories: [FileBlobStorage(directory: blockedFile.appendingPathComponent("unter"))],
                                 onProgressFileOnly: { names.add($0) })
    #expect(throws: TieredBlobStorage.StorageFull.self) {
        try none.write("progress-b.json", Data(repeating: 5, count: TieredBlobStorage.smallLimit + 1))
    }
    #expect(names.all == ["progress-a.json"])
}

@Test func pruneCutoffIsExactly18Months() {
    // 1500 young entries plus two old ones (over quota by two): one just inside 18 months stays, one just
    // outside goes.
    var b = ProgressBook()
    for i in 0..<1500 {
        let id = "tt900:3:\(i)"
        b.entries[id] = WatchProgress(id: id, item: show, season: 3, episode: i, position: 0, duration: 2400,
                                      updated: now.addingTimeInterval(-Double(i) * 0.25 * day), finished: true)
    }
    let cutoff = ProgressBook.pruneCalendar.date(byAdding: .month, value: -18, to: now)!
    b.entries["tt900:9:1"] = WatchProgress(id: "tt900:9:1", item: show, season: 9, episode: 1, position: 0,
                                           duration: 2400, updated: cutoff.addingTimeInterval(1), finished: true)
    b.entries["tt900:9:2"] = WatchProgress(id: "tt900:9:2", item: show, season: 9, episode: 2, position: 0,
                                           duration: 2400, updated: cutoff.addingTimeInterval(-1), finished: true)
    let p = b.pruned(now: now)
    #expect(p.entries["tt900:9:1"] != nil)
    #expect(p.entries["tt900:9:2"] == nil)
    #expect(p.entries.count == 1501)
}

private final class MemoryBlobStorageForPrune: BlobStorage, @unchecked Sendable {
    private var blobs: [String: Data] = [:]
    private let lock = NSLock()
    func read(_ name: String) -> Data? { lock.withLock { blobs[name] } }
    func write(_ name: String, _ data: Data) throws { lock.withLock { blobs[name] = data } }
    func remove(_ name: String) { _ = lock.withLock { blobs.removeValue(forKey: name) } }
}

private final class PruneCounts: @unchecked Sendable {
    private var values: [Int] = []
    private let lock = NSLock()
    func add(_ v: Int) { lock.withLock { values.append(v) } }
    var all: [Int] { lock.withLock { values } }
}

private final class PruneNames: @unchecked Sendable {
    private var values: [String] = []
    private let lock = NSLock()
    func add(_ v: String) { lock.withLock { values.append(v) } }
    var all: [String] { lock.withLock { values } }
}
