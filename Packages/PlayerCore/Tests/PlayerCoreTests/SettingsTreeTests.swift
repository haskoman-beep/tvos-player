import Foundation
import Testing
@testable import PlayerCore

// Wave S: settings tree "3 Gruppen + System".

@Test func settingsTreeOrderAndGroups() {
    #expect(SettingsCategory.allCases.map(\.title) == [
        "Profil & Konten", "Addons", "Quellen",
        "Startseite", "Aussehen",
        "Wiedergabe", "Sprache & Untertitel", "Bild & Ton",
        "System",
    ])
    #expect(SettingsGroup.content.categories == [.profile, .addons, .sources])
    #expect(SettingsGroup.interface.categories == [.home, .appearance])
    #expect(SettingsGroup.playback.categories == [.playback, .audio, .picture])
    #expect(SettingsGroup.system.categories == [.system])
    #expect(SettingsGroup.allCases.map(\.title) == ["Inhalte", "Oberfläche", "Wiedergabe", nil])
    // Groups are contiguous: walking the list, each group starts exactly once.
    #expect(SettingsCategory.allCases.filter(\.startsGroup) == [.profile, .home, .playback, .system])
    #expect(SettingsGroup.allCases.flatMap(\.categories) == SettingsCategory.allCases)
}

@Test func settingsTreeScopeLabelsMatchStorage() {
    // Every row outside System is bound to the active profile (AppModel.binding); only System is per device.
    for c in SettingsCategory.allCases where c != .system {
        #expect(c.scope == .profile)
    }
    #expect(SettingsCategory.system.scope == .device)
    #expect(SettingsScope.profile.label == "Gilt für dieses Profil")
    #expect(SettingsScope.device.label == "Gilt für dieses Gerät")
}

@Test func settingsTreeKeepsCaseNamesForTints() {
    // Raw values of the old seven categories stay as they were (other code refers to them by name).
    for old in ["profile", "addons", "home", "appearance", "playback", "audio", "system"] {
        #expect(SettingsCategory(rawValue: old) != nil)
    }
}

@Test func summaryAddonsSourcesPicture() {
    #expect(SettingsSummary.addonsPage(count: 3, timeoutSeconds: 12) == "3 Addons · Zeitgrenze 12 s")
    #expect(SettingsSummary.addonsPage(count: 1, timeoutSeconds: 13) == "1 Addon · Zeitgrenze 12 s")
    #expect(SettingsSummary.addonsPage(count: 0, timeoutSeconds: 12) == "Kein Addon")
    #expect(SettingsSummary.sources(order: .smart, prefetch: true, instantPlay: false) == "Smart sortiert · vorladen an")
    #expect(SettingsSummary.sources(order: .addon, prefetch: false, instantPlay: true)
            == "Wie Addon sortiert · vorladen aus · Sofort abspielen")
    #expect(SettingsSummary.picture(soundSystemEARC: false, keepsMode: true, dolbyVisionForced: false, alwaysStereo: false)
            == "Über Fernseher (optisch/ARC) · HDMI-Modus halten")
    #expect(SettingsSummary.picture(soundSystemEARC: true, keepsMode: false, dolbyVisionForced: true, alwaysStereo: true)
            == "AV-Receiver mit eARC · Immer Stereo · Dolby Vision fest")
}
