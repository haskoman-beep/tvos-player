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

@Test func prunedKeepsNewestOpenEntriesAndSources() {
    // 700 started films, all older than 18 months: the newest 500 stay; finished ones are counted separately.
    var b = book(finished: 5, open: 700, offset: 600)
    b.rememberSource(StreamItem(name: "Q", title: "datei.mkv"), addon: "A", for: "tt5000", now: now)
    let p = b.pruned(now: now)
    #expect(p.entries.values.filter { !$0.finished }.count == 500)
    #expect(p.entries.values.filter(\.finished).count == 5)
    #expect(p.entries["tt5000"] != nil && p.entries["tt5499"] != nil && p.entries["tt5500"] == nil)
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
