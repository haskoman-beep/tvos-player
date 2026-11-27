import Foundation
import Testing
@testable import PlayerCore

// Phase 0a, finding 1: a UserDefaults copy that is older than the file must not win on read.
// A UserDefaults write can pass the read-back check in the running process and still never reach the disk
// (app killed, cfprefsd refusing). The next start then sees the old entry next to a newer file.

private let name = "profiles.json"
/// Marks a store whose entries from older builds were taken over already (`adoptLegacyDefaults`).
private let adopted = TieredBlobStorage.adoptedKey

/// Every entry of the store, as the next app start would find it.
private func snapshot(_ kv: MemoryKeyValueBlobs) -> [String: Data] {
    var out: [String: Data] = [:]
    for k in kv.keys(withPrefix: "") { out[k] = kv.data(forKey: k) }
    return out
}

/// Model time passing between two writes (file dates may otherwise fall into the same clock tick).
private func age(_ dir: FileBlobStorage, _ name: String, by seconds: TimeInterval) throws {
    let now = dir.modificationDate(name) ?? Date()
    try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(seconds)], ofItemAtPath: dir.url(name).path)
}

@Test func fileWinsWhenDefaultsWriteWasLost() throws {
    let dirs = [FileBlobStorage(directory: tempDir()), FileBlobStorage(directory: tempDir())]
    let kv = MemoryKeyValueBlobs()
    let first = TieredBlobStorage(defaults: kv, directories: dirs)
    try first.write(name, Data("old".utf8))
    let before = snapshot(kv)
    try first.write(name, Data("new".utf8))
    for d in dirs { try age(d, name, by: 10) }

    // Next start: the files hold "new", UserDefaults fell back to the state before the second write.
    let next = TieredBlobStorage(defaults: MemoryKeyValueBlobs(before), directories: dirs)
    #expect(next.read(name) == Data("new".utf8))
}

@Test func fileWinsOverDefaultsEntryWithoutRevision() throws {
    // Entry written by an older app version (no revision stored): nothing proves it is current.
    let dir = FileBlobStorage(directory: tempDir())
    try dir.write(name, Data("file".utf8))
    let s = TieredBlobStorage(defaults: MemoryKeyValueBlobs(["blob." + name: Data("defaults".utf8)]), directories: [dir])
    #expect(s.read(name) == Data("file".utf8))
}

@Test func defaultsWinWhenTheFileCouldNotBeWritten() throws {
    let dir = FileBlobStorage(directory: tempDir())
    let kv = MemoryKeyValueBlobs()
    try TieredBlobStorage(defaults: kv, directories: [dir]).write(name, Data("old".utf8))
    // Second write: no folder takes the file (tvOS code 513), only UserDefaults holds the new state.
    let blocker = tempDir().appendingPathComponent("datei")
    try Data("x".utf8).write(to: blocker)
    let blocked = FileBlobStorage(directory: blocker.appendingPathComponent("unter"))
    let s = TieredBlobStorage(defaults: kv, directories: [dir], writeDirectories: [blocked])
    try s.write(name, Data("new".utf8))
    #expect(dir.read(name) == Data("old".utf8))
    #expect(s.read(name) == Data("new".utf8))
}

@Test func defaultsEntryWithoutFileStillReads() throws {
    // tvOS emptied Caches and Application Support was never writable: the UserDefaults copy is all there is.
    let s = TieredBlobStorage(defaults: MemoryKeyValueBlobs(["blob." + name: Data("defaults".utf8)]),
                              directories: [FileBlobStorage(directory: tempDir())])
    #expect(s.read(name) == Data("defaults".utf8))
}

@Test func migrateDoesNotOverwriteNewerFileWithStaleDefaults() throws {
    let dir = FileBlobStorage(directory: tempDir())
    try dir.write("progress-a.json", Data("file".utf8))
    let stale = Data(repeating: 7, count: TieredBlobStorage.smallLimit + 1)   // too large: migrate() moves it out
    let kv = MemoryKeyValueBlobs(["blob.progress-a.json": stale, adopted: Data([1])])
    let s = TieredBlobStorage(defaults: kv, directories: [dir])
    s.migrate()
    #expect(dir.read("progress-a.json") == Data("file".utf8))
    #expect(kv.data(forKey: "blob.progress-a.json") == nil)
}

@Test func trimDoesNotOverwriteNewerGenerationFileWithStaleDefaults() throws {
    let dir = FileBlobStorage(directory: tempDir())
    try dir.write("profiles.json.1", Data("file".utf8))
    let kv = MemoryKeyValueBlobs(["profilegen.1": Data(repeating: 7, count: 190_000)])
    let s = TieredBlobStorage(defaults: kv, directories: [dir])
    // The main block grows so far that the generation has to leave UserDefaults.
    try s.write("profiles.json", Data(repeating: 5, count: 400_000))
    #expect(kv.data(forKey: "profilegen.1") == nil)
    #expect(dir.read("profiles.json.1") == Data("file".utf8))
}

@Test func overtakenDefaultsNamesOnlyEntriesThatDifferFromTheWinningFile() throws {
    let dir = FileBlobStorage(directory: tempDir())
    try dir.write(name, Data("file".utf8))
    try dir.write("profiles.json.1", Data("gen".utf8))
    try dir.write("same.json", Data("same".utf8))
    let kv = MemoryKeyValueBlobs([
        "blob." + name: Data("defaults".utf8),      // differs, no revision: overtaken
        "profilegen.1": Data("oldgen".utf8),         // generation key, overtaken as well
        "blob.same.json": Data("same".utf8),         // no revision but identical: nothing lost
        "blob.only.json": Data("only".utf8),         // no file at all: still the valid copy
        adopted: Data([1]),
    ])
    let s = TieredBlobStorage(defaults: kv, directories: [dir])
    #expect(s.overtakenDefaults() == [name, "profiles.json.1"])
}

/// Review: first start after the update. No entry has a revision yet, and UserDefaults was the copy that won until
/// now (Application Support may hold a file from a start long ago). The entries are taken over once, as they are.
@Test func entriesOfAnOlderBuildWinOnceAfterTheUpdate() throws {
    let dir = FileBlobStorage(directory: tempDir())
    try dir.write(name, Data("old file".utf8))
    let kv = MemoryKeyValueBlobs(["blob." + name: Data("defaults".utf8)])
    let s = TieredBlobStorage(defaults: kv, directories: [dir])
    #expect(s.overtakenDefaults().isEmpty)
    s.migrate()
    #expect(s.read(name) == Data("defaults".utf8))
    #expect(kv.data(forKey: adopted) != nil)

    // Later an entry without revision gives way again (the take-over happens once).
    try dir.write("other.json", Data("file".utf8))
    kv.set(Data("defaults".utf8), forKey: "blob.other.json")
    let next = TieredBlobStorage(defaults: kv, directories: [dir])
    next.migrate()
    #expect(next.read("other.json") == Data("file".utf8))
    #expect(next.read(name) == Data("defaults".utf8))
}
