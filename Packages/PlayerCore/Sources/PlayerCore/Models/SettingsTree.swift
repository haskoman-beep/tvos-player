import Foundation

/// Wave S: the settings tree (left column). Three groups with headers plus System, set apart at the end.
/// Pure logic (order, titles, groups, storage scope) so the tree is testable; the app adds symbols and colours.
///
/// Case names stay stable for code that only needs a category colour (e.g. `SettingsCategory.playback.tint`):
/// `.addons` is now only "Addons" (the source rules moved to `.sources`), `.playback` is "Wiedergabe" without
/// picture, `.audio` is "Sprache & Untertitel" and `.picture` is the new device page "Bild & Ton".
public enum SettingsCategory: String, CaseIterable, Identifiable, Hashable, Sendable {
    case profile, addons, sources, home, appearance, playback, audio, picture, system

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .profile: "Profil & Konten"
        case .addons: "Addons"
        case .sources: "Quellen"
        case .home: "Startseite"
        case .appearance: "Aussehen"
        case .playback: "Wiedergabe"
        case .audio: "Sprache & Untertitel"
        case .picture: "Bild & Ton"
        case .system: "System"
        }
    }

    public var group: SettingsGroup {
        switch self {
        case .profile, .addons, .sources: .content
        case .home, .appearance: .interface
        case .playback, .audio, .picture: .playback
        case .system: .system
        }
    }

    /// Where the settings of this category are stored today. Only a label: the storage itself is unchanged.
    /// Everything bound through `AppModel.binding` lives in the active profile; System holds the update check,
    /// the diagnostics switch (UserDefaults) and the log receiver, which belong to the device.
    public var scope: SettingsScope {
        switch self {
        case .system: .device
        default: .profile
        }
    }

    /// Whether this category opens a new group in the left column (header or gap above it).
    public var startsGroup: Bool {
        Self.allCases.first { $0.group == group } == self
    }
}

/// Group of the left column.
public enum SettingsGroup: String, CaseIterable, Sendable {
    case content, interface, playback, system

    /// Header in small caps; System has none and is only set apart by a gap.
    public var title: String? {
        switch self {
        case .content: "Inhalte"
        case .interface: "Oberfläche"
        case .playback: "Wiedergabe"
        case .system: nil
        }
    }

    public var categories: [SettingsCategory] { SettingsCategory.allCases.filter { $0.group == self } }
}

/// Storage scope shown under a category title.
public enum SettingsScope: Sendable, Equatable {
    case profile, device

    public var label: String {
        switch self {
        case .profile: "Gilt für dieses Profil"
        case .device: "Gilt für dieses Gerät"
        }
    }
}

extension SettingsSummary {
    /// Header of "Addons": „3 Addons · Zeitgrenze 12 s“, „Kein Addon“.
    public static func addonsPage(count n: Int, timeoutSeconds: Double) -> String {
        DesignText.metaLine([addons(n), n == 0 ? nil : "Zeitgrenze \(Int(AddonSearch.nearestChoice(timeoutSeconds))) s"])
    }

    /// Header of "Quellen": „Smart sortiert · vorladen an“, plus „Sofort abspielen“ when that card is on.
    public static func sources(order: StreamOrderMode, prefetch: Bool, instantPlay: Bool) -> String {
        DesignText.metaLine([orderName(order) + " sortiert", "vorladen " + (prefetch ? "an" : "aus"),
                             instantPlay ? "Sofort abspielen" : nil])
    }

    /// Header of "Bild & Ton": „Über Fernseher (optisch/ARC) · HDMI-Modus halten“, extras only when on.
    public static func picture(soundSystemEARC: Bool, keepsMode: Bool, dolbyVisionForced: Bool, alwaysStereo: Bool) -> String {
        DesignText.metaLine([soundSystemName(eARC: soundSystemEARC), alwaysStereo ? "Immer Stereo" : nil,
                             keepsMode ? "HDMI-Modus halten" : nil, dolbyVisionForced ? "Dolby Vision fest" : nil])
    }
}
