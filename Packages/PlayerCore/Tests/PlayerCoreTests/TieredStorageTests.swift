import Foundation
import Testing
@testable import PlayerCore

private func tiered(_ kv: MemoryKeyValueBlobs = MemoryKeyValueBlobs(), dirs: Int = 2) -> (TieredBlobStorage, MemoryKeyValueBlobs, [FileBlobStorage]) {
    let d = (0..<dirs).map { _ in FileBlobStorage(directory: tempDir()) }
    return (TieredBlobStorage(defaults: kv, directories: d), kv, d)
}

private func bytes(_ n: Int, _ v: UInt8 = 7) -> Data { Data(repeating: v, count: n) }

/// Ordner, der sich nicht anlegen lässt (Datei im Weg) – simuliert tvOS-Code 513.
private func blockedDir() -> FileBlobStorage {
    let f = tempDir().appendingPathComponent("datei")
    try? Data("x".utf8).write(to: f)
    return FileBlobStorage(directory: f.appendingPathComponent("unter"))
}

@Test func smallBlobGoesToDefaultsAndFile() throws {
    let (s, kv, d) = tiered()
    try s.write("progress-a.json", bytes(1000))
    #expect(kv.data(forKey: "blob.progress-a.json")?.count == 1000)
    #expect(d[0].read("progress-a.json") == bytes(1000))
    #expect(s.read("progress-a.json") == bytes(1000))
}

@Test func largeBlobOnlyInFileAndOldDefaultsEntryRemoved() throws {
    let (s, kv, d) = tiered()
    try s.write("progress-a.json", bytes(100))
    try s.write("progress-a.json", bytes(TieredBlobStorage.smallLimit + 1, 9))
    #expect(kv.data(forKey: "blob.progress-a.json") == nil)
    #expect(d[0].read("progress-a.json")?.count == TieredBlobStorage.smallLimit + 1)
    #expect(s.read("progress-a.json") == bytes(TieredBlobStorage.smallLimit + 1, 9))
}

@Test func profilesMayUseMoreDefaultsSpaceBackupNone() throws {
    let (s, kv, _) = tiered()
    try s.write("profiles.json", bytes(60_000))
    try s.write("profiles.json.bak", bytes(10))
    #expect(kv.data(forKey: "blob.profiles.json")?.count == 60_000)
    #expect(kv.data(forKey: "blob.profiles.json.bak") == nil)
    #expect(s.read("profiles.json.bak") == bytes(10))
}

@Test func budgetCapsTotalDefaults() throws {
    let (s, kv, _) = tiered()
    try s.write("profiles.json", bytes(TieredBlobStorage.profileLimit))
    try s.write("profiles2.json", bytes(1))           // normaler Name, passt noch
    for i in 0..<20 { try s.write("p\(i).json", bytes(TieredBlobStorage.smallLimit)) }
    let total = s.defaultsSizes().values.reduce(0, +)
    #expect(total <= TieredBlobStorage.budget)
    for i in 0..<20 { #expect(s.read("p\(i).json") == bytes(TieredBlobStorage.smallLimit)) }
    #expect(kv.keys(withPrefix: "blob.").count < 22)
}

@Test func unwritablePreferredDirFallsBackToSecond() throws {
    let kv = MemoryKeyValueBlobs()
    let good = FileBlobStorage(directory: tempDir())
    let s = TieredBlobStorage(defaults: kv, directories: [blockedDir(), good])
    #expect(!blockedDir().isWritable && good.isWritable)
    try s.write("progress-a.json", bytes(50_000))
    #expect(good.read("progress-a.json")?.count == 50_000)
    #expect(s.read("progress-a.json")?.count == 50_000)
}

@Test func writingRemovesStaleCopyInOtherDir() throws {
    let (s, _, d) = tiered()
    try d[1].write("progress-a.json", bytes(50_000, 1))   // alte Kopie im Ersatzordner
    try s.write("progress-a.json", bytes(50_000, 2))
    #expect(d[1].read("progress-a.json") == nil)
    #expect(s.read("progress-a.json") == bytes(50_000, 2))
}

@Test func largeBlobWithoutAnyWritableFileThrows() {
    let s = TieredBlobStorage(defaults: MemoryKeyValueBlobs(), directories: [blockedDir()])
    #expect(throws: TieredBlobStorage.StorageFull.self) { try s.write("progress-a.json", bytes(50_000)) }
    // Kleine Blöcke gehen ohne Datei trotzdem (UserDefaults).
    #expect((try? s.write("progress-b.json", bytes(10))) != nil)
    #expect(s.read("progress-b.json") == bytes(10))
}

@Test func compressionAppliesOnlyToDefaults() throws {
    let kv = MemoryKeyValueBlobs()
    let dir = FileBlobStorage(directory: tempDir())
    // „Kompression“: erstes Byte weglassen; Entpacken hängt es wieder an.
    let s = TieredBlobStorage(defaults: kv, directories: [dir],
                              compress: { Data($0.dropFirst()) }, decompress: { Data([0]) + $0 })
    let raw = Data([0, 1, 2, 3])
    try s.write("x.json", raw)
    #expect(kv.data(forKey: "blob.x.json") == Data([1, 2, 3]))
    #expect(dir.read("x.json") == raw)
    #expect(s.read("x.json") == raw)
}

@Test func removeClearsEverywhere() throws {
    let (s, kv, d) = tiered()
    try s.write("a.json", bytes(10))
    s.remove("a.json")
    #expect(kv.data(forKey: "blob.a.json") == nil && d.allSatisfy { $0.read("a.json") == nil } && s.read("a.json") == nil)
}

@Test func migrationMovesOversizedAndKeepsSmall() {
    let kv = MemoryKeyValueBlobs([
        "blob.profiles.json": bytes(5000),
        "blob.profiles.json.bak": bytes(4000, 2),
        "blob.progress-a.json": bytes(400_000, 3),
        "blob.progress-b.json": bytes(2000, 4),
        "andere.einstellung": bytes(10),
    ])
    let (s, _, d) = tiered(kv)
    let m = s.migrate()
    #expect(Set(m.moved) == ["profiles.json.bak", "progress-a.json"])
    #expect(Set(m.kept) == ["profiles.json", "progress-b.json"])
    #expect(m.failed.isEmpty)
    #expect(kv.data(forKey: "blob.progress-a.json") == nil && kv.data(forKey: "blob.profiles.json.bak") == nil)
    #expect(d[0].read("progress-a.json") == bytes(400_000, 3))
    #expect(s.read("progress-a.json") == bytes(400_000, 3))
    #expect(s.read("profiles.json.bak") == bytes(4000, 2))
    #expect(kv.data(forKey: "andere.einstellung") == bytes(10))   // fremde Schlüssel unberührt
    // Zweiter Lauf: nichts mehr zu tun.
    #expect(s.migrate().moved.isEmpty)
}

@Test func migrationRespectsBudgetProfilesFirst() {
    var vals: [String: Data] = ["blob.profiles.json": bytes(100_000)]
    for i in 0..<15 { vals["blob.progress-\(i).json"] = bytes(15_000) }
    let kv = MemoryKeyValueBlobs(vals)
    let (s, _, _) = tiered(kv)
    let m = s.migrate()
    #expect(m.kept.first == "profiles.json")
    #expect(s.defaultsSizes().values.reduce(0, +) <= TieredBlobStorage.budget)
    #expect(!m.moved.isEmpty)
    for i in 0..<15 { #expect(s.read("progress-\(i).json") == bytes(15_000)) }
}

@Test func migrationKeepsEntryWhenNoFileWritable() {
    let kv = MemoryKeyValueBlobs(["blob.progress-a.json": bytes(50_000)])
    let s = TieredBlobStorage(defaults: kv, directories: [blockedDir()])
    let m = s.migrate()
    #expect(m.failed == ["progress-a.json"])
    #expect(kv.data(forKey: "blob.progress-a.json") != nil)
}

@Test func migrationSavesUndecodableRawBlob() {
    let kv = MemoryKeyValueBlobs(["blob.progress-a.json": bytes(50_000)])
    let dir = FileBlobStorage(directory: tempDir())
    let s = TieredBlobStorage(defaults: kv, directories: [dir], decompress: { _ in nil })
    #expect(s.migrate().moved == ["progress-a.json"])
    #expect(dir.read("progress-a.json.defaults-raw") == bytes(50_000))
}

@Test func profileAndProgressStoresWorkOnTieredStorage() throws {
    let (s, _, _) = tiered()
    let ps = ProfileStore(storage: s)
    var p = StoredProfiles.makeDefault(); p.profiles[0].name = "Gestuft"
    try ps.save(p)
    #expect(ps.load() == p)
    let prog = ProgressStore(storage: s)
    let id = UUID()
    var book = ProgressBook()
    book.record(id: "tt1", item: MetaPreview(id: "tt1", type: "movie", name: "A"), season: nil, episode: nil, position: 10, duration: 100)
    try prog.save(book, profile: id)
    #expect(prog.load(profile: id).entries.count == 1)
}

// MARK: TimedCache

@Test func timedCacheFreshStaleAndRetry() {
    var c = TimedCache<[Int]>(lifetime: 100, retryAfter: 10)
    let t0 = Date(timeIntervalSince1970: 1000)
    #expect(c["a"] == nil && c.isStale("a", now: t0) && !c.needsRefresh("a", now: t0))
    c.store([1], for: "a", now: t0)
    #expect(c["a"] == [1] && !c.isStale("a", now: t0 + 99) && !c.needsRefresh("a", now: t0 + 99))
    #expect(c.isStale("a", now: t0 + 100) && c.needsRefresh("a", now: t0 + 100))
    #expect(c.keysNeedingRefresh(now: t0 + 100) == ["a"])
    c.markFailed("a", now: t0 + 100)
    #expect(c["a"] == [1])                                   // alter Stand bleibt sichtbar
    #expect(!c.needsRefresh("a", now: t0 + 105))
    #expect(c.needsRefresh("a", now: t0 + 110))
    c.store([2], for: "a", now: t0 + 111)
    #expect(c["a"] == [2] && !c.needsRefresh("a", now: t0 + 150) && c.storedAt("a") == t0 + 111)
    c.removeAll()
    #expect(c["a"] == nil)
}

@Test func timedCacheDefaultLifetimeIsADay() {
    let c = TimedCache<Int>()
    #expect(c.lifetime == 24 * 3600)
}
