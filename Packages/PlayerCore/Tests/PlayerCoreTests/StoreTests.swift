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
    s.profiles[0].name = "Test"
    try store.save(s)
    #expect(store.load().profiles == s)
}

@Test func missingFileGivesDefault() {
    let s = ProfileStore(directory: tempDir()).load().profiles
    #expect(s.profiles.count == 1 && s.profiles[0].name == "Ich")
    #expect(s.active?.id == s.profiles[0].id)
}

@Test func corruptFileFallsBackAndKeepsBackup() throws {
    let store = ProfileStore(directory: tempDir())
    try Data("kaputt{".utf8).write(to: store.fileURL)
    let s = store.load().profiles
    #expect(s.profiles.count == 1)
    #expect(try String(contentsOf: store.unreadableURL, encoding: .utf8) == "kaputt{")   // Task 1.3: own slot
}

@Test func newerSchemaIsNotOverwritten() throws {
    let store = ProfileStore(directory: tempDir())
    var s = StoredProfiles.makeDefault(); s.schemaVersion = 99
    try store.exportData(s).write(to: store.fileURL)
    _ = store.load()
    #expect(FileManager.default.fileExists(atPath: store.unreadableURL.path))   // Task 1.3: own slot
    #expect(try store.exportData(s) == Data(contentsOf: store.fileURL))       // and profiles.json is untouched
}

@Test func exportImportRoundTrip() throws {
    let store = ProfileStore(directory: tempDir())
    let s = StoredProfiles.makeDefault()
    #expect(try store.importData(store.exportData(s)) == s)
}

@Test func olderProfileWithoutNewFieldsStillLoads() throws {
    let json = #"{"schemaVersion":1,"profiles":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Alt"}]}"#
    let s = try ProfileStore(directory: tempDir()).importData(Data(json.utf8))
    #expect(s.profiles[0].name == "Alt" && s.profiles[0].autoplayNext && s.profiles[0].audioPriority == ["de", "en", "orig"])
}
