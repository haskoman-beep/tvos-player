import Foundation
import Testing
@testable import PlayerCore

// Task 4.2 (D-28, D-1): the look model. One preset, "Mein Look" (= configurator preset "appletv"), plus overrides.
// `Fixtures/konfigurator-export.json` is a copy of `docs/design/konfigurator/export.json`.

private func lookFixture(_ name: String) throws -> Data {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

private func sortedJSON<T: Encodable>(_ value: T) throws -> JSONValue {
    let enc = JSONEncoder()
    enc.outputFormatting = [.sortedKeys]
    return try JSONDecoder().decode(JSONValue.self, from: enc.encode(value))
}

/// Number of leaf values in a JSON object tree.
private func leafCount(_ v: JSONValue) -> Int {
    if case .object(let o) = v { return o.values.map(leafCount).reduce(0, +) }
    return 1
}

@Test func lookDecodesUnknownValueAsPresetDefault() throws {
    let json = #"{"version":1,"preset":"appletv","overrides":{"global":{"accent":"neonpink","background":"graphit"},"#
        + #""home":{"cardSize":17,"focusGlow":false},"detail":{"descriptionLines":4}}}"#
    let (look, report) = try JSONDecoder().decodeReporting(Look.self, from: Data(json.utf8))
    #expect(look.overrides.global.accent == nil)
    #expect(look.overrides.global.background == .graphit)
    #expect(look.overrides.home.cardSize == nil)
    #expect(look.overrides.home.focusGlow == false)
    #expect(look.overrides.detail.descriptionLines == nil)
    #expect(Set(report.ignored) == ["overrides.global.accent", "overrides.home.cardSize",
                                    "overrides.detail.descriptionLines"])
    let values = look.resolved()
    #expect(values.global.accent == .weiss)
    #expect(values.global.background == .graphit)
    #expect(values.home.cardSize == .gross)
    #expect(values.detail.descriptionLines == .two)

    // Not even a wrong type for the whole block throws.
    let (broken, brokenReport) = try JSONDecoder().decodeReporting(Look.self,
        from: Data(#"{"version":"x","preset":7,"overrides":[1,2]}"#.utf8))
    #expect(broken == Look())
    #expect(Set(brokenReport.ignored) == ["version", "preset", "overrides"])
}

@Test func unknownPresetIDFallsBackToAppleTV() throws {
    for raw in ["edel", "infuse", "kino", "streaming", "zukunft"] {
        let json = #"{"version":1,"preset":"\#(raw)","overrides":{"global":{"accent":"rot"}}}"#
        let (look, report) = try JSONDecoder().decodeReporting(Look.self, from: Data(json.utf8))
        #expect(look.preset == .appleTV)
        #expect(look.overrides.global.accent == .rot)
        #expect(report.ignored == ["preset"])
    }
    #expect(LookPresetID.appleTV.rawValue == "appletv")
    #expect(LookPresetID.appleTV.title == "Mein Look")
    #expect(LookPresetID.allCases == [.appleTV])
}

@Test func lookMissingInOldProfileMigratesFromAppearance() throws {
    // main-profiles-v1: accent green, cardSize large, expandPosters false, heroEnabled false, navigation top,
    // no badges (default style logo), no player block (default trackPanelStyle topBar).
    let stored = try ProfileStore.decode(try lookFixture("main-profiles-v1.json"))
    let look = try #require(stored.profiles.first).look
    #expect(look.preset == .appleTV)
    #expect(look.version == LookSchema.current)
    var expected = LookOverrides()
    expected.global.accent = .salbei
    expected.home.heroStyle = .aus
    expected.detail.badgeStyle = .logos
    expected.player.trackPanel = .seite
    #expect(look.overrides == expected)
    #expect(look.overrides.count == 4)

    // Build 3 profiles (build249 shape = Build 3 keys) migrate as well, each one by its own fields.
    let b3 = try ProfileStore.decode(try lookFixture("build249-profiles.json"))
    let first = b3.profiles[0].look.overrides       // orange, large, expand on, hero off, top, badges text, topBar
    #expect(first.global.accent == .koralle)
    #expect(first.global.navigation == nil)
    #expect(first.home.cardSize == nil)
    #expect(first.home.expandPosters == true)
    #expect(first.home.heroStyle == .aus)
    #expect(first.detail.badgeStyle == nil)
    #expect(first.player.trackPanel == .seite)
    let second = b3.profiles[1].look.overrides      // blue, medium, expand on, hero on, sidebar, logo, topBar
    #expect(second.global.navigation == .seitenleiste)
    #expect(second.global.accent == .blau)
    #expect(second.home.cardSize == .mittel)
    #expect(second.home.heroStyle == nil)
    #expect(second.detail.badgeStyle == .logos)
}

@Test func lookMigrationTableIsComplete() {
    func migrated(_ a: Appearance = Appearance(), _ p: PlayerComfortSettings = PlayerComfortSettings()) -> LookValues {
        Look.migrated(from: a, player: p, sources: SourceSettings()).resolved()
    }
    let nav: [(NavigationStyle, LookNavigation)] = [(.sidebar, .seitenleiste), (.top, .oben)]
    for (old, new) in nav { #expect(migrated(Appearance(navigation: old)).global.navigation == new) }
    let accents: [(AccentChoice, LookAccent)] = [(.blue, .blau), (.purple, .violett), (.pink, .koralle),
                                                (.orange, .koralle), (.green, .salbei), (.white, .weiss)]
    for (old, new) in accents { #expect(migrated(Appearance(accent: old)).global.accent == new) }
    let sizes: [(CardSize, LookCardSize)] = [(.small, .klein), (.medium, .mittel), (.large, .gross)]
    for (old, new) in sizes { #expect(migrated(Appearance(cardSize: old)).home.cardSize == new) }
    #expect(migrated(Appearance(heroEnabled: false)).home.heroStyle == .aus)
    #expect(migrated(Appearance(heroEnabled: true)).home.heroStyle == .vollbild)
    #expect(migrated(Appearance(expandPosters: true)).home.expandPosters == true)
    #expect(migrated(Appearance(expandPosters: false)).home.expandPosters == false)
    #expect(migrated(Appearance(badges: BadgeSettings(style: .text))).detail.badgeStyle == .text)
    #expect(migrated(Appearance(badges: BadgeSettings(style: .logo))).detail.badgeStyle == .logos)
    let panels: [(TrackPanelStyle, LookTrackPanel)] = [(.topBar, .seite), (.bottomBar, .unten), (.menu, .mitte)]
    for (old, new) in panels {
        #expect(migrated(Appearance(), PlayerComfortSettings(trackPanelStyle: old)).player.trackPanel == new)
    }
    // A profile that already looks like "Mein Look" has no overrides.
    let same = Look.migrated(from: Appearance(navigation: .top, accent: .white, cardSize: .large, expandPosters: false,
                                              badges: BadgeSettings(style: .text)),
                             player: PlayerComfortSettings(trackPanelStyle: .bottomBar), sources: SourceSettings())
    #expect(same.overrides.isEmpty)
}

@Test func appleTVPresetShowsStandardHeroInfoAndFollowsFocus() {
    // User decision 26.11.: "Mein Look" shows the standard hero info (meta line, ratings, overview) and the
    // backdrop follows the focus; the clock stays off. Old profiles without these overrides get them as well.
    let v = LookPreset.values(.appleTV)
    #expect(v.home.heroInfo == .standard)
    #expect(v.home.backdropFollowsFocus)
    #expect(!v.global.clock)
    #expect(LookPreset.baseline.home.heroInfo == .standard && LookPreset.baseline.home.backdropFollowsFocus)
}

@Test func appleTVPresetResolvesCompletely() throws {
    let values = Look().resolved()
    #expect(values == LookPreset.values(.appleTV))
    let json = try sortedJSON(values)
    #expect(leafCount(json) == 35)
    guard case .object(let sections) = json else { Issue.record("not an object"); return }
    #expect(Set(sections.keys) == ["global", "home", "detail", "player"])
    #expect(Look().overrides.isEmpty)
    #expect(Look().overrides.count == 0)
}

@Test func overridesRoundTrip() throws {
    var look = Look()
    #expect(try sortedJSON(look.overrides) == .object([:]))
    look.overrides.global.accent = .eisblau
    look.overrides.global.clock = true
    look.overrides.home.focusGlow = false
    look.overrides.home.corners = .eckig
    look.overrides.detail.descriptionLines = .five
    look.overrides.player.stillWatching = .karte
    let data = try JSONEncoder().encode(look)
    let (back, report) = try JSONDecoder().decodeReporting(Look.self, from: data)
    #expect(back == look)
    #expect(report.isEmpty)
    #expect(try sortedJSON(back) == sortedJSON(look))
    // Only the touched sections are written.
    let text = String(decoding: data, as: UTF8.self)
    #expect(text.contains(#""descriptionLines":5"#))
    let r = back.resolved()
    #expect(r.global.accent == .eisblau && r.global.clock && !r.home.focusGlow && r.home.corners == .eckig)
    #expect(r.detail.descriptionLines == .five && r.player.stillWatching == .karte)
    #expect(r.home.cardShape == .querformat)
    #expect(back.overrides.count == 6)

    // Diff against the preset gives the overrides back.
    #expect(LookOverrides.difference(r, from: LookPreset.values(.appleTV)) == look.overrides)
}

@Test func configuratorExportMatchesAppleTVPreset() throws {
    let file = try JSONDecoder().decode(JSONValue.self, from: try lookFixture("konfigurator-export.json"))
    guard case .object(let top) = file else { Issue.record("export is not an object"); return }
    #expect(top["schema"] == .string("player.appearance.preset"))
    #expect(top["preset"] == .string(LookPresetID.appleTV.rawValue))
    let values = try #require(top["values"])
    #expect(leafCount(values) == 35)
    #expect(try sortedJSON(LookPreset.values(.appleTV)) == values)
}

@Test func lookHigherVersionIsReadLikeKnown() throws {
    let json = #"{"version":7,"preset":"appletv","newTopLevel":{"x":1},"#
        + #""overrides":{"global":{"accent":"rot","sparkle":true},"cinema":{"mode":"imax"}}}"#
    let (look, report) = try JSONDecoder().decodeReporting(Look.self, from: Data(json.utf8))
    #expect(look.version == 7)
    #expect(look.overrides.global.accent == .rot)
    #expect(report.isEmpty)
    #expect(LookMigration.upgrade(look, from: 7) == look)
    #expect(LookMigration.upgrade(look, from: 1) == look)
    // Written back in this build's own shape: unknown keys are gone, so the version is the writer's, not 7.
    let written = String(decoding: try JSONEncoder().encode(look), as: UTF8.self)
    #expect(written.contains(#""version":\#(LookSchema.current)"#))
    #expect(!written.contains(#""version":7"#))
}

@Test func derivedLookFollowsOldFieldsUntilRestyled() throws {
    // Profile 0 of build249: orange, hero off, topBar; its look is only derived from these fields.
    var p = try ProfileStore.decode(try lookFixture("build249-profiles.json")).profiles[0]
    p.appearance.accent = .blue
    p.player.trackPanelStyle = .bottomBar
    #expect(p.look.overrides.global.accent == .blau)
    #expect(p.look.overrides.player.trackPanel == nil)          // unten is the preset value
    #expect(p.look == Look.migrated(from: p.appearance, player: p.player, sources: p.sources))
    let data = try JSONEncoder().encode(p)
    #expect(!String(decoding: data, as: UTF8.self).contains(#""look""#))
    #expect(try JSONDecoder().decode(Profile.self, from: data).look.overrides.global.accent == .blau)

    // Once restyled, the look stays as set when an old field changes.
    var q = try ProfileStore.decode(try lookFixture("build249-profiles.json")).profiles[0]
    q.look.overrides.global.accent = .rot
    q.appearance.accent = .green
    q.appearance.heroEnabled = true
    #expect(q.look.overrides.global.accent == .rot)
    #expect(q.look.overrides.home.heroStyle == .aus)
    let back = try JSONDecoder().decode(Profile.self, from: try JSONEncoder().encode(q))
    #expect(back.look.overrides.global.accent == .rot)
    #expect(back.appearance.accent == .green)
}

@Test func profileWithFutureLookStillLoads() throws {
    let (stored, report) = try ProfileStore.decodeReporting(try lookFixture("build4-profiles-look.json"))
    #expect(stored.profiles.count == 2)
    let first = stored.profiles[0].look
    #expect(first.overrides.global.accent == .koralle)
    #expect(first.overrides.home.heroStyle == .aus)
    #expect(first.overrides.player.trackPanel == .seite)
    let second = stored.profiles[1].look           // version 2, preset "edel", unknown accent and fields
    #expect(second.preset == .appleTV)
    #expect(second.version == 2)
    // The old badge row (appearance.badges.style = logo) wins over the stored look on load (adoptOldLookRows).
    #expect(second.overrides.count == 1)
    #expect(second.overrides.detail.badgeStyle == .logos)
    #expect(Set(report.ignored) == ["profiles[1].look.preset", "profiles[1].look.overrides.global.accent"])
    // The old fields stay as they were and keep being written next to `look`.
    #expect(stored.profiles[0].appearance.accent == .orange)
    let enc = JSONEncoder()
    enc.outputFormatting = [.sortedKeys]
    let written = String(decoding: try enc.encode(stored.profiles[0]), as: UTF8.self)
    #expect(written.contains(#""appearance":{"#))
    #expect(written.contains(#""look":{"overrides":{"#))
    #expect(written.contains(#""trackPanelStyle":"topBar""#))
    // Written profiles read back equal.
    let again = try JSONDecoder().decode(Profile.self, from: try JSONEncoder().encode(stored.profiles[0]))
    #expect(again == stored.profiles[0])
    // A look that only mirrors the old fields is not written (Build 3 bytes stay the same) and reads back equal.
    let plain = try ProfileStore.decode(try lookFixture("build249-profiles.json")).profiles[0]
    let plainData = try JSONEncoder().encode(plain)
    #expect(!String(decoding: plainData, as: UTF8.self).contains(#""look""#))
    #expect(try JSONDecoder().decode(Profile.self, from: plainData).look == plain.look)
    #expect(!String(decoding: try JSONEncoder().encode(Profile.makeDefault()), as: UTF8.self).contains(#""look""#))
}

@Test func lookMetricsAreMonotonic() {
    let sizes = LookCardSize.allCases.map { LookMetrics.cardSize($0, shape: .poster).width }
    #expect(sizes == sizes.sorted() && Set(sizes).count == 3)
    let scales = LookFocusScale.allCases.map(LookMetrics.focusScale)
    #expect(scales == scales.sorted())
    let radii = LookCorners.allCases.map(LookMetrics.cornerRadius)
    #expect(radii == radii.sorted())
    let gaps = LookRowSpacing.allCases.map { LookMetrics.rowSpacing($0).row }
    #expect(gaps == gaps.sorted())
    let types = LookTypeScale.allCases.map(LookMetrics.typeScale)
    #expect(types == types.sorted())
    let off = LookMetrics.motion(.aus)
    #expect(off.focus == 0 && off.fade == 0 && off.backdrop == 0 && off.expand == 0)
    let lines = LookDescriptionLines.allCases.map(LookMetrics.descriptionLines)
    #expect(lines == lines.sorted())
}

@Test func lookMetricsMatchConfigurator() {
    #expect(LookMetrics.focusScale(.keine) == 1.0)
    #expect(LookMetrics.focusScale(.dezent) == 1.05)
    #expect(LookMetrics.focusScale(.kraeftig) == 1.12)

    #expect(LookCorners.allCases.map(LookMetrics.cornerRadius) == [0, 8, 14, 26])
    #expect(LookCorners.allCases.map(LookMetrics.rowRadius) == [4, 12, 18, 30])
    #expect(LookCorners.allCases.map(LookMetrics.panelRadius) == [8, 16, 22, 34])

    #expect(LookMetrics.rowSpacing(.eng) == LookSpacing(card: 16, row: 36))
    #expect(LookMetrics.rowSpacing(.normal) == LookSpacing(card: 24, row: 48))
    #expect(LookMetrics.rowSpacing(.luftig) == LookSpacing(card: 32, row: 64))

    #expect(LookMetrics.cardSize(.mittel, shape: .poster) == CGSize(width: 240, height: 360))
    #expect(LookMetrics.cardSize(.mittel, shape: .querformat) == CGSize(width: 440, height: 248))
    #expect(LookMetrics.cardSize(.klein, shape: .poster) == CGSize(width: 240 * 0.85, height: 360 * 0.85))
    #expect(LookMetrics.cardSize(.gross, shape: .querformat) == CGSize(width: 440 * 1.2, height: 248 * 1.2))
    // "mischung" is decided per row (continue watching landscape, the rest poster); the base size is the poster.
    #expect(LookMetrics.cardSize(.mittel, shape: .mischung) == CGSize(width: 240, height: 360))
    #expect(LookMetrics.expandedWidth(height: 360) == 640)

    #expect(LookMetrics.typeScale(.kompakt) == 0.9)
    #expect(LookMetrics.typeScale(.standard) == 1.0)
    #expect(LookMetrics.typeScale(.gross) == 1.12)

    #expect(LookMetrics.motion(.aus) == LookMotionTimes(focus: 0, fade: 0, backdrop: 0, expand: 0))
    #expect(LookMetrics.motion(.dezent) == LookMotionTimes(focus: 0.18, fade: 0.24, backdrop: 0.5, expand: 0.25))
    #expect(LookMetrics.motion(.standard) == LookMotionTimes(focus: 0.22, fade: 0.38, backdrop: 0.7, expand: 0.3))
    #expect(LookMetrics.rest == LookRestTimes(backdrop: 0.35, expand: 0.5, prefetch: 0.7))

    #expect(LookMetrics.focusShadow(.keiner) == nil)
    #expect(LookMetrics.focusShadow(.weich) == LookShadow(opacity: 0.45, radius: 20, y: 18))
    #expect(LookMetrics.focusShadow(.tief) == LookShadow(opacity: 0.75, radius: 35, y: 34))
    #expect(LookMetrics.focusBorderWidth == 4)
    #expect(LookMetrics.focusBorderGap == 4)

    #expect(LookMetrics.contentLeading(.seitenleiste) == 150)
    #expect(LookMetrics.contentLeading(.oben) == 80)
    #expect(LookDescriptionLines.allCases.map(LookMetrics.descriptionLines) == [2, 3, 5])
}

@Test func optionRawValuesMatchConfigurator() {
    // Appendix A of the plan: every option with every value the configurator offers.
    #expect(LookNavigation.allCases.map(\.rawValue) == ["seitenleiste", "oben"])
    #expect(LookSettingsLayout.allCases.map(\.rawValue) == ["spalten", "kacheln", "liste"])
    #expect(LookAccent.allCases.map(\.rawValue)
            == ["champagner", "weiss", "eisblau", "blau", "rot", "koralle", "salbei", "violett"])
    #expect(LookBackground.allCases.map(\.rawValue) == ["schwarz", "graphit", "tinte", "warm"])
    #expect(LookTypeScale.allCases.map(\.rawValue) == ["kompakt", "standard", "gross"])
    #expect(LookTypeCharacter.allCases.map(\.rawValue) == ["neutral", "editorial", "technisch"])
    #expect(LookMotion.allCases.map(\.rawValue) == ["aus", "dezent", "standard"])
    #expect(LookHeroStyle.allCases.map(\.rawValue) == ["vollbild", "banner", "karussell", "aus"])
    #expect(LookHeroInfo.allCases.map(\.rawValue) == ["minimal", "standard", "ausfuehrlich"])
    #expect(LookHeroTitle.allCases.map(\.rawValue) == ["logo", "text"])
    #expect(LookCardShape.allCases.map(\.rawValue) == ["poster", "querformat", "mischung"])
    #expect(LookCardSize.allCases.map(\.rawValue) == ["klein", "mittel", "gross"])
    #expect(LookCorners.allCases.map(\.rawValue) == ["eckig", "leicht", "weich", "rund"])
    #expect(LookRowSpacing.allCases.map(\.rawValue) == ["eng", "normal", "luftig"])
    #expect(LookRowTitle.allCases.map(\.rawValue) == ["dezent", "standard", "gross"])
    #expect(LookCardTitles.allCases.map(\.rawValue) == ["immer", "fokus", "aus"])
    #expect(LookFocusScale.allCases.map(\.rawValue) == ["keine", "dezent", "kraeftig"])
    #expect(LookFocusBorder.allCases.map(\.rawValue) == ["keiner", "weiss", "akzent"])
    #expect(LookFocusShadow.allCases.map(\.rawValue) == ["keiner", "weich", "tief"])
    #expect(LookDetailLayout.allCases.map(\.rawValue) == ["links", "zentriert", "kino"])
    #expect(LookDescriptionLines.allCases.map(\.rawValue) == [2, 3, 5])
    #expect(LookCast.allCases.map(\.rawValue) == ["kreise", "karten", "text", "aus"])
    #expect(LookBadgeStyle.allCases.map(\.rawValue) == ["umriss", "gefuellt", "text", "logos"])
    #expect(LookRatingStyle.allCases.map(\.rawValue) == ["symbole", "text", "kacheln"])
    #expect(LookSourceList.allCases.map(\.rawValue) == ["kompakt", "ausfuehrlich", "karten"])
    #expect(LookControlBar.allCases.map(\.rawValue) == ["minimal", "standard", "ausfuehrlich"])
    #expect(LookPlayerBadges.allCases.map(\.rawValue) == ["aus", "kompakt", "voll"])
    #expect(LookTimeDisplay.allCases.map(\.rawValue) == ["rest", "gesamt", "ende"])
    #expect(LookTrackPanel.allCases.map(\.rawValue) == ["seite", "unten", "mitte"])
    #expect(LookUpNext.allCases.map(\.rawValue) == ["karte", "leiste", "vollbild"])
    #expect(LookStillWatching.allCases.map(\.rawValue) == ["dialog", "karte"])
}
