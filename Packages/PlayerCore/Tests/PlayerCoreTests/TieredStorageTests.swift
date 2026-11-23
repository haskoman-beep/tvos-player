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
    for i in 0..<20 { try s.write("p\(i).json", bytes(30_000)) }
    let sizes = s.defaultsSizes()
    #expect(sizes.values.reduce(0, +) <= TieredBlobStorage.budget)
    #expect(sizes.filter { $0.key != "profiles.json" }.values.reduce(0, +) <= TieredBlobStorage.othersBudget)
    for i in 0..<20 { #expect(s.read("p\(i).json") == bytes(30_000)) }
    #expect(kv.keys(withPrefix: "blob.").count < 21)
}

@Test func profilesAlwaysFitEvenWhenOthersFillBudget() throws {
    let (s, kv, _) = tiered()
    for i in 0..<10 { try s.write("progress-\(i).json", bytes(40_000)) }   // füllt das Restbudget
    #expect(s.defaultsSizes().values.reduce(0, +) <= TieredBlobStorage.othersBudget)
    try s.write("profiles.json", bytes(400_000, 5))
    #expect(kv.data(forKey: "blob.profiles.json") == bytes(400_000, 5))
    #expect(s.defaultsSizes().values.reduce(0, +) <= TieredBlobStorage.budget)
}

@Test func normalBlobUsesRemainingBudgetUpToLimit() throws {
    let (s, kv, _) = tiered()
    try s.write("progress-a.json", bytes(90_000))
    #expect(kv.data(forKey: "blob.progress-a.json") != nil)
    try s.write("progress-b.json", bytes(TieredBlobStorage.othersBudget - 90_000))
    #expect(kv.data(forKey: "blob.progress-b.json") != nil)
    try s.write("progress-c.json", bytes(1))
    #expect(kv.data(forKey: "blob.progress-c.json") == nil && s.read("progress-c.json") == bytes(1))
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

@Test func fileGoesToEveryWritableDir() throws {
    let (s, _, d) = tiered()
    try s.write("progress-a.json", bytes(200_000, 2))
    #expect(d.allSatisfy { $0.read("progress-a.json") == bytes(200_000, 2) })
}

@Test func readPicksNewestFileCopy() throws {
    let (s, _, d) = tiered()
    try d[0].write("progress-a.json", bytes(200_000, 1))
    try d[1].write("progress-a.json", bytes(200_000, 2))
    let fm = FileManager.default
    try fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -3600)], ofItemAtPath: d[0].url("progress-a.json").path)
    try fm.setAttributes([.modificationDate: Date()], ofItemAtPath: d[1].url("progress-a.json").path)
    #expect(s.read("progress-a.json") == bytes(200_000, 2))
    try fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: 60)], ofItemAtPath: d[0].url("progress-a.json").path)
    #expect(s.read("progress-a.json") == bytes(200_000, 1))
}

@Test func droppedDefaultsWriteFallsBackToFile() throws {
    let kv = MemoryKeyValueBlobs(["blob.progress-a.json": bytes(10, 1)])
    let (s, _, _) = tiered(kv)
    kv.dropsWrites = true
    try s.write("progress-a.json", bytes(10, 2))
    #expect(kv.data(forKey: "blob.progress-a.json") == nil)        // alter Stand gelöscht
    #expect(s.read("progress-a.json") == bytes(10, 2))
    // Ohne beschreibbare Datei ist das ein Fehler.
    let s2 = TieredBlobStorage(defaults: kv, directories: [blockedDir()])
    #expect(throws: TieredBlobStorage.StorageFull.self) { try s2.write("progress-b.json", bytes(10)) }
}

@Test func largeBlobWithoutAnyWritableFileThrows() {
    let s = TieredBlobStorage(defaults: MemoryKeyValueBlobs(), directories: [blockedDir()])
    #expect(throws: TieredBlobStorage.StorageFull.self) { try s.write("progress-a.json", bytes(200_000)) }
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
    var vals: [String: Data] = ["blob.profiles.json": bytes(500_000)]
    for i in 0..<15 { vals["blob.progress-\(i).json"] = bytes(15_000) }
    let kv = MemoryKeyValueBlobs(vals)
    let (s, _, _) = tiered(kv)
    let m = s.migrate()
    #expect(m.kept.first == "profiles.json" && !m.moved.contains("profiles.json"))
    #expect(kv.data(forKey: "blob.profiles.json") != nil)
    #expect(s.defaultsSizes().values.reduce(0, +) <= TieredBlobStorage.budget)
    #expect(!m.moved.isEmpty)
    for i in 0..<15 { #expect(s.read("progress-\(i).json") == bytes(15_000)) }
}

@Test func migrationKeepsEntryWhenNoFileWritable() {
    let kv = MemoryKeyValueBlobs(["blob.progress-a.json": bytes(200_000)])
    let s = TieredBlobStorage(defaults: kv, directories: [blockedDir()])
    let m = s.migrate()
    #expect(m.failed == ["progress-a.json"])
    #expect(kv.data(forKey: "blob.progress-a.json") != nil)
}

@Test func migrationSavesUndecodableRawBlob() {
    let kv = MemoryKeyValueBlobs(["blob.progress-a.json": bytes(200_000)])
    let dir = FileBlobStorage(directory: tempDir())
    let s = TieredBlobStorage(defaults: kv, directories: [dir], decompress: { _ in nil })
    #expect(s.migrate().moved == ["progress-a.json"])
    #expect(dir.read("progress-a.json.defaults-raw") == bytes(200_000))
}

@Test func profileAndProgressStoresWorkOnTieredStorage() throws {
    let (s, _, _) = tiered()
    let ps = ProfileStore(storage: s)
    var p = StoredProfiles.makeDefault(); p.profiles[0].name = "Gestuft"
    try ps.save(p)
    #expect(ps.load().profiles == p)
    let prog = ProgressStore(storage: s)
    let id = UUID()
    var book = ProgressBook()
    book.record(id: "tt1", item: MetaPreview(id: "tt1", type: "movie", name: "A"), season: nil, episode: nil, position: 10, duration: 100)
    try prog.save(book, profile: id)
    #expect(prog.load(profile: id).entries.count == 1)
}

@Test func readsFromReadOnlyDirButWritesOnlyToWritable() throws {
    let kv = MemoryKeyValueBlobs()
    let old = FileBlobStorage(directory: tempDir()), cur = FileBlobStorage(directory: tempDir())
    try old.write("progress-a.json", bytes(200_000, 1))           // Altbestand im nun gesperrten Ordner
    let s = TieredBlobStorage(defaults: kv, directories: [old, cur], writeDirectories: [cur])
    #expect(s.read("progress-a.json") == bytes(200_000, 1))
    try s.write("progress-b.json", bytes(200_000, 2))
    #expect(old.read("progress-b.json") == nil && cur.read("progress-b.json") == bytes(200_000, 2))
}

@Test func reportsProfilesOnlyInFile() throws {
    final class Box: @unchecked Sendable { var sizes: [Int] = [] }
    let box = Box()
    let kv = MemoryKeyValueBlobs()
    let s = TieredBlobStorage(defaults: kv, directories: [FileBlobStorage(directory: tempDir())],
                              onProfilesFileOnly: { box.sizes.append($0) })
    try s.write("profiles.json", bytes(1000))
    #expect(box.sizes.isEmpty)
    try s.write("profiles.json", bytes(TieredBlobStorage.profileLimit + 1))
    #expect(box.sizes == [TieredBlobStorage.profileLimit + 1])
    kv.dropsWrites = true
    try s.write("profiles.json", bytes(10))
    #expect(box.sizes.count == 2 && box.sizes.last == 10)
    try s.write("progress-a.json", bytes(10))                       // andere Blöcke melden nichts
    #expect(box.sizes.count == 2)
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

@Test func timedCacheGenerationBlocksStoreAfterClear() {
    var c = TimedCache<[Int]>()
    let g = c.generation
    let r1 = c.store([1], for: "a", generation: g); #expect(r1)
    c.removeAll()
    #expect(c.generation == g + 1)
    let r2 = c.store([2], for: "a", generation: g); #expect(!r2)   // Abruf von vor dem Leeren
    #expect(c["a"] == nil)
    let r3 = c.store([3], for: "a", generation: c.generation); #expect(r3 && c["a"] == [3])
}

@Test func timedCacheEmptyRefreshKeepsFilledList() {
    var c = TimedCache<[Int]>()
    let t0 = Date(timeIntervalSince1970: 0)
    c.store([1, 2], for: "a", now: t0)
    let e1 = c.storeRefreshed([], for: "a", generation: c.generation, now: t0 + 10); #expect(!e1)
    #expect(c["a"] == [1, 2] && c.storedAt("a") == t0)
    let e2 = c.storeRefreshed([3], for: "a", generation: c.generation, now: t0 + 20); #expect(e2 && c["a"] == [3])
    c.store([], for: "b")
    let e3 = c.storeRefreshed([], for: "b", generation: c.generation); #expect(e3)   // leer → leer ist in Ordnung
}

@Test func timedCacheDefaultLifetimeIsADay() {
    let c = TimedCache<Int>()
    #expect(c.lifetime == 24 * 3600)
}

// Wave F-o round 4: import blobs (media snapshot of a collection link, pasted widget export) are files only.
@Test func importBlobStaysOutOfDefaultsAtAnySize() throws {
    let (s, kv, d) = tiered()
    let name = TieredBlobStorage.fileOnlyPrefix + "media-p-1.json"
    #expect(TieredBlobStorage.limit(name) == 0)
    for n in [1, 200, TieredBlobStorage.smallLimit, 170_000] {
        try s.write(name, bytes(n))
        #expect(kv.data(forKey: "blob." + name) == nil)
        #expect(d[0].read(name)?.count == n)
        #expect(d[1].read(name)?.count == n)
        #expect(s.read(name)?.count == n)
    }
    #expect(s.defaultsSizes().isEmpty)
}

@Test func manyImportBlobsLeaveDefaultsBudgetToOthers() throws {
    let (s, _, _) = tiered()
    try s.write("progress-a.json", bytes(50_000))
    for i in 0..<30 { try s.write(TieredBlobStorage.fileOnlyPrefix + "media-p-\(i).json", bytes(170_000)) }
    #expect(s.defaultsSizes() == ["progress-a.json": 50_000])
}

@Test func importBlobFallsBackToSecondDirectory() throws {
    let good = FileBlobStorage(directory: tempDir())
    let kv = MemoryKeyValueBlobs()
    let s = TieredBlobStorage(defaults: kv, directories: [blockedDir(), good])
    let name = TieredBlobStorage.fileOnlyPrefix + "paste-1.json"
    try s.write(name, bytes(5000))
    #expect(good.read(name) == bytes(5000))
    #expect(s.read(name) == bytes(5000))
    #expect(kv.data(forKey: "blob." + name) == nil)
    s.remove(name)
    #expect(s.read(name) == nil)
}

@Test func importBlobWithoutWritableDirectoryThrows() {
    let s = TieredBlobStorage(defaults: MemoryKeyValueBlobs(), directories: [blockedDir()])
    #expect(throws: TieredBlobStorage.StorageFull.self) {
        try s.write(TieredBlobStorage.fileOnlyPrefix + "paste-1.json", bytes(10))
    }
}

// Wave F-o round 4 (R4-1): a one-time move reports every blob that was not stored, so the old copy can stay.
@Test func adoptMissingWritesAllAndKeepsNewerBlobs() throws {
    let (s, kv, _) = tiered()
    let media = TieredBlobStorage.fileOnlyPrefix + "media-p-1.json"
    try s.write("linkpack-p-2.json", bytes(40, 3))   // already there, newer than the copy being moved
    let failed = s.adoptMissing([(media, bytes(170_000)), ("linkpack-p-1.json", bytes(500)), ("linkpack-p-2.json", bytes(40, 1))])
    #expect(failed.isEmpty)
    #expect(s.read(media) == bytes(170_000))
    #expect(kv.data(forKey: "blob." + media) == nil)
    #expect(s.read("linkpack-p-1.json") == bytes(500))
    #expect(s.read("linkpack-p-2.json") == bytes(40, 3))
}

@Test func adoptMissingReportsFailedBlobs() {
    let s = TieredBlobStorage(defaults: MemoryKeyValueBlobs(), directories: [blockedDir()])
    let media = TieredBlobStorage.fileOnlyPrefix + "media-p-1.json"
    // The small pack still fits the key-value store; the file-only snapshot has nowhere to go.
    let failed = s.adoptMissing([(media, bytes(1000)), ("linkpack-p-1.json", bytes(500))])
    #expect(failed == [media])
    #expect(s.read("linkpack-p-1.json") == bytes(500))
    #expect(s.adoptMissing([]) == [])
}
