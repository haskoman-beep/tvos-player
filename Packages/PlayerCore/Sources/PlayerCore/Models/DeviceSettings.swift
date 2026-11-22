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

/// Device settings as one small JSON block. Its presence is the "already moved" mark: the move from the
/// profiles runs only while the block is missing, so it happens once per device.
public final class DeviceSettingsStore: @unchecked Sendable {
    public static let name = "device-settings.json"
    public let storage: BlobStorage

    public init(storage: BlobStorage) { self.storage = storage }

    /// Loads the device block. Missing: takes the active profile's old values, writes them and reports `migrated`.
    /// An unreadable block gives the defaults and does not move again (the profiles no longer hold the values
    /// once they were saved after the update).
    public func loadOrMigrate() -> (settings: DeviceSettings, migrated: Bool) {
        if let data = storage.read(Self.name) {
            return ((try? JSONDecoder().decode(DeviceSettings.self, from: data)) ?? DeviceSettings(), false)
        }
        let s = DeviceSettings.migrated(fromProfilesData: storage.read(ProfileStore.name))
        try? save(s)
        return (s, true)
    }

    public func save(_ s: DeviceSettings) throws {
        try storage.write(Self.name, try JSONEncoder().encode(s))
    }
}
