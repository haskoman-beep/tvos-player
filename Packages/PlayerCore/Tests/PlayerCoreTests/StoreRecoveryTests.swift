import Foundation
import Testing
@testable import PlayerCore

// Task 1.3 (S-1, S-11): loading never leads to overwriting; the last two good versions stay.

private func named(_ name: String, schema: Int = 1) -> StoredProfiles {
    var s = StoredProfiles.makeDefault(); s.profiles[0].name = name; s.schemaVersion = schema
    return s
}

private func encoded(_ s: StoredProfiles) throws -> Data { try JSONEncoder().encode(s) }

private let t0 = Date(timeIntervalSince1970: 1_700_000_000)   // before the real clock: .bak dates (now) are newer

private func tieredStore(_ kv: MemoryKeyValueBlobs = MemoryKeyValueBlobs(), dirs: Int = 2)
    -> (ProfileStore, TieredBlobStorage, MemoryKeyValueBlobs, [FileBlobStorage]) {
    let d = (0..<dirs).map { _ in FileBlobStorage(directory: tempDir()) }
    let t = TieredBlobStorage(defaults: kv, directories: d)
    return (ProfileStore(storage: t), t, kv, d)
}

private func candidates(_ l: ProfileLoad) -> [RecoveryCandidate] {
    if case .unreadable(_, let c) = l { return c }
    return []
}

// MARK: The seven tests from the brief

@Test func missingFileIsFresh() {
    let store = ProfileStore(directory: tempDir())
    guard case .fresh(let s) = store.loadResult() else { Issue.record("expected .fresh"); return }
    #expect(s.profiles.count == 1 && s.profiles[0].name == "Ich")
}

@Test func garbageIsUnreadableAndNothingIsWritten() throws {
    let dir = tempDir()
    let store = ProfileStore(directory: dir)
    try Data("kaputt{".utf8).write(to: store.fileURL)
    guard case .unreadable(let reason, let c) = store.loadResult() else { Issue.record("expected .unreadable"); return }
    #expect(!reason.isEmpty)
    #expect(c.isEmpty)
    // The unreadable file stays as it is; only the copy in its own slot (and its date) is new.
    #expect(try Data(contentsOf: store.fileURL) == Data("kaputt{".utf8))
    #expect(try Data(contentsOf: store.unreadableURL) == Data("kaputt{".utf8))
    let names = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
    #expect(names == ["profiles.json", "profiles.json.dates", "profiles.json.unreadable.bak"])
}

@Test func truncatedJsonListsGenerationsAsCandidates() throws {
    let store = ProfileStore(directory: tempDir())
    try store.save(named("A"), now: t0)
    try store.save(named("B"), now: t0.addingTimeInterval(1))            // A → .1
    try store.save(named("C"), now: t0.addingTimeInterval(700))          // B → .1, A → .2
    let full = try Data(contentsOf: store.fileURL)
    try full.prefix(full.count / 2).write(to: store.fileURL)             // abgeschnitten
    let c = candidates(store.loadResult())
    #expect(c.map(\.id) == ["profiles.json.1#0", "profiles.json.2#0"])
    #expect(c.allSatisfy { $0.profiles == 1 && $0.savedAt != nil && !$0.label.isEmpty })
}

@Test func restoreFromGeneration1() throws {
    let store = ProfileStore(directory: tempDir())
    try store.save(named("Alt"), now: t0)
    try store.save(named("Neu"), now: t0.addingTimeInterval(1))
    try Data("{\"schemaVersion\":1,\"prof".utf8).write(to: store.fileURL)
    let c = candidates(store.loadResult())
    let s = try store.restore(try #require(c.first).id)
    #expect(s.profiles[0].name == "Alt")
    guard case .loaded(let again, _) = store.loadResult() else { Issue.record("expected .loaded"); return }
    #expect(again.profiles[0].name == "Alt")
    #expect(try Data(contentsOf: store.unreadableURL) == Data("{\"schemaVersion\":1,\"prof".utf8))   // the broken state is kept
}

@Test func restoreFromBak() throws {
    // Build 249 set aside a file that this build can read (e.g. thanks to lenient decoding); the main file is broken.
    let store = ProfileStore(directory: tempDir())
    try encoded(named("Gerettet")).write(to: store.backupURL)
    try Data("kaputt{".utf8).write(to: store.fileURL)
    let c = candidates(store.loadResult())
    #expect(c.map(\.id) == ["profiles.json.bak#0"])
    let s = try store.restore("profiles.json.bak#0")
    #expect(s.profiles[0].name == "Gerettet")
    #expect(try Data(contentsOf: store.unreadableURL) == Data("kaputt{".utf8))   // the broken state is kept
    #expect(try ProfileStore.decode(Data(contentsOf: store.backupURL)).profiles[0].name == "Gerettet")   // .bak stays
    guard case .loaded(let again, _) = store.loadResult() else { Issue.record("expected .loaded"); return }
    #expect(again.profiles[0].name == "Gerettet")
}

@Test func saveRotatesGenerationsAtMostEveryTenMinutes() throws {
    let store = ProfileStore(directory: tempDir())
    func gen(_ n: Int) -> String? { store.storage.read("profiles.json.\(n)").flatMap { try? ProfileStore.decode($0) }?.profiles[0].name }
    try store.save(named("A"), now: t0)
    #expect(gen(1) == nil)                                               // nothing older yet
    try store.save(named("B"), now: t0.addingTimeInterval(5))
    #expect(gen(1) == "A" && gen(2) == nil)
    try store.save(named("C"), now: t0.addingTimeInterval(60))           // within 10 min: no rotation
    try store.save(named("D"), now: t0.addingTimeInterval(9 * 60))
    #expect(gen(1) == "A" && gen(2) == nil)
    let e = named("E")
    try store.save(e, now: t0.addingTimeInterval(5 + 10 * 60))           // 10 min after the last rotation
    #expect(gen(1) == "D" && gen(2) == "A")
    try store.save(e, now: t0.addingTimeInterval(3600))                  // unchanged data: no rotation
    #expect(gen(1) == "D" && gen(2) == "A")
    try store.save(named("F"), now: t0.addingTimeInterval(3601))
    #expect(gen(1) == "E" && gen(2) == "D")
}

@Test func unreadableProgressKeepsFileAsBak() throws {
    let dir = tempDir()
    let store = ProgressStore(directory: dir)
    let id = UUID()
    let name = "progress-\(id.uuidString).json"
    try Data("{\"entries\":{\"tt1\":{\"id\":".utf8).write(to: dir.appendingPathComponent(name))
    #expect(store.load(profile: id) == nil)
    #expect(try Data(contentsOf: dir.appendingPathComponent(name + ".bak")) == Data("{\"entries\":{\"tt1\":{\"id\":".utf8))
    #expect(try Data(contentsOf: dir.appendingPathComponent(name)) == Data("{\"entries\":{\"tt1\":{\"id\":".utf8))
    #expect(store.load(profile: UUID())?.entries.isEmpty == true)        // missing file: empty book, not nil
}

// MARK: Extra rules

@Test func unreadableSetAsideFreezesGenerationsForSevenDays() throws {
    let store = ProfileStore(directory: tempDir())
    func gen(_ n: Int) -> String? { store.storage.read("profiles.json.\(n)").flatMap { try? ProfileStore.decode($0) }?.profiles[0].name }
    let day: TimeInterval = 24 * 3600
    try store.save(named("A"), now: t0)
    try store.save(named("B"), now: t0.addingTimeInterval(1))            // .1 = A
    try Data("kaputt{".utf8).write(to: store.fileURL)
    _ = store.loadResult(now: t0.addingTimeInterval(100))                // set aside now (newer than .1)
    _ = try store.startFresh(now: t0.addingTimeInterval(100))
    try store.save(named("X"), now: t0.addingTimeInterval(6 * day))
    #expect(gen(1) == "A" && gen(2) == nil)                              // day 6: frozen, the good generation stays
    try store.save(named("Y"), now: t0.addingTimeInterval(8 * day))
    #expect(gen(1) == "X" && gen(2) == "A")                              // day 8: rotates again
    #expect(try Data(contentsOf: store.unreadableURL) == Data("kaputt{".utf8))
}

@Test func clockGoingBackIsNotDue() throws {
    let store = ProfileStore(directory: tempDir())
    func gen(_ n: Int) -> String? { store.storage.read("profiles.json.\(n)").flatMap { try? ProfileStore.decode($0) }?.profiles[0].name }
    try store.save(named("A"), now: t0)
    try store.save(named("B"), now: t0.addingTimeInterval(1000))         // .1 = A at t0+1000
    try store.save(named("C"), now: t0)                                  // clock went back: no rotation
    #expect(gen(1) == "A" && gen(2) == nil)
}

@Test func reportBakSurvivesLaterUnreadableSetAsideAndStartFresh() throws {
    let json = """
    {"schemaVersion":1,"profiles":[{"id":"00000000-0000-4000-8000-000000000051","name":"Original",
     "appearance":{"accent":"turquoise"}}]}
    """
    let store = ProfileStore(directory: tempDir())
    try Data(json.utf8).write(to: store.fileURL)
    guard case .loaded = store.loadResult() else { Issue.record("expected .loaded"); return }
    try Data("kaputt{".utf8).write(to: store.fileURL)
    let c = candidates(store.loadResult())
    #expect(c.map(\.id) == ["profiles.json.bak#0"])
    _ = try store.startFresh()
    #expect(try Data(contentsOf: store.backupURL) == Data(json.utf8))
    #expect(try Data(contentsOf: store.unreadableURL) == Data("kaputt{".utf8))
}

@Test func savingUnreadableStateNeverRotatesBrokenData() throws {
    let store = ProfileStore(directory: tempDir())
    try Data("kaputt{".utf8).write(to: store.fileURL)
    _ = store.loadResult()
    _ = try store.startFresh()
    #expect(store.storage.read("profiles.json.1") == nil)
    #expect(try Data(contentsOf: store.unreadableURL) == Data("kaputt{".utf8))
}

@Test func missingMainWithGenerationsIsNotFresh() throws {
    let store = ProfileStore(directory: tempDir())
    try store.save(named("A"), now: t0)
    try store.save(named("B"), now: t0.addingTimeInterval(1))
    try FileManager.default.removeItem(at: store.fileURL)
    #expect(candidates(store.loadResult()).map(\.id) == ["profiles.json.1#0"])
}

@Test func decodedWithReportKeepsOriginalAsBak() throws {
    let json = """
    {"schemaVersion":1,"profiles":[{"id":"00000000-0000-4000-8000-000000000031","name":"Eins",
     "appearance":{"accent":"turquoise"}}]}
    """
    let store = ProfileStore(directory: tempDir())
    try Data(json.utf8).write(to: store.fileURL)
    guard case .loaded(let s, let report) = store.loadResult() else { Issue.record("expected .loaded"); return }
    #expect(!report.isEmpty && s.profiles[0].name == "Eins")
    #expect(try Data(contentsOf: store.backupURL) == Data(json.utf8))
    // The next save drops the unknown value from profiles.json; the .bak still has it and is a candidate.
    try store.save(s, now: t0)
    #expect(try Data(contentsOf: store.backupURL) == Data(json.utf8))
    try? FileManager.default.removeItem(at: store.fileURL.appendingPathExtension("1"))   // .1 would hold the same bytes
    try Data("kaputt{".utf8).write(to: store.fileURL)
    let c = candidates(store.loadResult())
    #expect(c.map(\.id) == ["profiles.json.bak#0"])
}

@Test func reportBakDoesNotReplaceUnreadableBak() throws {
    let store = ProfileStore(directory: tempDir())
    try Data("kaputt{".utf8).write(to: store.backupURL)
    let json = #"{"schemaVersion":1,"profiles":[{"id":"00000000-0000-4000-8000-000000000041","name":"X","language":"tlh"}]}"#
    try Data(json.utf8).write(to: store.fileURL)
    guard case .loaded = store.loadResult() else { Issue.record("expected .loaded"); return }
    #expect(try Data(contentsOf: store.backupURL) == Data("kaputt{".utf8))
}

@Test func newerSchemaIsUnreadableNotFresh() throws {
    let store = ProfileStore(directory: tempDir())
    try encoded(named("Zukunft", schema: 99)).write(to: store.fileURL)
    guard case .unreadable(let reason, _) = store.loadResult() else { Issue.record("expected .unreadable"); return }
    #expect(reason.contains("99"))
}

@Test func fileCopiesAreCandidates() throws {
    // UserDefaults holds a broken block, one file copy is still readable (e.g. older state in Application Support).
    let (store, _, kv, dirs) = tieredStore()
    try store.save(named("Datei"), now: t0)
    kv.set(Data("kaputt{".utf8), forKey: "blob.profiles.json")
    try Data("kaputt{".utf8).write(to: dirs[1].url("profiles.json"))
    let c = candidates(store.loadResult())
    #expect(c.count == 1 && c[0].id == "profiles.json#1" && c[0].savedAt != nil)
    #expect(try store.restore(c[0].id).profiles[0].name == "Datei")
}

@Test func distantPastProgressRoundTrips() throws {
    // Analysis open question 8: entries from Trakt/Simkl without a readable paused_at carry Date.distantPast.
    let store = ProgressStore(directory: tempDir())
    let id = UUID()
    var b = ProgressBook()
    b.merge(remote: [RemoteProgress(id: "tt7", item: MetaPreview(id: "tt7", type: "movie", name: "A"), season: nil, episode: nil,
                                    fraction: 0.4, updated: .distantPast)])
    try store.save(b, profile: id)
    let back = try #require(store.load(profile: id))
    #expect(back.entries["tt7"] != nil)
}

// MARK: Storage layout of the two generations (user decision 2026-11-22)

@Test func generationsUseOwnKeysOutsideBlobPrefix() throws {
    let (store, t, kv, dirs) = tieredStore()
    try store.save(named("A"), now: t0)
    try store.save(named("B"), now: t0.addingTimeInterval(1))
    try store.save(named("C"), now: t0.addingTimeInterval(700))
    #expect(kv.data(forKey: "profilegen.1") != nil && kv.data(forKey: "profilegen.2") != nil)
    #expect(kv.keys(withPrefix: "blob.").sorted() == ["blob.profiles.json"])
    #expect(t.defaultsSizes().keys.sorted() == ["profiles.json"])
    #expect(dirs.allSatisfy { $0.read("profiles.json.1") != nil && $0.read("profiles.json.2") != nil })
    // Build 249's migrate() only looks at `blob.*`: it neither moves nor deletes the generations.
    let before = kv.keys(withPrefix: "profilegen.").sorted().map { kv.data(forKey: $0) }
    let m = t.migrate()
    #expect(m.moved.isEmpty && m.kept == ["profiles.json"])
    #expect(kv.keys(withPrefix: "profilegen.").sorted().map { kv.data(forKey: $0) } == before)
}

@Test func oldStorageStateLoadsInNewCode() throws {
    // Build 249 state: only `blob.profiles.json` plus the file copies, no generations, no dates.
    let kv = MemoryKeyValueBlobs()
    let dirs = [FileBlobStorage(directory: tempDir()), FileBlobStorage(directory: tempDir())]
    let data = try encoded(named("Altbestand"))
    kv.set(data, forKey: "blob.profiles.json")
    for d in dirs { try d.write("profiles.json", data) }
    let store = ProfileStore(storage: TieredBlobStorage(defaults: kv, directories: dirs))
    guard case .loaded(let s, let report) = store.loadResult() else { Issue.record("expected .loaded"); return }
    #expect(s.profiles[0].name == "Altbestand" && report.isEmpty)
    #expect(dirs.allSatisfy { $0.read("profiles.json.bak") == nil })
    var changed = s; changed.profiles[0].name = "Weiter"
    try store.save(changed, now: t0)
    #expect(store.storage.read("profiles.json.1") == data)              // the old state is the first generation
}

@Test func newWrittenProfilesStayReadableByBaseDecoder() throws {
    // Same JSON shape as before: a plain synthesized decode (as in build 249) of what save writes.
    let (store, _, kv, dirs) = tieredStore()
    try store.save(named("A"), now: t0)
    try store.save(named("B"), now: t0.addingTimeInterval(1))
    struct Base249: Decodable { var schemaVersion: Int; var profiles: [Profile]; var activeProfileID: UUID? }
    for blob in [kv.data(forKey: "blob.profiles.json"), dirs[0].read("profiles.json"),
                 kv.data(forKey: "profilegen.1"), dirs[0].read("profiles.json.1")] {
        let data = try #require(blob)
        let b = try JSONDecoder().decode(Base249.self, from: data)
        #expect(b.schemaVersion == 1 && b.profiles.count == 1)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let keys = try #require(object).keys.sorted()
        #expect(keys == ["activeProfileID", "profiles", "schemaVersion"])
    }
}

@Test func worstCaseDefaultsStayWithinBudget() throws {
    let kv = MemoryKeyValueBlobs()
    let t = TieredBlobStorage(defaults: kv, directories: [FileBlobStorage(directory: tempDir())])
    func total() -> Int { kv.keys(withPrefix: "").reduce(0) { $0 + (kv.data(forKey: $1)?.count ?? 0) } }
    func family() -> (all: Int, gens: Int) {
        let g = ["profilegen.1", "profilegen.2", "profilegen.dates"].reduce(0) { $0 + (kv.data(forKey: $1)?.count ?? 0) }
        return ((kv.data(forKey: "blob.profiles.json")?.count ?? 0) + g, g)
    }
    func check() {
        #expect(total() <= TieredBlobStorage.budget)
        #expect(family().all <= TieredBlobStorage.profileLimit)
        #expect(family().gens <= TieredBlobStorage.generationsLimit)
    }
    // Everything else at its maximum.
    try t.write(TieredBlobStorage.deviceName, Data(repeating: 1, count: TieredBlobStorage.deviceLimit))
    for i in 0..<20 { try t.write("progress-\(i).json", Data(repeating: 2, count: 40_000)) }
    check()
    // Generations first (small main), then the main block grows to its limit: generations give way.
    try t.write("profiles.json", Data(repeating: 3, count: 10_000))
    try t.write("profiles.json.1", Data(repeating: 4, count: TieredBlobStorage.generationsLimit))
    try t.write("profiles.json.2", Data(repeating: 5, count: TieredBlobStorage.generationsLimit))
    try t.write("profiles.json.dates", Data(repeating: 6, count: 200))
    check()
    #expect(kv.data(forKey: "profilegen.1") != nil && kv.data(forKey: "profilegen.2") == nil)   // .1 has priority
    for n in [100_000, 200_000, 320_000, 400_000, TieredBlobStorage.profileLimit] {
        try t.write("profiles.json", Data(repeating: 3, count: n))
        check()
    }
    #expect(kv.data(forKey: "profilegen.1") == nil)
    // What does not fit stays readable from the files.
    #expect(t.read("profiles.json.1")?.count == TieredBlobStorage.generationsLimit)
    #expect(t.read("profiles.json.2")?.count == TieredBlobStorage.generationsLimit)
    // Small generations next to a small main block both stay in UserDefaults.
    try t.write("profiles.json", Data(repeating: 3, count: 50_000))
    try t.write("profiles.json.1", Data(repeating: 4, count: 60_000))
    try t.write("profiles.json.2", Data(repeating: 5, count: 60_000))
    check()
    #expect(kv.data(forKey: "profilegen.1") != nil && kv.data(forKey: "profilegen.2") != nil)
    // Also the structural bound: all reserves together stay within the budget.
    #expect(TieredBlobStorage.profileLimit + TieredBlobStorage.deviceLimit + TieredBlobStorage.othersBudget <= TieredBlobStorage.budget)
}
