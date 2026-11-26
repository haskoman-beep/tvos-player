import Foundation
import Testing
@testable import PlayerCore

// Integration build 5 (user decision 26.11.): the old rows „Plaketten-Stil“ (Aussehen) and „Titelbild oben“
// (Startseite) are gone; only the look rows `badgeStyle` and `heroStyle` remain. An old value that the stored look
// does not map to moves into the look once, on load, in both directions (review L3: the old field is the truth). The JSON format stays: the old fields still
// decode and are still written.

private func roundTrip(_ p: Profile) throws -> Profile {
    try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(p))
}

/// A profile whose look is stored (not derived from the old fields): `cardShape` maps to no old field.
private func storedLookProfile() -> Profile {
    var p = Profile.makeDefault()
    p.setLook("cardShape", to: "poster")
    return p
}

@Test func oldBadgeStyleRowMovesIntoLookOnLoad() throws {
    var p = storedLookProfile()
    p.appearance.badges.style = .text   // as the old row „Plaketten-Stil“ did
    #expect(p.look.resolved().detail.badgeStyle == .logos)
    var q = p
    #expect(q.adoptOldLookRows() == ["badgeStyle"])
    let back = try roundTrip(p)
    #expect(back.look.resolved().detail.badgeStyle == .text)
    #expect(back.look.resolved().home.cardShape == .poster)
    #expect(back.appearance.badges.style == .text)   // old field still decodes and stays
    #expect(back.themeLook.detail.badgeStyle == .text)
}

@Test func oldHeroToggleOffMovesIntoLookOnLoad() throws {
    var p = storedLookProfile()
    p.appearance.heroEnabled = false   // as the old row „Titelbild oben“ did
    #expect(p.look.resolved().home.heroStyle == .vollbild)
    let back = try roundTrip(p)
    #expect(back.look.resolved().home.heroStyle == .aus)
    #expect(!back.appearance.heroEnabled)
    #expect(back.themeLook.home.heroStyle == .aus)
}

@Test func oldLookRowsMigrationIsIdempotentAndLeavesDefaultsAlone() throws {
    var p = storedLookProfile()
    p.appearance.badges.style = .text
    p.appearance.heroEnabled = false
    var back = try roundTrip(p)
    let look = back.look
    #expect(back.adoptOldLookRows().isEmpty)
    #expect(back.look == look)
    #expect(try roundTrip(back).look == look)
    // Old fields at their defaults: nothing moves.
    var d = storedLookProfile()
    let before = d.look
    #expect(d.adoptOldLookRows().isEmpty)
    #expect(try roundTrip(d).look == before)
    // A derived look (old profile without `look`) already follows the old fields.
    var old = Profile.makeDefault()
    old.appearance.badges.style = .text
    #expect(old.adoptOldLookRows().isEmpty)
    #expect(try roundTrip(old).themeLook.detail.badgeStyle == .text)
}

@Test func oldLogoBadgeFieldOverridesStoredOutlineLook() throws {
    // Review L3: old field logo + stored umriss → logos (the old field is the truth).
    var p = storedLookProfile()
    p.setLook("badgeStyle", to: "umriss")
    p.appearance.badges.style = .logo
    #expect(p.adoptOldLookRows() == ["badgeStyle"])
    #expect(p.look.resolved().detail.badgeStyle == .logos)
    #expect(try roundTrip(p).themeLook.detail.badgeStyle == .logos)
}

@Test func oldHeroToggleOnOverridesStoredHeroOff() throws {
    // Review L3: old field on + stored aus → the preset's hero style, as `themeLook` shows it.
    var p = storedLookProfile()
    p.setLook("heroStyle", to: "aus")
    p.appearance.heroEnabled = true
    #expect(p.adoptOldLookRows() == ["heroStyle"])
    let preset = LookPreset.values(p.look.preset).home.heroStyle
    #expect(p.look.resolved().home.heroStyle == preset)
    #expect(p.themeLook.home.heroStyle == preset)
    #expect(try roundTrip(p).look.resolved().home.heroStyle == preset)
}

@Test func oldLookRowsMigrationKeepsLookVersion() {
    // Review L4: the migration replaces only the overrides.
    var p = storedLookProfile()
    p.look.version = 99
    p.appearance.badges.style = .text
    #expect(p.adoptOldLookRows() == ["badgeStyle"])
    #expect(p.look.version == 99)
    #expect(p.look.resolved().home.cardShape == .poster)
}

@Test func oldTextBadgeFieldKeepsOutlineLook() throws {
    // „Umriss“ maps to the old field text: consistent, so the look keeps umriss.
    var p = storedLookProfile()
    p.setLook("badgeStyle", to: "umriss")
    #expect(p.appearance.badges.style == .text)
    let back = try roundTrip(p)
    #expect(back.look.resolved().detail.badgeStyle == .umriss)
    #expect(back.themeLook.detail.badgeStyle == .umriss)
}

@Test func badgeSettingsDrawnInLookStyle() {
    let s = BadgeSettings()
    #expect(s.style == .logo)
    #expect(s.drawn(as: .text).style == .text)
    #expect(s.drawn(as: .umriss).style == .text)
    #expect(s.drawn(as: .gefuellt).style == .text)
    var t = s; t.style = .text
    #expect(t.drawn(as: .logos).style == .logo)
    #expect(t.drawn(as: .logos).resolution == s.resolution)   // only the style changes
}
