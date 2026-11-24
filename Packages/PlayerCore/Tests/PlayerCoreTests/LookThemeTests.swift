import Foundation
import Testing
@testable import PlayerCore

// Task 4.4 (D-3, D-9, D-12, D-13, D-15, D-17, D-27): pure tables of the runtime theme and the look it is built from.

@Test func themeLookTakesOldFieldsOverStoredLook() {
    var p = Profile(name: "T")
    p.appearance.accent = .green
    p.appearance.cardSize = .small
    p.appearance.heroEnabled = false
    // A stale stored look (e.g. read from disk before the user changed the old settings).
    var stale = LookOverrides()
    stale.global.accent = .rot
    stale.home.cardSize = .gross
    stale.home.heroStyle = .banner
    p.look = Look(preset: .appleTV, overrides: stale)
    let v = p.themeLook
    #expect(v.global.accent == .salbei)
    #expect(v.home.cardSize == .klein)
    #expect(v.home.heroStyle == .aus)
    // No drift: whatever the stored look says, the old fields decide these keys.
    #expect(v.global.navigation == Look.migrated(from: p.appearance, player: p.player, sources: p.sources)
        .resolved().global.navigation)
}

@Test func themeLookKeepsStoredOverridesWithoutOldField() {
    var p = Profile(name: "T")
    var o = LookOverrides()
    o.global.background = .tinte
    o.global.typeScale = .gross
    o.global.motion = .aus
    o.home.heroStyle = .banner
    p.look = Look(preset: .appleTV, overrides: o)
    let v = p.themeLook
    #expect(v.global.background == .tinte)
    #expect(v.global.typeScale == .gross)
    #expect(v.global.motion == .aus)
    #expect(v.home.heroStyle == .banner)   // hero on: a stored style stays
    // Untouched profile: the theme look is exactly the migrated look.
    let fresh = Profile(name: "U")
    #expect(fresh.themeLook == Look.migrated(from: fresh.appearance, player: fresh.player, sources: fresh.sources)
        .resolved())
}

@Test func themeColorTablesMatchPlan() {
    #expect(LookTheme.accent(.champagner) == .init(accent: 0xD4B87A, onAccent: 0x17140C))
    #expect(LookTheme.accent(.blau) == .init(accent: 0x3B82F6, onAccent: 0xFFFFFF))
    #expect(LookTheme.accent(.violett) == .init(accent: 0xA78BFA, onAccent: 0x120A26))
    #expect(Set(LookAccent.allCases.map { LookTheme.accent($0).accent }).count == LookAccent.allCases.count)
    #expect(LookTheme.background(.schwarz) == .init(base: 0x000000, surface: 0x131314, raised: 0x1F1F20))
    #expect(LookTheme.background(.graphit) == .init(base: 0x0B0C0E, surface: 0x17191D, raised: 0x22252B))
    // Every tone gets lighter from base to surface to raised.
    for b in LookBackground.allCases {
        let c = LookTheme.background(b)
        func lum(_ x: UInt32) -> UInt32 { (x >> 16 & 0xFF) + (x >> 8 & 0xFF) + (x & 0xFF) }
        #expect(lum(c.base) < lum(c.surface) && lum(c.surface) < lum(c.raised))
    }
}

@Test func themeTypeTableMatchesPlan() {
    let d = LookTheme.type(.display, scale: .standard, character: .editorial)
    #expect(d.size == 76 && d.weight == 300 && d.tracking == -0.025 && d.lineHeight == 1.02)
    #expect(LookTheme.type(.meta, scale: .standard, character: .technisch).tracking == 0.05)
    #expect(LookTheme.type(.body, scale: .gross, character: .neutral).size == 29 * 1.12)
    #expect(LookTheme.type(.badge, scale: .kompakt, character: .neutral).size == 23 * 0.9)
    // Readable text never under 26 pt at standard scale; only the badge stays at 23 (07 §3.2).
    for r in LookTheme.Role.allCases where r != .badge {
        #expect(LookTheme.type(r, scale: .standard, character: .neutral).size >= 26)
    }
}

@Test func themeMotionOffWhenSystemReducesMotion() {
    #expect(LookTheme.motion(.standard, reduceMotion: true) == LookMetrics.motion(.aus))
    #expect(LookTheme.motion(.dezent, reduceMotion: false).focus == 0.18)
}
