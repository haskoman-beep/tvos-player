import Foundation
import Testing
@testable import PlayerCore

// Wave F-n: „Sofort abspielen“ setting and the detail poster size.

@Test func instantPlaySettingDefaultsOff() throws {
    #expect(PlayerComfortSettings().instantPlay == false)
    #expect(Profile(name: "x").player.instantPlay == false)
    // Older profile without the field: off; other fields keep their stored values.
    let old = try JSONDecoder().decode(PlayerComfortSettings.self, from: Data(#"{"rememberTracks":false}"#.utf8))
    #expect(!old.instantPlay && !old.rememberTracks)
    // Wrong type falls back to the default instead of dropping the settings.
    let bad = try JSONDecoder().decode(PlayerComfortSettings.self, from: Data(#"{"instantPlay":"ja"}"#.utf8))
    #expect(!bad.instantPlay)
    var s = PlayerComfortSettings()
    s.instantPlay = true
    let back = try JSONDecoder().decode(PlayerComfortSettings.self, from: JSONEncoder().encode(s))
    #expect(back.instantPlay)
}

@Test func instantPlaySettingRoundTripsInProfile() throws {
    var p = Profile(name: "x")
    p.player.instantPlay = true
    let back = try JSONDecoder().decode(Profile.self, from: JSONEncoder().encode(p))
    #expect(back.player.instantPlay)
}

@Test func instantPlayCardOnlyForMoviesWithSetting() {
    #expect(DetailPage.showsInstantPlay(setting: true, isSeries: false))
    #expect(!DetailPage.showsInstantPlay(setting: false, isSeries: false))
    #expect(!DetailPage.showsInstantPlay(setting: true, isSeries: true))
    #expect(!DetailPage.showsInstantPlay(setting: false, isSeries: true))
}

@Test func mainActionIsPlayUnlessCardWithPick() {
    // Off (default): always „Abspielen“, also when a pick would exist.
    #expect(DetailPage.mainAction(setting: false, isSeries: false, hasPick: true) == .play)
    #expect(DetailPage.mainAction(setting: false, isSeries: false, hasPick: false) == .play)
    // On: the card with a pick, else „Abspielen“ (the „Keine Quelle“ button never takes the focus).
    #expect(DetailPage.mainAction(setting: true, isSeries: false, hasPick: true) == .instantPlay)
    #expect(DetailPage.mainAction(setting: true, isSeries: false, hasPick: false) == .play)
    // Series never show the card.
    #expect(DetailPage.mainAction(setting: true, isSeries: true, hasPick: true) == .play)
}

@Test func lateCardTakesFocusOnlyWhenShownAndEarly() {
    #expect(DetailPage.lateCardTakesFocus(setting: true, isSeries: false, focusOnPlay: true, sinceEntry: 0.5))
    #expect(DetailPage.lateCardTakesFocus(setting: true, isSeries: false, focusOnPlay: true, sinceEntry: 2))
    #expect(!DetailPage.lateCardTakesFocus(setting: true, isSeries: false, focusOnPlay: true, sinceEntry: 2.1))
    #expect(!DetailPage.lateCardTakesFocus(setting: true, isSeries: false, focusOnPlay: false, sinceEntry: 0.5))
    #expect(!DetailPage.lateCardTakesFocus(setting: true, isSeries: false, focusOnPlay: true, sinceEntry: nil))
    #expect(!DetailPage.lateCardTakesFocus(setting: false, isSeries: false, focusOnPlay: true, sinceEntry: 0.5))
    #expect(!DetailPage.lateCardTakesFocus(setting: true, isSeries: true, focusOnPlay: true, sinceEntry: 0.5))
}

@Test func detailPosterMatchesBlockHeight() throws {
    // Long description (meta line, badges, three lines): poster exactly as tall as the block minus the inset.
    let long = try #require(DetailPage.posterSize(blockHeight: 262, bottomInset: 10))
    #expect(long.height == 252 && long.width == 168)
    // 4K is laid out in the same points; a taller block gives a proportionally wider poster.
    let tall = try #require(DetailPage.posterSize(blockHeight: 300.4))
    #expect(tall.height == 300 && tall.width == 200)
    // Negative insets are ignored.
    #expect(DetailPage.posterSize(blockHeight: 200, bottomInset: -5)?.height == 200)
}

@Test func detailPosterLeftOutWhenBlockTooSmall() {
    // Meta line and badges only (no description): too small for a poster.
    #expect(DetailPage.posterSize(blockHeight: 90) == nil)
    #expect(DetailPage.posterSize(blockHeight: 125, bottomInset: 10) == nil)
    #expect(DetailPage.posterSize(blockHeight: 0) == nil)
    #expect(DetailPage.posterSize(blockHeight: .infinity) == nil)
    #expect(DetailPage.posterSize(blockHeight: .nan) == nil)
    #expect(DetailPage.posterSize(blockHeight: 120) != nil)
}

@Test func detailPosterMeasurementIgnoresJitter() {
    #expect(!DetailPage.shouldUpdate(measured: 250.4, stored: 250))
    #expect(DetailPage.shouldUpdate(measured: 251, stored: 250))
    #expect(DetailPage.shouldUpdate(measured: 0, stored: 250))
}
