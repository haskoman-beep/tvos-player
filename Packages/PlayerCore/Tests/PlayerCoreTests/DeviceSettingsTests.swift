import Foundation
import Testing
@testable import PlayerCore

// Wave S round 2: „Bild & Ton“ is stored per device; one-time move from the active profile.

private let idA = UUID(), idB = UUID()

/// profiles.json as written before round 2: both profiles carry their own sound and picture fields.
private func oldProfilesJSON(active: UUID?) -> Data {
    let act = active.map { #","activeProfileID":"\#($0.uuidString)""# } ?? ""
    return Data(#"""
    {"schemaVersion":1\#(act),"profiles":[
     {"id":"\#(idA.uuidString)","name":"A","audioShaping":{"nightMode":true,"audioDelayMs":120},"displayMode":{"panelPresentsDolbyVision":true}},
     {"id":"\#(idB.uuidString)","name":"B","audioShaping":{"safeStereo":true,"bridge":"lossless"},"displayMode":{"foldsDolbyVisionFEL":false,"keepModeBetweenEpisodes":false}}]}
    """#.utf8)
}

@Test func deviceSettingsDefaults() throws {
    let d = DeviceSettings()
    #expect(d.audioShaping == AudioShapingSettings() && d.displayMode == DisplayModeSettings())
    #expect(!d.displayMode.panelPresentsDolbyVision && d.displayMode.foldsDolbyVisionFEL && d.displayMode.keepModeBetweenEpisodes)
    #expect(!d.audioShaping.shapesAudio && !d.audioShaping.safeStereo && !d.audioShaping.hasEARCReceiver)
    // Partial or broken block: the broken part falls back, the rest stays.
    let partial = try JSONDecoder().decode(DeviceSettings.self, from: Data(#"{"audioShaping":7,"displayMode":{"keepModeBetweenEpisodes":false}}"#.utf8))
    #expect(partial.audioShaping == AudioShapingSettings() && !partial.displayMode.keepModeBetweenEpisodes)
}

@Test func migrationTakesActiveProfile() {
    let b = DeviceSettings.migrated(fromProfilesData: oldProfilesJSON(active: idB))
    #expect(b.audioShaping.safeStereo && b.audioShaping.hasEARCReceiver && !b.audioShaping.nightMode)
    #expect(!b.displayMode.foldsDolbyVisionFEL && !b.displayMode.keepModeBetweenEpisodes && !b.displayMode.panelPresentsDolbyVision)
    let a = DeviceSettings.migrated(fromProfilesData: oldProfilesJSON(active: idA))
    #expect(a.audioShaping.nightMode && a.audioShaping.audioDelayMs == 120 && a.displayMode.panelPresentsDolbyVision)
    // No active ID or an unknown one: the first profile, like `StoredProfiles.active`.
    #expect(DeviceSettings.migrated(fromProfilesData: oldProfilesJSON(active: nil)) == a)
    #expect(DeviceSettings.migrated(fromProfilesData: oldProfilesJSON(active: UUID())) == a)
    // Nothing to take: defaults.
    #expect(DeviceSettings.migrated(fromProfilesData: nil) == DeviceSettings())
    #expect(DeviceSettings.migrated(fromProfilesData: Data("kaputt".utf8)) == DeviceSettings())
    #expect(DeviceSettings.migrated(fromProfilesData: Data(#"{"profiles":[{"id":"\#(idA.uuidString)","name":"A"}]}"#.utf8)) == DeviceSettings())
}

/// The app's UserDefaults flag, in memory.
private final class Flag: @unchecked Sendable {
    var set = false
    func store(_ storage: BlobStorage) -> DeviceSettingsStore {
        DeviceSettingsStore(storage: storage, isMigrated: { self.set }, markMigrated: { self.set = true })
    }
}

/// Storage whose writes always fail.
private struct FailingStorage: BlobStorage {
    let base: BlobStorage
    struct Full: Error {}
    func read(_ name: String) -> Data? { base.read(name) }
    func write(_ name: String, _ data: Data) throws { throw Full() }
    func remove(_ name: String) { base.remove(name) }
}

@Test func migrationRunsOnceThenDeviceBlockWins() throws {
    let storage = FileBlobStorage(directory: tempDir())
    try storage.write(ProfileStore.name, oldProfilesJSON(active: idB))
    let flag = Flag()
    let store = flag.store(storage)
    let first = store.loadOrMigrate()
    #expect(first.outcome == .migrated(fromProfiles: true) && first.writeError == nil && flag.set)
    #expect(first.settings.audioShaping.safeStereo)
    // Changed on the device; the profiles still hold the old values, but the move does not run again.
    var changed = first.settings
    changed.audioShaping.safeStereo = false
    changed.displayMode.panelPresentsDolbyVision = true
    try store.save(changed)
    let second = flag.store(storage).loadOrMigrate()
    #expect(second.outcome == .loaded && second.settings == changed)
    // Switching the active profile in profiles.json changes nothing either.
    try storage.write(ProfileStore.name, oldProfilesJSON(active: idA))
    #expect(flag.store(storage).loadOrMigrate().settings == changed)
    // Fresh install without profiles: defaults, written once, not reported as taken from a profile.
    let freshFlag = Flag()
    let fresh = freshFlag.store(FileBlobStorage(directory: tempDir()))
    let f = fresh.loadOrMigrate()
    #expect(f.outcome == .migrated(fromProfiles: false) && f.settings == DeviceSettings() && freshFlag.set)
    #expect(fresh.loadOrMigrate().outcome == .loaded)
}

@Test func lostBlockWithFlagSetDoesNotMigrateAgain() throws {
    // Review S I-R2-1: the block is gone (e.g. purged Caches copy), profiles.json still has the old values.
    let storage = FileBlobStorage(directory: tempDir())
    try storage.write(ProfileStore.name, oldProfilesJSON(active: idB))
    let flag = Flag()
    flag.set = true
    let r = flag.store(storage).loadOrMigrate()
    #expect(r.outcome == .blockMissing && r.settings == DeviceSettings() && !r.settings.audioShaping.safeStereo)
    // Defaults are written back: the next start reads them without a further notice.
    #expect(flag.store(storage).loadOrMigrate().outcome == .loaded)
    // An unreadable block: defaults, reported.
    try storage.write(DeviceSettingsStore.name, Data("kaputt".utf8))
    let u = flag.store(storage).loadOrMigrate()
    #expect(u.outcome == .blockUnreadable && u.settings == DeviceSettings())
    // An old block without flag (earlier build) sets the flag and does not move.
    let other = FileBlobStorage(directory: tempDir())
    let fresh = Flag()
    try fresh.store(other).save(DeviceSettings(audioShaping: AudioShapingSettings(nightMode: true)))
    #expect(fresh.store(other).loadOrMigrate().outcome == .loaded && fresh.set)
}

@Test func failedFirstWriteIsReportedAndLeavesFlagUnset() throws {
    let base = FileBlobStorage(directory: tempDir())
    try base.write(ProfileStore.name, oldProfilesJSON(active: idA))
    let flag = Flag()
    let r = flag.store(FailingStorage(base: base)).loadOrMigrate()
    #expect(r.outcome == .migrated(fromProfiles: true) && r.writeError != nil && !flag.set)
    #expect(r.settings.audioShaping.nightMode)   // values are still used for this run
}

@Test func deviceBlockHasReservedDefaultsSlot() throws {
    // The other blocks fill their shared budget; the device block still goes to UserDefaults and stays there.
    let kv = MemoryKeyValueBlobs()
    let s = TieredBlobStorage(defaults: kv, directories: [FileBlobStorage(directory: tempDir())])
    let half = TieredBlobStorage.othersBudget / 2
    try s.write("progress-a.json", Data(repeating: 1, count: half))
    try s.write("progress-b.json", Data(repeating: 2, count: half))
    #expect(s.defaultsSizes().values.reduce(0, +) == TieredBlobStorage.othersBudget)
    try s.write(DeviceSettingsStore.name, try JSONEncoder().encode(DeviceSettings()))
    #expect(kv.data(forKey: TieredBlobStorage.prefix + DeviceSettingsStore.name) != nil)
    #expect(s.migrate().kept.contains(DeviceSettingsStore.name))
    #expect(TieredBlobStorage.isReserved(DeviceSettingsStore.name) && TieredBlobStorage.isReserved(ProfileStore.name))
}

@Test func oldProfilesDecodeAndDropDeviceFields() throws {
    let s = try ProfileStore.decode(oldProfilesJSON(active: idB))
    #expect(s.profiles.map(\.name) == ["A", "B"] && s.active?.id == idB)
    // Export, save and sync no longer carry the device fields.
    let out = String(data: try ProfileStore(directory: tempDir()).exportData(s), encoding: .utf8)!
    #expect(!out.contains("audioShaping") && !out.contains("displayMode") && !out.contains("safeStereo"))
    let json = String(data: try JSONEncoder().encode(s.profiles[0]), encoding: .utf8)!
    #expect(!json.contains("audioShaping") && !json.contains("displayMode"))
    // An imported backup with other device values leaves the device block alone.
    let storage = FileBlobStorage(directory: tempDir())
    let store = Flag().store(storage)
    try store.save(DeviceSettings(displayMode: DisplayModeSettings(keepModeBetweenEpisodes: false)))
    try storage.write(ProfileStore.name, oldProfilesJSON(active: idA))
    #expect(store.loadOrMigrate().settings.displayMode.keepModeBetweenEpisodes == false)
    #expect(!store.loadOrMigrate().settings.displayMode.panelPresentsDolbyVision)
}

// MARK: Task 1.5: remote log fields (additive)

/// The device block as the app wrote it before task 1.5: only the picture and sound fields.
private let deviceJSONBeforeRemoteLog = Data(#"""
{"audioShaping":{"nightMode":true,"audioDelayMs":40},"displayMode":{"panelPresentsDolbyVision":true,"keepModeBetweenEpisodes":false}}
"""#.utf8)

/// The field set of `DeviceSettings` before task 1.5, with the same decoding as then.
private struct DeviceSettingsBeforeRemoteLog: Decodable {
    var audioShaping: AudioShapingSettings
    var displayMode: DisplayModeSettings
    enum CodingKeys: String, CodingKey { case audioShaping, displayMode }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        audioShaping = (try? c.decodeIfPresent(AudioShapingSettings.self, forKey: .audioShaping)) ?? nil ?? AudioShapingSettings()
        displayMode = (try? c.decodeIfPresent(DisplayModeSettings.self, forKey: .displayMode)) ?? nil ?? DisplayModeSettings()
    }
}

@Test func deviceSettingsOldBlockDecodesWithRemoteLogOff() throws {
    let d = try JSONDecoder().decode(DeviceSettings.self, from: deviceJSONBeforeRemoteLog)
    #expect(!d.remoteLogEnabled && d.remoteLogReceiver == nil)
    #expect(d.audioShaping.nightMode && d.audioShaping.audioDelayMs == 40)
    #expect(d.displayMode.panelPresentsDolbyVision && !d.displayMode.keepModeBetweenEpisodes)
    #expect(!DeviceSettings().remoteLogEnabled && DeviceSettings().remoteLogReceiver == nil)
    // Broken new fields fall back alone.
    let broken = try JSONDecoder().decode(DeviceSettings.self, from: Data(#"{"remoteLogEnabled":"ja","remoteLogReceiver":5}"#.utf8))
    #expect(!broken.remoteLogEnabled && broken.remoteLogReceiver == nil)
}

@Test func deviceSettingsNewBlockStillReadableByOldFieldSet() throws {
    var d = try JSONDecoder().decode(DeviceSettings.self, from: deviceJSONBeforeRemoteLog)
    d.remoteLogEnabled = true
    d.remoteLogReceiver = "Player-Log"
    let data = try JSONEncoder().encode(d)
    // Round trip keeps everything.
    #expect(try JSONDecoder().decode(DeviceSettings.self, from: data) == d)
    // An older build ignores the extra keys and reads its fields unchanged.
    let old = try JSONDecoder().decode(DeviceSettingsBeforeRemoteLog.self, from: data)
    #expect(old.audioShaping == d.audioShaping && old.displayMode == d.displayMode)
    // The existing fields keep their stored form: same keys and values as written by the old field set.
    let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let oldObj = try #require(try JSONSerialization.jsonObject(with: try JSONEncoder().encode(DeviceSettings(
        audioShaping: d.audioShaping, displayMode: d.displayMode))) as? [String: Any])
    #expect(Set(obj.keys) == ["audioShaping", "displayMode", "remoteLogEnabled", "remoteLogReceiver"])
    func canonical(_ v: Any?) throws -> Data { try JSONSerialization.data(withJSONObject: try #require(v), options: [.sortedKeys]) }
    #expect(try canonical(obj["audioShaping"]) == canonical(oldObj["audioShaping"]))
    #expect(try canonical(obj["displayMode"]) == canonical(oldObj["displayMode"]))
}
