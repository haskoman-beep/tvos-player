import Foundation
import Testing
@testable import PlayerCore

/// Fixture `main-profiles-v1.json`: vollständige Sicherung, geschrieben mit dem Profil-Code des main-Stands
/// vor dem Design-Umbau (alle damaligen Felder belegt, keines der neuen). Schlüssel und Tokens sind Testwerte.
@Test func mainProfileBackupLoadsWithAllFieldsAndNewDefaults() throws {
    let s = try ProfileStore(directory: FileManager.default.temporaryDirectory).importData(fixture("main-profiles-v1.json"))
    #expect(s.schemaVersion == 1)
    #expect(s.profiles.count == 1)
    let p = try #require(s.active)
    #expect(p.id == UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE"))

    // Alte Felder bleiben erhalten.
    #expect(p.name == "Wohnzimmer")
    #expect(p.language == .en)
    #expect(p.audioPriority == ["en", "orig", "de"])
    #expect(p.subtitleLanguage == "en")
    #expect(p.progressSource == .trakt)
    #expect(p.addons.map(\.manifestURL) == ["https://addon.example/manifest.json"])
    #expect(p.addons.first?.manifest.idPrefixes == ["tt"])
    #expect(p.collections.first?.folders.first?.sources.first?.id == "s1")
    #expect(p.home.rows.count == 2)
    #expect(p.home.rows.first?.style == .landscape)
    #expect(p.apiKeys == ["tmdb": "TESTKEY-NOT-REAL"])
    #expect(p.autoplayNext == false)
    #expect(p.syncTokens["trakt"]?.refreshToken == "test-refresh")
    #expect(p.syncTokens["trakt"]?.expiresAt == Date(timeIntervalSince1970: 1_900_000_000))
    #expect(p.appearance.navigation == .top)
    #expect(p.appearance.accent == .green)
    #expect(p.appearance.cardSize == .large)
    #expect(p.appearance.heroEnabled == false)
    #expect(p.appearance.heroRowID == UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
    #expect(p.appearance.expandPosters == false)

    // Altes subtitlesEnabled = true → Modus „immer“.
    #expect(p.subtitleMode == .always)
    // Neue Felder: Standardwerte.
    #expect(p.stillWatchingAfter == StillWatchingCounter.defaultLimit)
    #expect(p.diskCache == DiskCacheSettings())
    #expect(p.diskCache.enabled == false)
    #expect(p.appearance.prefetchStreams == true)
    #expect(p.appearance.badges == BadgeSettings())
}
