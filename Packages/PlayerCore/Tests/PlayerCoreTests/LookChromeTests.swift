import Foundation
import Testing
@testable import PlayerCore

// Task 5.6 (D-19, D-28): main navigation, clock and settings layout from the look.

@Test func settingsTreeIsSameForAllLayouts() {
    // Every layout shows the phone entry once and all nine categories in the same order; only the headers differ.
    let columns = SettingsLayoutTree.entries(.spalten)
    for layout in LookSettingsLayout.allCases {
        let e = SettingsLayoutTree.entries(layout)
        #expect(e.filter { $0 == .phone }.count == 1, "phone entry in \(layout)")
        #expect(e.first == .phone, "phone entry first in \(layout)")
        #expect(SettingsLayoutTree.categories(e) == SettingsCategory.allCases, "categories in \(layout)")
        #expect(SettingsLayoutTree.categories(e) == SettingsLayoutTree.categories(columns))
    }
    // Two columns keep today's group headers (System only with a gap), tiles have none, the list names each
    // category (its rows follow under the header).
    #expect(columns == [.phone, .group(.content), .category(.profile), .category(.addons), .category(.sources),
                        .group(.interface), .category(.home), .category(.appearance),
                        .group(.playback), .category(.playback), .category(.audio), .category(.picture),
                        .group(.system), .category(.system)])
    #expect(SettingsLayoutTree.entries(.kacheln) == [.phone] + SettingsCategory.allCases.map { .category($0) })
    #expect(SettingsLayoutTree.entries(.liste) == [.phone] + SettingsCategory.allCases.map { .category($0) })
}

@Test func clockTextUsesLocale24h() {
    let utc = TimeZone(identifier: "UTC")!
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = utc
    let evening = cal.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: 20, minute: 5))!
    let morning = cal.date(from: DateComponents(year: 2026, month: 11, day: 26, hour: 7, minute: 9))!
    let de = Locale(identifier: "de_DE")
    #expect(LookChrome.clockText(evening, locale: de, timeZone: utc) == "20:05")
    #expect(LookChrome.clockText(morning, locale: de, timeZone: utc) == "07:09")
    // 24 h even where the locale would say "8:05 PM".
    let us = LookChrome.clockText(evening, locale: Locale(identifier: "en_US"), timeZone: utc)
    #expect(us == "20:05")
    #expect(!us.contains("PM"))
    // The time zone is honoured (UTC+1 in November).
    #expect(LookChrome.clockText(evening, locale: de, timeZone: TimeZone(identifier: "Europe/Berlin")!) == "21:05")

    // Plan: meta role 27 pt × typeScale, weight 500, white 75 %, right 80, top 56; hidden in the player.
    let std = LookChrome(LookPreset.values(.appleTV))
    #expect(std.clockFontSize == 27)
    #expect(LookChrome.clockWeight == 500 && LookChrome.clockOpacity == 0.75)
    #expect(LookChrome.clockTrailing == 80 && LookChrome.clockTop == 56)
    var big = LookPreset.values(.appleTV)
    big.global.typeScale = .gross
    #expect(LookChrome(big).clockFontSize == 27 * LookMetrics.typeScale(.gross))
    #expect(!std.showsClock)   // Mein Look: clock off
    big.global.clock = true
    #expect(LookChrome(big).showsClock)
}

@Test func contentLeadingFollowsNavigation() {
    var v = LookPreset.values(.appleTV)
    v.global.navigation = .seitenleiste
    let side = LookChrome(v)
    #expect(side.contentLeading == 150)
    #expect(side.leadingExtra == 70)
    #expect(side.navigationStyle == .sidebar)
    v.global.navigation = .oben
    let top = LookChrome(v)
    #expect(top.contentLeading == 80)
    #expect(top.leadingExtra == 0)
    #expect(top.navigationStyle == .top)
    // The navigation the root reads follows the old field the settings write (themeLook), both ways.
    var p = Profile(name: "A")
    p.appearance.navigation = .top
    #expect(LookChrome(p.themeLook).navigationStyle == .top)
    p.setLook("navigation", to: "seitenleiste")
    #expect(p.appearance.navigation == .sidebar && LookChrome(p.themeLook).navigationStyle == .sidebar)
}

@Test func settingsTilesUseCornersAndLayoutLatch() {
    // Tiles: 4 columns, gap 26, height 230, radius cornerRadius + 6.
    var v = LookPreset.values(.appleTV)
    #expect(LookChrome.tileColumns == 4 && LookChrome.tileSpacing == 26 && LookChrome.tileHeight == 230)
    #expect(LookChrome(v).tileRadius == LookMetrics.cornerRadius(v.home.corners) + 6)
    v.home.corners = .eckig
    #expect(LookChrome(v).tileRadius == 6)
    // A layout change waits while a settings subpage is open (its link would vanish and pop the page).
    #expect(SettingsLayoutTree.shown(latched: .spalten, current: .kacheln, rootVisible: false) == .spalten)
    #expect(SettingsLayoutTree.shown(latched: .spalten, current: .kacheln, rootVisible: true) == .kacheln)
    #expect(SettingsLayoutTree.shown(latched: nil, current: .liste, rootVisible: false) == .liste)
}

@Test func navigationClockAndLayoutRowsAreActive() {
    let v = LookPreset.values(.appleTV)
    for key in ["navigation", "clock", "settingsLayout"] {
        #expect(LookOptionCatalog.isEnabled(key, in: v) == (true, nil), "\(key)")
    }
    var p = Profile(name: "A")
    p.setLook("clock", to: "true")
    p.setLook("settingsLayout", to: "kacheln")
    #expect(LookChrome(p.themeLook).showsClock && LookChrome(p.themeLook).settingsLayout == .kacheln)
}
