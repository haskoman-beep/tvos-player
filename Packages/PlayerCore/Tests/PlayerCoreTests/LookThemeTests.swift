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

// Fix round 1 (review M1/M2): the "no visible change" decisions, and why make(default) differs from standard only
// in the accent.
@Test func defaultThemeLookUsesNoPlanTokens() {
    let v = Profile.makeDefault().themeLook
    #expect(!LookTheme.usesPlanBackground(v))
    #expect(!LookTheme.usesPlanType(scale: v.global.typeScale, character: v.global.typeCharacter))
    #expect(!LookTheme.usesPlanMotion(v, reduceMotion: false))
    #expect(LookTheme.usesPlanMotion(v, reduceMotion: true))
    // ThemeValues.standard carries the preset accent; the default profile's old accent (blue) maps to blau.
    #expect(LookPreset.values(.appleTV).global.accent == .weiss)
    #expect(v.global.accent == .blau)
}

@Test func planTokenDecisionsFollowThePreset() {
    var v = LookPreset.values(.appleTV)
    v.global.background = .warm
    #expect(LookTheme.usesPlanBackground(v))
    #expect(LookTheme.usesPlanType(scale: .gross, character: .neutral))
    #expect(LookTheme.usesPlanType(scale: .standard, character: .editorial))
    v.global.motion = .dezent
    #expect(LookTheme.usesPlanMotion(v, reduceMotion: false))
}

// Review M3: every row of both color tables against the plan.
@Test func themeColorTablesCompleteAgainstPlan() {
    let accents: [LookAccent: (UInt32, UInt32)] = [
        .champagner: (0xD4B87A, 0x17140C), .weiss: (0xF2F1EC, 0x111111), .eisblau: (0x8FC7FF, 0x06121D),
        .blau: (0x3B82F6, 0xFFFFFF), .rot: (0xE5383B, 0xFFFFFF), .koralle: (0xFF7A59, 0x1D0A04),
        .salbei: (0x9FC5A8, 0x0B160E), .violett: (0xA78BFA, 0x120A26),
    ]
    #expect(accents.count == LookAccent.allCases.count)
    for (a, c) in accents { #expect(LookTheme.accent(a) == .init(accent: c.0, onAccent: c.1)) }
    let bgs: [LookBackground: (UInt32, UInt32, UInt32)] = [
        .schwarz: (0x000000, 0x131314, 0x1F1F20), .graphit: (0x0B0C0E, 0x17191D, 0x22252B),
        .tinte: (0x070B14, 0x111827, 0x1E2432), .warm: (0x0E0B08, 0x1C1713, 0x27231F),
    ]
    #expect(bgs.count == LookBackground.allCases.count)
    for (b, c) in bgs { #expect(LookTheme.background(b) == .init(base: c.0, surface: c.1, raised: c.2)) }
}
