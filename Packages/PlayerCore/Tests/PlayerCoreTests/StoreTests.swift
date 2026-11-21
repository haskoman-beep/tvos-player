import Foundation
import Testing
@testable import PlayerCore

func tempDir() -> URL {
    let u = FileManager.default.temporaryDirectory.appendingPathComponent("pc-" + UUID().uuidString)
    try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}

@Test func saveThenLoad() throws {
    let store = ProfileStore(directory: tempDir())
    var s = StoredProfiles.makeDefault()
    s.profiles[0].name = "Max"
    try store.save(s)
    #expect(store.load() == s)
}

@Test func missingFileGivesDefault() {
    let s = ProfileStore(directory: tempDir()).load()
    #expect(s.profiles.count == 1 && s.profiles[0].name == "Ich")
    #expect(s.active?.id == s.profiles[0].id)
}

@Test func corruptFileFallsBackAndKeepsBackup() throws {
    let store = ProfileStore(directory: tempDir())
    try Data("kaputt{".utf8).write(to: store.fileURL)
    let s = store.load()
    #expect(s.profiles.count == 1)
    #expect(try String(contentsOf: store.backupURL, encoding: .utf8) == "kaputt{")
}

@Test func newerSchemaIsNotOverwritten() throws {
    let store = ProfileStore(directory: tempDir())
    var s = StoredProfiles.makeDefault(); s.schemaVersion = 99
    try store.exportData(s).write(to: store.fileURL)
    _ = store.load()
    #expect(FileManager.default.fileExists(atPath: store.backupURL.path))
}

@Test func exportImportRoundTrip() throws {
    let store = ProfileStore(directory: tempDir())
    let s = StoredProfiles.makeDefault()
    #expect(try store.importData(store.exportData(s)) == s)
}
