import Foundation

/// Wave S round 2: settings that belong to this Apple TV (TV panel, HDMI mode, sound system), not to a profile.
/// Everything on the „Bild & Ton“ page lives here. Profile export, import and sync do not carry it.
public struct DeviceSettings: Codable, Sendable, Equatable {
    /// Ton: Nachtmodus, Dialog, Lautheit, Versatz, Anlage (eARC), immer Stereo.
    public var audioShaping: AudioShapingSettings
    /// Bild: Dolby Vision fest, FEL, HDMI-Modus zwischen Folgen halten.
    public var displayMode: DisplayModeSettings

    public init(audioShaping: AudioShapingSettings = AudioShapingSettings(),
                displayMode: DisplayModeSettings = DisplayModeSettings()) {
        self.audioShaping = audioShaping; self.displayMode = displayMode
    }

    enum CodingKeys: String, CodingKey { case audioShaping, displayMode }

    /// Missing or unreadable fields fall back to the defaults instead of dropping the whole block.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = DeviceSettings()
        audioShaping = (try? c.decodeIfPresent(AudioShapingSettings.self, forKey: .audioShaping)) ?? nil ?? d.audioShaping
        displayMode = (try? c.decodeIfPresent(DisplayModeSettings.self, forKey: .displayMode)) ?? nil ?? d.displayMode
    }

    /// One-time move: the values the active profile had before wave S round 2 (raw `profiles.json`).
    /// The active profile wins; without an active ID the first profile counts (same rule as `StoredProfiles.active`).
    /// No data, no profiles or unreadable data give the defaults.
    public static func migrated(fromProfilesData data: Data?) -> DeviceSettings {
        guard let data, let old = try? JSONDecoder().decode(LegacyProfiles.self, from: data) else { return DeviceSettings() }
        guard let p = old.profiles.first(where: { $0.id == old.activeProfileID }) ?? old.profiles.first else { return DeviceSettings() }
        return DeviceSettings(audioShaping: p.audioShaping ?? AudioShapingSettings(), displayMode: p.displayMode ?? DisplayModeSettings())
    }

    /// Only the old per-profile fields; everything else in the file is ignored.
    private struct LegacyProfiles: Decodable {
        struct Entry: Decodable {
            var id: UUID?
            var audioShaping: AudioShapingSettings?
            var displayMode: DisplayModeSettings?
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                id = try? c.decodeIfPresent(UUID.self, forKey: .id)
                audioShaping = (try? c.decodeIfPresent(AudioShapingSettings.self, forKey: .audioShaping)) ?? nil
                displayMode = (try? c.decodeIfPresent(DisplayModeSettings.self, forKey: .displayMode)) ?? nil
            }
            enum CodingKeys: String, CodingKey { case id, audioShaping, displayMode }
        }
        var profiles: [Entry]
        var activeProfileID: UUID?
    }
}

/// Device settings as one small JSON block with a reserved UserDefaults slot (`TieredBlobStorage.deviceName`).
/// A separate one-time flag (plain UserDefaults in the app) records that the move from the profiles happened, so a
/// lost block never moves again: it would revert later device edits to old profile values.
public final class DeviceSettingsStore: @unchecked Sendable {
    public static let name = TieredBlobStorage.deviceName
    /// UserDefaults key of the one-time flag in the app.
    public static let migratedFlagKey = "deviceSettingsMigrated.v1"
    public let storage: BlobStorage
    let isMigrated: @Sendable () -> Bool
    let markMigrated: @Sendable () -> Void

    /// What `loadOrMigrate()` found; the app logs it.
    public enum Outcome: Equatable, Sendable {
        /// Block read as stored.
        case loaded
        /// First start: moved from the active profile (`fromProfiles`) or, without profiles, defaults.
        case migrated(fromProfiles: Bool)
        /// Flag set but the block is gone: defaults, no second move.
        case blockMissing
        /// Block present but unreadable: defaults.
        case blockUnreadable
    }

    public init(storage: BlobStorage, isMigrated: @escaping @Sendable () -> Bool, markMigrated: @escaping @Sendable () -> Void) {
        self.storage = storage; self.isMigrated = isMigrated; self.markMigrated = markMigrated
    }

    /// Loads the block, or moves the values once from the active profile. Defaults that replace a missing or
    /// unreadable block are written back, so the next start reads them. `writeError` is a failed write.
    public func loadOrMigrate() -> (settings: DeviceSettings, outcome: Outcome, writeError: Error?) {
        if let data = storage.read(Self.name) {
            if !isMigrated() { markMigrated() }
            if let s = try? JSONDecoder().decode(DeviceSettings.self, from: data) { return (s, .loaded, nil) }
            return (DeviceSettings(), .blockUnreadable, write(DeviceSettings()))
        }
        if isMigrated() { return (DeviceSettings(), .blockMissing, write(DeviceSettings())) }
        let profiles = storage.read(ProfileStore.name)
        let s = DeviceSettings.migrated(fromProfilesData: profiles)
        let error = write(s)
        if error == nil { markMigrated() }
        return (s, .migrated(fromProfiles: profiles != nil), error)
    }

    public func save(_ s: DeviceSettings) throws {
        try storage.write(Self.name, try JSONEncoder().encode(s))
    }

    private func write(_ s: DeviceSettings) -> Error? {
        do { try save(s); return nil } catch { return error }
    }
}
