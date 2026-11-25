import Foundation
import Testing
@testable import PlayerCore

// Task 4.5 (D-14, D-19, D-28): the catalog behind Einstellungen › Aussehen.

/// The configurator keys of `LookValues`, per area, read from its encoding.
private func lookValueKeys() throws -> [String: Set<String>] {
    let data = try JSONEncoder().encode(LookPreset.values(.appleTV))
    let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: [String: Any]])
    return obj.mapValues { Set($0.keys) }
}

@Test func catalogHasAllConfiguratorOptions() throws {
    let all = LookOptionCatalog.all
    #expect(all.count == 35)
    #expect(Set(all.map(\.id)).count == 35)
    var byArea: [String: Set<String>] = [:]
    for e in all { byArea[e.area.rawValue, default: []].insert(e.key) }
    #expect(byArea == (try lookValueKeys()))
    // Appendix A order: first and last rows, and German texts verbatim.
    #expect(all.first?.key == "navigation")
    #expect(all.last?.key == "stillWatching")
    let accent = try #require(LookOptionCatalog.entry("accent"))
    #expect(accent.label == "Akzentfarbe")
    #expect(accent.group == "Farbe")
    #expect(accent.help == "Markiert Gewähltes und den Hauptknopf. Der Fokus selbst bleibt weiß.")
    #expect(accent.choices.first?.label == "Champagner")
    #expect(accent.availableFrom == .b4)
    #expect(LookOptionCatalog.entry("layout")?.availableFrom == .b5b)
    #expect(LookOptionCatalog.entry("upNext")?.availableFrom == .b5c)
    #expect(LookOptionCatalog.entry("stillWatching")?.label == "„Noch da?“")
}

@Test func catalogChoicesMatchEnums() throws {
    let base = LookPreset.values(.appleTV)
    for e in LookOptionCatalog.all {
        #expect(!e.choices.isEmpty)
        // The Mein Look value is one of the choices.
        let current = try #require(LookOptionCatalog.rawValue(e.key, in: base))
        #expect(e.choices.contains { $0.raw == current }, "\(e.key)")
        for c in e.choices {
            // Every choice decodes as a valid override of exactly this key.
            let o = try #require(LookOptionCatalog.overrides(LookOverrides(), setting: e.key, to: c.raw), "\(e.key)")
            // The Mein Look value is no deviation: picking it drops the override (fix round 1, I1).
            #expect(o.count == (c.raw == current ? 0 : 1), "\(e.key)=\(c.raw)")
            #expect(LookOptionCatalog.rawValue(e.key, in: o.applied(to: base)) == c.raw)
        }
        // Clearing the override again leaves none.
        let other = try #require(e.choices.first { $0.raw != current })
        let set = try #require(LookOptionCatalog.overrides(LookOverrides(), setting: e.key, to: other.raw))
        #expect(set.count == 1)
        #expect(LookOptionCatalog.overrides(set, setting: e.key, to: nil)?.isEmpty == true)
    }
}

@Test func glowDisablesCardShapeOptions() {
    var v = LookPreset.values(.appleTV)
    v.home.focusGlow = true
    for key in ["corners", "focusScale", "focusBorder", "focusShadow"] {
        let r = LookOptionCatalog.isEnabled(key, in: v, build: .b5a)
        #expect(!r.enabled, "\(key)")
        #expect(r.reason == "Bei Glanz bestimmt tvOS Form, Größe und Schatten der Karte.")
    }
    #expect(LookOptionCatalog.isEnabled("focusGlow", in: v, build: .b5a).enabled)
    v.home.focusGlow = false
    #expect(LookOptionCatalog.isEnabled("corners", in: v, build: .b5a).enabled)
    // In Build 4 the later options are visible but off.
    let later = LookOptionCatalog.isEnabled("corners", in: v)
    #expect(!later.enabled && later.reason == "kommt mit Build 5a")
    #expect(LookOptionCatalog.isEnabled("accent", in: v) == (true, nil))
    #expect(LookOptionCatalog.isEnabled("sourceList", in: v, implemented: []).reason == "kommt mit Build 5b")
    // System reduce motion: still selectable, with a note.
    let m = LookOptionCatalog.isEnabled("motion", in: v, reduceMotion: true)
    #expect(m.enabled && m.reason == "Das System reduziert Bewegung; diese Einstellung wirkt erst, wenn das aus ist.")
    #expect(LookOptionCatalog.isEnabled("expandPosters", in: v, reduceMotion: true).reason == m.reason)
}

@Test func noFocusSignForcesWhiteBorder() {
    var v = LookPreset.values(.appleTV)
    v.home.focusScale = .keine; v.home.focusBorder = .keiner; v.home.focusShadow = .keiner; v.home.focusGlow = false
    #expect(LookOptionCatalog.groupHint("Fokus-Effekt", in: v) == "Ohne Fokus-Zeichen setzt die App einen weißen Rahmen.")
    #expect(LookOptionCatalog.effectiveFocusBorder(v) == .weiss)
    v.home.focusShadow = .weich
    #expect(LookOptionCatalog.groupHint("Fokus-Effekt", in: v) == nil)
    #expect(LookOptionCatalog.effectiveFocusBorder(v) == .keiner)
    #expect(LookOptionCatalog.groupHint("Farbe", in: v) == nil)
}

@Test func summaryCountsOverrides() {
    // Task 4.5-base: the count is against the baseline (old defaults), so start from its overrides.
    var o = LookOverrides.difference(LookPreset.baseline, from: LookPreset.values(.appleTV))
    #expect(SettingsSummary.look(Look(overrides: o)) == "Mein Look · Standard")
    #expect(SettingsSummary.lookValue(Look(overrides: o)) == "Standard")
    o.global.accent = .rot; o.home.corners = .eckig; o.player.upNext = .leiste
    #expect(SettingsSummary.look(Look(overrides: o)) == "Mein Look · angepasst · 3")
    #expect(SettingsSummary.lookValue(Look(overrides: o)) == "angepasst · 3")
}

// Fix round 1 (I2): writes go through the profile so the theme shows them; summary and rows read `themeLook`.

@Test func setLookShowsInThemeAndOldFields() {
    var p = Profile(name: "T")
    p.setLook("accent", to: "rot")
    #expect(p.themeLook.global.accent == .rot)
    #expect(p.appearance.accent == .pink)
    p.setLook("cardSize", to: "klein")
    #expect(p.themeLook.home.cardSize == .klein)
    #expect(p.appearance.cardSize == .small)
    p.setLook("corners", to: "eckig")
    #expect(p.themeLook.home.corners == .eckig)
    #expect(SettingsSummary.lookValue(p) == "angepasst · 3")
    #expect(p.lookRawValue("accent") == "rot")
    #expect(p.isLookOverridden("accent"))
    // Back to the baseline value (old default blue): no deviation left for that key.
    p.setLook("accent", to: "blau")
    #expect(p.themeLook.global.accent == .blau)
    #expect(!p.isLookOverridden("accent"))
    p.setLook("corners", to: nil)
    #expect(SettingsSummary.lookValue(p) == "angepasst · 1")
}

@Test func summaryCountsOldFieldChanges() {
    var p = Profile(name: "T")
    #expect(SettingsSummary.lookValue(p) == "Standard")
    p.appearance.accent = .green
    #expect(p.themeLook.global.accent == .salbei)
    #expect(SettingsSummary.lookValue(p) == "angepasst · 1")
    #expect(SettingsSummary.look(p) == "Mein Look · angepasst · 1")
    #expect(p.lookRawValue("accent") == "salbei")
}

@Test func resetLookAfterOldFieldChanges() {
    var p = Profile(name: "T")
    p.appearance.accent = .green
    p.appearance.heroEnabled = false
    p.player.trackPanelStyle = .menu
    p.setLook("background", to: "tinte")
    p.resetLook()
    #expect(p.themeLook == LookPreset.baseline)   // Task 4.5-base: back to the old defaults
    #expect(SettingsSummary.lookValue(p) == "Standard")
    #expect(SettingsSummary.look(p) == "Mein Look · Standard")
    #expect(p.appearance.accent == .blue)
    #expect(p.appearance.heroEnabled)
}

// Task 4.5 review M2: one encode per settings body instead of two per row.

@Test func rawValuesMatchSingleKeyReads() throws {
    var v = LookPreset.values(.appleTV)
    v.global.accent = .rot; v.home.focusGlow = true; v.detail.descriptionLines = .five
    for values in [v, LookPreset.baseline, LookPreset.values(.appleTV)] {
        let all = LookOptionCatalog.rawValues(values)
        #expect(all.count == LookOptionCatalog.all.count)
        for e in LookOptionCatalog.all {
            #expect(all[e.key] == LookOptionCatalog.rawValue(e.key, in: values), "\(e.key)")
        }
    }
    #expect(LookOptionCatalog.baselineRawValues == LookOptionCatalog.rawValues(LookPreset.baseline))
}

@Test func profileLookRowsMatchPerKeyReads() {
    var p = Profile(name: "T")
    p.setLook("accent", to: "rot")
    p.setLook("corners", to: "eckig")
    p.appearance.expandPosters.toggle()
    let rows = p.lookRows
    #expect(rows.raw.count == LookOptionCatalog.all.count)
    for e in LookOptionCatalog.all {
        #expect(rows.raw[e.key] == p.lookRawValue(e.key), "\(e.key)")
        #expect(rows.isOverridden(e.key) == p.isLookOverridden(e.key), "\(e.key)")
    }
    #expect(rows.raw["accent"] == "rot")
    #expect(rows.overriddenCount == 3)
    #expect(Profile(name: "U").lookRows.overriddenCount == 0)
}

// Task 4.5 review M5: a later-build row whose concept still has an active old row points to it.

@Test func laterBuildRowsPointToTheActiveOldRow() {
    let v = LookPreset.values(.appleTV)
    // Task 5.3 draws badgeStyle and layout, so the stand-in note shows only without that code (`implemented: []`).
    #expect(LookOptionCatalog.isEnabled("badgeStyle", in: v, implemented: []).reason
        == "kommt mit Build 5b · bis dahin: „Plaketten-Stil“ unten")
    #expect(LookOptionCatalog.isEnabled("badgeStyle", in: v) == (true, nil))
    #expect(LookOptionCatalog.isEnabled("heroStyle", in: v).reason
        == "kommt mit Build 5a · bis dahin: „Titelbild oben“ unter Startseite")
    #expect(LookOptionCatalog.isEnabled("heroStyle", in: v, build: .b5a) == (true, nil))
    #expect(LookOptionCatalog.isEnabled("layout", in: v, implemented: []).reason == "kommt mit Build 5b")
}
