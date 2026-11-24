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
            #expect(o.count == 1, "\(e.key)=\(c.raw)")
            #expect(LookOptionCatalog.rawValue(e.key, in: o.applied(to: base)) == c.raw)
        }
        // Clearing the override again leaves none.
        let set = try #require(LookOptionCatalog.overrides(LookOverrides(), setting: e.key, to: e.choices[0].raw))
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
    #expect(LookOptionCatalog.isEnabled("sourceList", in: v).reason == "kommt mit Build 5b")
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
    var o = LookOverrides()
    #expect(SettingsSummary.look(Look(overrides: o)) == "Mein Look · Apple TV")
    #expect(SettingsSummary.lookValue(Look(overrides: o)) == "Apple TV")
    o.global.accent = .rot; o.home.corners = .eckig; o.player.upNext = .leiste
    #expect(SettingsSummary.look(Look(overrides: o)) == "Mein Look · angepasst · 3")
    #expect(SettingsSummary.lookValue(Look(overrides: o)) == "angepasst · 3")
}
