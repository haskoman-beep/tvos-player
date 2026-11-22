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

@Test func migrationRunsOnceThenDeviceBlockWins() throws {
    let dir = tempDir()
    let storage = FileBlobStorage(directory: dir)
    try storage.write(ProfileStore.name, oldProfilesJSON(active: idB))
    let store = DeviceSettingsStore(storage: storage)
    let first = store.loadOrMigrate()
    #expect(first.migrated && first.settings.audioShaping.safeStereo)
    // Changed on the device; the profiles still hold the old values, but the move does not run again.
    var changed = first.settings
    changed.audioShaping.safeStereo = false
    changed.displayMode.panelPresentsDolbyVision = true
    try store.save(changed)
    let second = DeviceSettingsStore(storage: storage).loadOrMigrate()
    #expect(!second.migrated && second.settings == changed)
    // Switching the active profile in profiles.json changes nothing either.
    try storage.write(ProfileStore.name, oldProfilesJSON(active: idA))
    #expect(DeviceSettingsStore(storage: storage).loadOrMigrate().settings == changed)
    // Fresh install without profiles: defaults, written once.
    let fresh = DeviceSettingsStore(storage: FileBlobStorage(directory: tempDir()))
    let f = fresh.loadOrMigrate()
    #expect(f.migrated && f.settings == DeviceSettings())
    #expect(!fresh.loadOrMigrate().migrated)
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
    let store = DeviceSettingsStore(storage: storage)
    try store.save(DeviceSettings(displayMode: DisplayModeSettings(keepModeBetweenEpisodes: false)))
    try storage.write(ProfileStore.name, oldProfilesJSON(active: idA))
    #expect(store.loadOrMigrate().settings.displayMode.keepModeBetweenEpisodes == false)
    #expect(!store.loadOrMigrate().settings.displayMode.panelPresentsDolbyVision)
}
