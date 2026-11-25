import Foundation
import Testing
@testable import PlayerCore

// Task 4.5-base (user decision 25.11.): the old default values are the baseline. An untouched profile (new, or a
// Build 3 profile nobody edited) shows "Standard" (user decision 25.11., first "Apple TV"); only real changes count.

private func baselineFixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

@Test func baselineIsTheMigratedOldDefaults() {
    let migrated = Look.migrated(from: Appearance(), player: PlayerComfortSettings(), sources: SourceSettings())
    #expect(LookPreset.baseline == migrated.resolved())
    #expect(Profile(name: "T").themeLook == LookPreset.baseline)
}

@Test func freshProfileShowsStandard() {
    let p = Profile(name: "T")
    #expect(SettingsSummary.lookValue(p) == "Standard")
    #expect(SettingsSummary.look(p) == "Mein Look · Standard")
    for e in LookOptionCatalog.all { #expect(!p.isLookOverridden(e.key), "\(e.key)") }
    #expect(SettingsSummary.lookValue(Profile.makeDefault()) == "Standard")
}

@Test func build3ProfileWithoutLookShowsStandard() throws {
    let stored = try ProfileStore.decode(try baselineFixture("build249-profiles.json"))
    // Profile 1 keeps every old default (blue, medium, expand on, hero on, sidebar, logo badges, topBar).
    #expect(SettingsSummary.lookValue(stored.profiles[1]) == "Standard")
    // Profile 0 changed navigation, accent, card size, hero and badge style in Build 3: those count.
    #expect(SettingsSummary.lookValue(stored.profiles[0]) == "angepasst · 5")
}

@Test func oneChangeCountsOne() {
    var p = Profile(name: "T")
    p.setLook("cardSize", to: "gross")
    #expect(SettingsSummary.lookValue(p) == "angepasst · 1")
    #expect(p.isLookOverridden("cardSize"))
    #expect(!p.isLookOverridden("navigation"))
    #expect(p.appearance.cardSize == .large)
    // The same change in the old settings counts the same.
    var q = Profile(name: "T")
    q.appearance.cardSize = .large
    #expect(SettingsSummary.lookValue(q) == "angepasst · 1")
}

@Test func setLookToBaselineValueCountsZero() {
    var p = Profile(name: "T")
    p.setLook("cardSize", to: "gross")
    p.setLook("cardSize", to: "mittel")       // the old default
    #expect(SettingsSummary.lookValue(p) == "Standard")
    p.setLook("accent", to: "rot")
    p.setLook("accent", to: nil)              // nil = back to the baseline, not to the preset's weiss
    #expect(p.themeLook.global.accent == .blau)
    #expect(p.appearance.accent == .blue)
    #expect(SettingsSummary.lookValue(p) == "Standard")
    // Unknown key or value changes nothing.
    let before = p
    p.setLook("nope", to: nil)
    p.setLook("accent", to: "neonpink")
    #expect(p == before)
}

@Test func resetLookReturnsToBaseline() throws {
    var p = Profile(name: "T")
    p.setLook("accent", to: "rot")
    p.setLook("navigation", to: "oben")
    p.setLook("background", to: "tinte")
    p.player.trackPanelStyle = .menu
    p.appearance.heroEnabled = false
    #expect(SettingsSummary.lookValue(p) == "angepasst · 5")
    p.resetLook()
    #expect(SettingsSummary.lookValue(p) == "Standard")
    #expect(p.themeLook == LookPreset.baseline)
    #expect(p.appearance == Appearance())
    #expect(p.player == PlayerComfortSettings())
    // Back to a look that only mirrors the old fields: not written, so the Build 3 bytes come back.
    #expect(!String(decoding: try JSONEncoder().encode(p), as: UTF8.self).contains(#""look""#))
}

@Test func importedLookCountsAgainstBaseline() throws {
    // The configurator export is exactly the Apple TV preset; against the old defaults it differs in six keys
    // (navigation, accent, cardSize, expandPosters, badgeStyle, trackPanel).
    let (look, _) = try LookImport.parse(try baselineFixture("konfigurator-export.json"))
    #expect(look.resolved() == LookPreset.values(.appleTV))
    #expect(SettingsSummary.lookValue(look) == "angepasst · 6")
    var p = Profile(name: "T")
    p.applyImportedLook(look)
    #expect(p.themeLook == LookPreset.values(.appleTV))   // still written with its exact values
    #expect(SettingsSummary.lookValue(p) == "angepasst · 6")
    #expect(p.isLookOverridden("navigation"))
    #expect(!p.isLookOverridden("background"))
    // An import with the baseline values counts zero.
    let base = Look(overrides: LookOverrides.difference(LookPreset.baseline, from: LookPreset.values(.appleTV)))
    #expect(SettingsSummary.lookValue(base) == "Standard")
    #expect(LookOptionCatalog.isOverridden("navigation", in: look.overrides))
    #expect(!LookOptionCatalog.isOverridden("navigation", in: base.overrides))
}
