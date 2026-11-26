import Foundation

/// Task 4.5: the four areas of the look, named like the keys of `LookValues` / a configurator export.
public enum LookArea: String, Sendable, Hashable, CaseIterable {
    case global, home, detail, player
}

/// Task 4.5: the build from which an option takes effect (plan appendix A, column "ab Build").
public enum LookBuild: Int, Sendable, Hashable, Comparable, CaseIterable {
    case b4, b5a, b5b, b5c

    /// The build this code ships in.
    public static let current: LookBuild = .b4

    public var title: String {
        switch self {
        case .b4: "4"
        case .b5a: "5a"
        case .b5b: "5b"
        case .b5c: "5c"
        }
    }

    public static func < (a: LookBuild, b: LookBuild) -> Bool { a.rawValue < b.rawValue }
}

/// One value of an option: the configurator raw value (`"true"`, `"2"` for bools and numbers) and its German name.
public struct LookChoice: Sendable, Hashable {
    public var raw: String
    public var label: String

    public init(raw: String, label: String) { self.raw = raw; self.label = label }
}

/// One row of Einstellungen › Aussehen. `label`, `help` and the value names are the German texts of appendix A.
public struct LookOptionEntry: Sendable, Hashable, Identifiable {
    public var area: LookArea
    public var group: String
    public var key: String
    public var label: String
    public var help: String
    public var choices: [LookChoice]
    public var availableFrom: LookBuild

    /// `area.key`, unique across the catalog.
    public var id: String { area.rawValue + "." + key }

    public func choiceLabel(_ raw: String) -> String? { choices.first { $0.raw == raw }?.label }
}

/// Task 4.5 (D-14, D-19, D-28): all 35 configurator options in the order of plan appendix A, plus the rules that
/// switch rows off. Pure data, so the settings page only renders it.
public enum LookOptionCatalog {
    public static let all: [LookOptionEntry] = makeAll()

    /// Task 5.3 (ruling 24.11.): the two detail rows outside the configurator (`Profile.detailExtras`), in their
    /// own group after „Quellenliste“. Not part of `all` (the 35 configurator options, export and import).
    public static let extras: [LookOptionEntry] = [
        LookOptionEntry(area: .detail, group: "Folgen und Titel", key: "episodes", label: "Folgen",
                        help: "Reihe zeigt die Folgen nebeneinander mit Bild und beginnt bei der ersten ungesehenen. "
                            + "Liste zeigt sie untereinander mit Text.",
                        choices: [LookChoice(raw: "reihe", label: "Reihe"), LookChoice(raw: "liste", label: "Liste")],
                        availableFrom: .b5b),
        LookOptionEntry(area: .detail, group: "Folgen und Titel", key: "titleArt", label: "Titel oben",
                        help: "Logo setzt das Titel-Logo an die Stelle des Posters; ohne Logo bleibt das Poster. "
                            + "Poster zeigt immer das Poster.",
                        choices: [LookChoice(raw: "logo", label: "Logo"), LookChoice(raw: "poster", label: "Poster")],
                        availableFrom: .b5b),
    ]

    /// All rows of Einstellungen › Aussehen: the 35 configurator options plus `extras`.
    public static let rows: [LookOptionEntry] = all + extras

    /// Whether `key` is one of the profile-owned extras (not in `LookValues`).
    public static func isExtra(_ key: String) -> Bool { extras.contains { $0.key == key } }

    /// Task 5.3: options of a later build that this code already draws; their rows are active although
    /// `LookBuild.current` stays `.b4`.
    /// Task 5.1: the card and row options of 5a (cardSize and expandPosters are Build 4 options); Task 5.2: the hero
    /// options of 5a; Task 5.4: the five player options of 5c (trackPanel is a Build 4 option already); Task 5.6:
    /// clock and settings layout (navigation is a Build 4 option already). `availableFrom` keeps the appendix value.
    /// Integration build 5: the one set of drawn later options, the default of `isEnabled(implemented:)`.
    public static let implemented: Set<String> = [
        // 5.3 detail
        "layout", "descriptionLines", "cast", "badgeStyle", "ratingStyle", "sourceList", "episodes", "titleArt",
        // 5.1 cards and rows
        "cardShape", "corners", "rowSpacing", "rowTitle", "cardTitles", "focusScale", "focusBorder", "focusShadow",
        "focusGlow",
        // 5.2 hero
        "heroStyle", "heroInfo", "heroTitle", "backdropFollowsFocus",
        // 5.4 player
        "controlBar", "badges", "timeDisplay", "upNext", "stillWatching",
        // 5.6 clock and settings
        "clock", "settingsLayout",
    ]

    public static func entry(_ key: String) -> LookOptionEntry? { rows.first { $0.key == key } }

    // MARK: Dependencies

    static let glowReason = "Bei Glanz bestimmt tvOS Form, Größe und Schatten der Karte."
    static let reduceMotionReason = "Das System reduziert Bewegung; diese Einstellung wirkt erst, wenn das aus ist."
    static let noFocusSignHint = "Ohne Fokus-Zeichen setzt die App einen weißen Rahmen."
    static let glowControlledKeys: Set<String> = ["corners", "focusScale", "focusBorder", "focusShadow"]
    // Review M5 pointed later-build options to their old stand-in rows („Plaketten-Stil“, „Titelbild oben“); both
    // rows are gone since integration build 5 (user decision 26.11.), so the note is plain „kommt mit Build …“.

    /// Whether the row `key` can be changed in `build`, and the note shown under it. An option of a later build is
    /// off with "kommt mit Build …"; with glow on, tvOS draws the card (`.buttonStyle(.card)`), so shape, scale,
    /// border and shadow are off. With system "reduce motion" the motion rows stay selectable but carry a note.
    /// Task 5.3: `implemented` lists the later-build options already drawn (default: all of them).
    public static func isEnabled(_ key: String, in values: LookValues, build: LookBuild = .current,
                                 reduceMotion: Bool = false,
                                 implemented: Set<String> = implemented) -> (enabled: Bool, reason: String?) {
        guard let e = entry(key) else { return (false, nil) }
        if e.availableFrom > build, !implemented.contains(key) {
            let later = "kommt mit Build \(e.availableFrom.title)"
            return (false, later)
        }
        if glowControlledKeys.contains(key), values.home.focusGlow { return (false, glowReason) }
        if reduceMotion, key == "motion" || key == "expandPosters" { return (true, reduceMotionReason) }
        return (true, nil)
    }

    /// True when the look shows no focus sign at all (no scale, border, shadow or glow).
    public static func hasNoFocusSign(_ v: LookValues) -> Bool {
        v.home.focusScale == .keine && v.home.focusBorder == .keiner && v.home.focusShadow == .keiner
            && !v.home.focusGlow
    }

    /// The border the theme draws: white when the look would otherwise show no focus sign.
    public static func effectiveFocusBorder(_ v: LookValues) -> LookFocusBorder {
        hasNoFocusSign(v) ? .weiss : v.home.focusBorder
    }

    /// The note under a group header, if any.
    public static func groupHint(_ group: String, in values: LookValues) -> String? {
        group == "Fokus-Effekt" && hasNoFocusSign(values) ? noFocusSignHint : nil
    }

    // MARK: Generic access (configurator key names)

    /// The raw value of `key` in `values` (`"true"` / `"false"` for bools, `"2"` for numbers).
    public static func rawValue(_ key: String, in values: LookValues) -> String? {
        guard let e = entry(key),
              let data = try? JSONEncoder().encode(values),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]],
              let value = obj[e.area.rawValue]?[key] else { return nil }
        return rawString(value, isBool: e.choices.map(\.raw) == ["true", "false"])
    }

    /// Review M2: the raw values of all catalog keys in `values` from one encode, keyed by `key` (the same values
    /// as `rawValue(_:in:)` per key). The settings page reads its 35 rows from this.
    public static func rawValues(_ values: LookValues) -> [String: String] {
        guard let data = try? JSONEncoder().encode(values),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else { return [:] }
        var out: [String: String] = [:]
        for e in all {
            if let v = obj[e.area.rawValue]?[e.key], let r = rawString(v, isBool: e.choices.map(\.raw) == ["true", "false"]) {
                out[e.key] = r
            }
        }
        return out
    }

    /// Raw values of the baseline (`LookPreset.baseline`), computed once.
    public static let baselineRawValues: [String: String] = rawValues(LookPreset.baseline)

    /// `overrides` with `key` set to `raw`, or removed for `nil` or the value of `preset`. This builds the stored
    /// shape only (overrides relative to the preset); it does not say what counts as a change. On the keys where the
    /// baseline differs from the preset (navigation, accent, cardSize, expandPosters, badgeStyle, trackPanel) a removed
    /// override still counts and shows the accent dot. "Back to the default" for a row is
    /// `Profile.setLook(key, to: nil)`. `nil` when the key or the raw value is unknown; the result is read back
    /// through the lenient decoder, so only valid values land.
    public static func overrides(_ overrides: LookOverrides, setting key: String, to raw: String?,
                                 preset: LookPresetID = .appleTV) -> LookOverrides? {
        guard let e = entry(key) else { return nil }
        if let r = raw, !e.choices.contains(where: { $0.raw == r }) { return nil }
        let base = LookPreset.values(preset)
        let raw = raw == rawValue(key, in: base) ? nil : raw
        guard let data = try? JSONEncoder().encode(overrides),
              var obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var area = obj[e.area.rawValue] as? [String: Any] ?? [:]
        if let raw { area[key] = jsonValue(raw) } else { area.removeValue(forKey: key) }
        obj[e.area.rawValue] = area
        guard let out = try? JSONSerialization.data(withJSONObject: obj),
              let decoded = try? JSONDecoder().decode(LookOverrides.self, from: out) else { return nil }
        if let raw, rawValue(key, in: decoded.applied(to: base)) != raw { return nil }
        return decoded
    }

    /// Whether `key` differs from the baseline (`LookPreset.baseline`, the old defaults; the row carries the
    /// accent dot and offers "Auf Standard zurücksetzen"). `overrides` are stored ones, relative to `preset`.
    /// Task 4.5-base: an override that only restates the baseline (e.g. navigation seitenleiste) is no change.
    /// It reads the stored overrides only, not the old fields that `Profile.themeLook` lets win. For a profile's
    /// rows use `Profile.isLookOverridden(_:)`.
    public static func isOverridden(_ key: String, in overrides: LookOverrides,
                                    preset: LookPresetID = .appleTV) -> Bool {
        guard let shown = rawValue(key, in: overrides.applied(to: LookPreset.values(preset))) else { return false }
        return shown != baselineRawValues[key]
    }

    /// JSONSerialization reads bools and numbers both as NSNumber; the entry says which one it is.
    private static func rawString(_ value: Any, isBool: Bool) -> String? {
        if let n = value as? NSNumber { return isBool ? (n.boolValue ? "true" : "false") : n.stringValue }
        return value as? String
    }

    private static func jsonValue(_ raw: String) -> Any {
        if raw == "true" { return true }
        if raw == "false" { return false }
        if let n = Int(raw) { return n }
        return raw
    }

    // MARK: Appendix A

    private static func makeAll() -> [LookOptionEntry] {
        func e(_ area: LookArea, _ group: String, _ key: String, _ label: String, _ choices: [(String, String)],
               _ help: String, _ build: LookBuild) -> LookOptionEntry {
            LookOptionEntry(area: area, group: group, key: key, label: label, help: help,
                            choices: choices.map { LookChoice(raw: $0.0, label: $0.1) }, availableFrom: build)
        }
        let onOff = [("true", "An"), ("false", "Aus")]
        return [
            // global
            e(.global, "Navigation", "navigation", "Hauptnavigation",
              [("seitenleiste", "Seitenleiste"), ("oben", "Obere Leiste")],
              "Seitenleiste links oder Leiste oben.", .b4),
            e(.global, "Navigation", "clock", "Uhr", onOff, "Zeigt die Uhrzeit oben rechts.", .b5a),
            e(.global, "Navigation", "settingsLayout", "Einstellungs-Layout",
              [("spalten", "Zwei Spalten"), ("kacheln", "Kacheln"), ("liste", "Liste")],
              "Zweispaltig mit Kategorien links, große Kacheln oder eine einzige Liste.", .b5a),
            e(.global, "Farbe", "accent", "Akzentfarbe",
              [("champagner", "Champagner"), ("weiss", "Weiß"), ("eisblau", "Eisblau"), ("blau", "Blau"),
               ("rot", "Rot"), ("koralle", "Koralle"), ("salbei", "Salbei"), ("violett", "Violett")],
              "Markiert Gewähltes und den Hauptknopf. Der Fokus selbst bleibt weiß.", .b4),
            e(.global, "Farbe", "background", "Hintergrundton",
              [("schwarz", "Schwarz (OLED)"), ("graphit", "Graphit"), ("tinte", "Tinte (bläulich)"),
               ("warm", "Warm (bräunlich)")],
              "Schwarz nutzt OLED voll aus. Die getönten Varianten wirken weicher.", .b4),
            e(.global, "Schrift und Bewegung", "typeScale", "Schriftgröße",
              [("kompakt", "Kompakt"), ("standard", "Standard"), ("gross", "Groß")],
              "Skaliert alle Texte gemeinsam.", .b4),
            e(.global, "Schrift und Bewegung", "typeCharacter", "Schriftcharakter",
              [("neutral", "Neutral"), ("editorial", "Editorial"), ("technisch", "Technisch")],
              "Neutral entspricht tvOS. Editorial setzt große Titel leichter und enger. Technisch setzt Metadaten "
                + "kräftiger und weiter.", .b4),
            e(.global, "Schrift und Bewegung", "motion", "Bewegung",
              [("aus", "Aus"), ("dezent", "Dezent"), ("standard", "Standard")],
              "Dauer und Stärke der Übergänge. Aus schaltet Überblendungen ab.", .b4),
            // home
            e(.home, "Hero", "heroStyle", "Hero-Stil",
              [("vollbild", "Vollbild"), ("banner", "Banner"), ("karussell", "Karussell"), ("aus", "Aus")],
              "Vollbild füllt den ganzen Bildschirm hinter den Reihen. Banner ist eine eigene Fläche über den Reihen. "
                + "Karussell zeigt den Nachbartitel angeschnitten.", .b5a),
            e(.home, "Hero", "heroInfo", "Info-Ebene",
              [("minimal", "Minimal"), ("standard", "Standard"), ("ausfuehrlich", "Ausführlich")],
              "Wie viel Text über dem Hero-Bild steht.", .b5a),
            e(.home, "Hero", "heroTitle", "Logo oder Titel", [("logo", "Logo"), ("text", "Titel als Text")],
              "Logo nimmt das Titel-Logo aus den Metadaten, wenn es eines gibt. Titel setzt den Namen immer als Text.",
              .b5a),
            e(.home, "Hero", "backdropFollowsFocus", "Hintergrund nach Fokus", onOff,
              "Der Hintergrund wechselt auf den Titel, auf dem der Fokus kurz ruht.", .b5a),
            e(.home, "Karten und Reihen", "cardShape", "Kartenform",
              [("poster", "Poster"), ("querformat", "Querformat"), ("mischung", "Mischung")],
              "Poster ist Hochformat, Querformat zeigt Szenenbilder. Mischung nutzt Querformat für Weiterschauen und "
                + "Poster für den Rest.", .b5a),
            e(.home, "Karten und Reihen", "cardSize", "Kartengröße",
              [("klein", "Klein"), ("mittel", "Mittel"), ("gross", "Groß")],
              "Größere Karten wirken ruhiger, zeigen aber weniger Titel pro Reihe.", .b4),
            e(.home, "Karten und Reihen", "corners", "Ecken",
              [("eckig", "Eckig"), ("leicht", "Leicht"), ("weich", "Weich"), ("rund", "Rund")],
              "Radius der Karten und Flächen.", .b5a),
            e(.home, "Karten und Reihen", "rowSpacing", "Abstände",
              [("eng", "Eng"), ("normal", "Normal"), ("luftig", "Luftig")],
              "Abstand zwischen Karten und zwischen Reihen.", .b5a),
            e(.home, "Karten und Reihen", "rowTitle", "Reihentitel",
              [("dezent", "Dezent"), ("standard", "Standard"), ("gross", "Groß")],
              "Dezent ist klein und zurückgenommen, Groß setzt kräftige Überschriften.", .b5a),
            e(.home, "Karten und Reihen", "cardTitles", "Titel unter Karten",
              [("immer", "Immer"), ("fokus", "Nur bei Fokus"), ("aus", "Aus")],
              "Zeigt den Namen unter der Karte: immer, nur bei Fokus oder nie.", .b5a),
            e(.home, "Karten und Reihen", "expandPosters", "Poster aufklappen", onOff,
              "Das fokussierte Poster wächst nach kurzer Ruhe zum Querformat mit Szenenbild.", .b4),
            e(.home, "Fokus-Effekt", "focusScale", "Skalierung",
              [("keine", "Keine"), ("dezent", "Dezent"), ("kraeftig", "Kräftig")],
              "Wie stark die fokussierte Karte wächst.", .b5a),
            e(.home, "Fokus-Effekt", "focusBorder", "Rahmen",
              [("keiner", "Keiner"), ("weiss", "Weiß"), ("akzent", "Akzentfarbe")],
              "Ein Rahmen um die fokussierte Karte.", .b5a),
            e(.home, "Fokus-Effekt", "focusShadow", "Schatten",
              [("keiner", "Keiner"), ("weich", "Weich"), ("tief", "Tief")],
              "Schatten unter der fokussierten Karte.", .b5a),
            e(.home, "Fokus-Effekt", "focusGlow", "Glanz", onOff,
              "Ein Lichtreflex auf der fokussierten Karte, wie bei den Postern der Apple-TV-App.", .b5a),
            // detail
            e(.detail, "Aufbau", "layout", "Layout",
              [("links", "Links"), ("zentriert", "Zentriert"), ("kino", "Kino-Vollbild")],
              "Links stellt Text und Knöpfe an den linken Rand. Zentriert setzt alles mittig. Kino-Vollbild zeigt fast "
                + "nur das Bild und schiebt den Rest nach unten.", .b5b),
            e(.detail, "Aufbau", "descriptionLines", "Beschreibungslänge",
              [("2", "2 Zeilen"), ("3", "3 Zeilen"), ("5", "5 Zeilen")],
              "Wie viele Zeilen der Beschreibung sofort sichtbar sind.", .b5b),
            e(.detail, "Aufbau", "cast", "Besetzung",
              [("kreise", "Kreise"), ("karten", "Karten"), ("text", "Textzeile"), ("aus", "Aus")],
              "Runde Porträts, Karten mit Rolle, eine Textzeile oder gar nicht.", .b5b),
            e(.detail, "Plaketten und Bewertungen", "badgeStyle", "Plakettenstil",
              [("umriss", "Umriss"), ("gefuellt", "Gefüllt"), ("text", "Nur Text"), ("logos", "Logos")],
              "Umriss ist fein, Gefüllt ist gut lesbar, Text kommt ohne Fläche aus. Logos zeichnet die Schriftzüge "
                + "nach.", .b5b),
            e(.detail, "Plaketten und Bewertungen", "ratingStyle", "Bewertungen",
              [("symbole", "Symbol + Zahl"), ("text", "Textzeile"), ("kacheln", "Kacheln")],
              "Symbole mit Zahl, reine Textzeile oder kleine Kacheln mit Quelle.", .b5b),
            e(.detail, "Quellenliste", "sourceList", "Darstellung",
              [("kompakt", "Kompakt"), ("ausfuehrlich", "Ausführlich"), ("karten", "Karten")],
              "Kompakt zeigt eine Zeile pro Quelle. Ausführlich zeigt den Text des Addons. Karten trennt Plaketten und "
                + "Text klar.", .b5b),
            // player
            e(.player, "Steuerleiste", "controlBar", "Umfang",
              [("minimal", "Minimal"), ("standard", "Standard"), ("ausfuehrlich", "Ausführlich")],
              "Minimal zeigt nur Zeitleiste und Zeit. Standard ergänzt Titel und Knöpfe. Ausführlich zeigt zusätzlich "
                + "Kapitelmarken und Technik.", .b5c),
            e(.player, "Steuerleiste", "badges", "Plaketten",
              [("aus", "Aus"), ("kompakt", "Kompakt"), ("voll", "Alle")],
              "Technik-Plaketten in der Steuerleiste.", .b5c),
            e(.player, "Steuerleiste", "timeDisplay", "Zeitanzeige",
              [("rest", "Restzeit"), ("gesamt", "Position / Dauer"), ("ende", "Endet um")],
              "Restzeit, Position und Gesamtdauer oder die Uhrzeit, zu der der Film endet.", .b5c),
            e(.player, "Panels und Hinweise", "trackPanel", "Ton- und Untertitel-Panel",
              [("seite", "Seite"), ("unten", "Unten"), ("mitte", "Mitte")],
              "Seite schiebt ein Panel von rechts herein. Unten legt es über die Steuerleiste. Mitte zeigt eine "
                + "schwebende Karte.", .b4),
            e(.player, "Panels und Hinweise", "upNext", "Nächste Folge",
              [("karte", "Karte"), ("leiste", "Leiste"), ("vollbild", "Vollbild")],
              "Karte unten rechts, schmale Leiste am unteren Rand oder Vollbild mit Vorschaubild.", .b5c),
            e(.player, "Panels und Hinweise", "stillWatching", "„Noch da?“",
              [("dialog", "Dialog"), ("karte", "Karte")],
              "Dialog in der Mitte, der das Bild abdunkelt, oder eine ruhige Karte unten.", .b5c),
        ]
    }
}

extension SettingsSummary {
    /// Task 4.5: value of the "Mein Look" row: „Standard“ or „angepasst · 3“ (user decision 25.11.: „Standard“,
    /// not „Apple TV“, because count 0 means the old defaults, not the Apple TV preset). Task 4.5-base:
    /// counts the keys that differ from the baseline (`LookPreset.baseline`, the old defaults), not the stored
    /// overrides, so an untouched profile shows „Standard“ and an imported Apple TV export counts its differences.
    public static func lookValue(_ look: Look) -> String { lookValue(count: LookPreset.baselineDeviationCount(look)) }

    static func lookValue(count n: Int) -> String { n == 0 ? "Standard" : "angepasst · \(n)" }

    /// Task 4.5: „Mein Look · Standard“ / „Mein Look · angepasst · 3“.
    public static func look(_ look: Look) -> String {
        DesignText.metaLine([look.preset.title, lookValue(look)])
    }
    /// Fix round 1 (I2): the row value from what the theme shows (`themeLook`), so a change in the old settings
    /// counts too. Integration build 5: plus the detail extras that differ (`episodes`, `titleArt`, in
    /// `Profile.detailExtras`), so n matches the rows' accent dots.
    public static func lookValue(_ p: Profile) -> String { lookValue(count: lookDeviationCount(p)) }

    public static func look(_ p: Profile) -> String { DesignText.metaLine([p.look.preset.title, lookValue(p)]) }

    static func lookDeviationCount(_ p: Profile) -> Int {
        let extras = LookOptionCatalog.extras.filter { p.isLookOverridden($0.key) }.count
        return LookPreset.baselineDeviationCount(p.shownLook) + extras
    }
}

extension Profile {
    /// Fix round 1 (I2): the look the theme shows, as preset plus deviations in the stored shape (relative to the
    /// preset). The count compares it with the baseline (`SettingsSummary.lookValue(Look)`).
    public var shownLook: Look {
        Look(preset: look.preset, overrides: LookOverrides.difference(themeLook, from: LookPreset.values(look.preset)))
    }

    /// The value a row shows (raw configurator value of `themeLook`).
    public func lookRawValue(_ key: String) -> String? {
        if LookOptionCatalog.isExtra(key) { return detailExtras.rawValue(key) }
        return LookOptionCatalog.rawValue(key, in: themeLook)
    }

    /// Whether the row differs from the baseline (`LookPreset.baseline`, the old defaults; accent dot,
    /// "Auf Standard zurücksetzen").
    public func isLookOverridden(_ key: String) -> Bool {
        if LookOptionCatalog.isExtra(key) { return detailExtras.rawValue(key) != LookDetailExtras().rawValue(key) }
        return LookOptionCatalog.rawValue(key, in: themeLook) != LookOptionCatalog.baselineRawValues[key]
    }

    /// Review M2: every row's value and accent dot from one `themeLook` and one encode.
    public var lookRows: LookRowValues { LookRowValues(themeLook, extras: detailExtras) }

    /// Sets one option starting from what the theme shows (`nil` = back to the baseline value, the old default),
    /// and writes the old fields it maps to through `applyImportedLook` (old fields first, look last), so
    /// `themeLook` shows the new value. The stored overrides stay relative to the preset. Unknown key or value:
    /// nothing changes.
    public mutating func setLook(_ key: String, to raw: String?) {
        if LookOptionCatalog.isExtra(key) {
            var x = detailExtras
            if x.set(key, to: raw) { detailExtras = x }
            return
        }
        guard let target = raw ?? LookOptionCatalog.rawValue(key, in: LookPreset.baseline),
              let o = LookOptionCatalog.overrides(shownLook.overrides, setting: key, to: target, preset: look.preset)
        else { return }
        applyImportedLook(Look(preset: look.preset, overrides: o))
    }

    /// "Alles auf Standard zurücksetzen" (Task 4.5-base): back to the baseline, the old defaults. The old fields
    /// return to their `Appearance()` / `PlayerComfortSettings()` values, and the look is again the one they
    /// migrate to (so it is not written and the summary says „Standard“).
    public mutating func resetLook() {
        let base = LookOverrides.difference(LookPreset.baseline, from: LookPreset.values(look.preset))
        applyImportedLook(Look(preset: look.preset, overrides: base))
        if detailExtras != LookDetailExtras() { detailExtras = LookDetailExtras() }
    }
}

/// Review M2 (Task 4.5): the values of all rows of Einstellungen › Aussehen at once, so a settings body encodes the
/// look once instead of twice per row.
public struct LookRowValues: Sendable, Equatable {
    /// Raw value per row key (`LookOptionCatalog.rawValue`, plus the detail extras from `LookDetailExtras`).
    public let raw: [String: String]

    /// Integration build 5 (b5b review W5): the rows include `LookOptionCatalog.extras` (`episodes`, `titleArt`),
    /// which live in `Profile.detailExtras`, not in `LookValues`.
    public init(_ values: LookValues, extras: LookDetailExtras = LookDetailExtras()) {
        var r = LookOptionCatalog.rawValues(values)
        for e in LookOptionCatalog.extras { r[e.key] = extras.rawValue(e.key) }
        raw = r
    }

    /// Whether `key` differs from the baseline (accent dot), as `Profile.isLookOverridden`; an extra against the
    /// `LookDetailExtras()` defaults.
    public func isOverridden(_ key: String) -> Bool {
        if LookOptionCatalog.isExtra(key) { return raw[key] != LookRowValues.extrasBaseline[key] }
        return raw[key] != LookOptionCatalog.baselineRawValues[key]
    }

    /// Number of rows that differ (configurator options and extras).
    public var overriddenCount: Int { LookOptionCatalog.rows.filter { isOverridden($0.key) }.count }

    static let extrasBaseline: [String: String] = {
        var r: [String: String] = [:]
        for e in LookOptionCatalog.extras { r[e.key] = LookDetailExtras().rawValue(e.key) }
        return r
    }()
}
