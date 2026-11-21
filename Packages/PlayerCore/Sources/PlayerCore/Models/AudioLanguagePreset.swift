import Foundation

/// Welle F-a (E5): feste Reihenfolgen für die Tonsprache statt eines nicht änderbaren Textes.
/// Gespeichert bleibt `Profile.audioPriority` (Sprachcodes, "orig" = Originalspur), damit alte Profile,
/// die Quellen-Sortierung und die Spurwahl unverändert weiterlaufen.
public enum AudioLanguagePreset: String, CaseIterable, Sendable {
    case germanFirst
    case originalFirst
    case englishFirst

    /// Standard eines neuen Profils (`Profile.init`).
    public static let standard: AudioLanguagePreset = .germanFirst

    public var priority: [String] {
        switch self {
        case .germanFirst: ["de", "en", "orig"]
        case .originalFirst: ["orig", "de"]
        case .englishFirst: ["en", "de", "orig"]
        }
    }

    /// Wert in der Zeile „Tonsprache“.
    public var label: String { AudioLanguagePreset.describe(priority) }

    /// Kurzform für Zusammenfassungen: ohne das abschließende „Original“ („Deutsch → Englisch“).
    public var shortLabel: String {
        var p = priority
        if p.count > 2, p.last == "orig" { p.removeLast() }
        return AudioLanguagePreset.describe(p)
    }

    /// Passendes Preset zu einem gespeicherten Vorrang (Groß-/Kleinschreibung und Leerraum egal), sonst nil.
    public static func matching(_ priority: [String]) -> AudioLanguagePreset? {
        let norm = normalized(priority)
        return allCases.first { $0.priority == norm }
    }

    /// Lesbarer Vorrang: „Deutsch → Englisch → Original“; unbekannte Codes in Großbuchstaben („FR“).
    public static func describe(_ priority: [String]) -> String {
        let parts = normalized(priority).map(languageName)
        return parts.isEmpty ? "Original" : parts.joined(separator: " → ")
    }

    /// Feste Namen (keine Locale: gleich auf jedem Gerät und im Test).
    public static func languageName(_ code: String) -> String {
        switch code.lowercased() {
        case "orig": "Original"
        case "de", "deu", "ger": "Deutsch"
        case "en", "eng": "Englisch"
        case "fr", "fra", "fre": "Französisch"
        case "es", "spa": "Spanisch"
        case "it", "ita": "Italienisch"
        case "ja", "jpn": "Japanisch"
        default: code.uppercased()
        }
    }

    static func normalized(_ priority: [String]) -> [String] {
        priority.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty }
    }
}

/// Auswahl in der Zeile „Tonsprache“: ein Preset oder die bisherige eigene Reihenfolge.
/// „Eigene Reihenfolge“ zeigt den alten Wert und lässt ihn unverändert, bis man ein Preset wählt (Plan §6.4).
public enum AudioLanguageChoice: Hashable, Sendable {
    case preset(AudioLanguagePreset)
    case custom

    public static func of(_ priority: [String]) -> AudioLanguageChoice {
        AudioLanguagePreset.matching(priority).map { .preset($0) } ?? .custom
    }

    /// Angebotene Werte: die drei Presets, „Eigene Reihenfolge“ nur, wenn der gespeicherte Wert keins ist.
    public static func choices(for priority: [String]) -> [AudioLanguageChoice] {
        let presets = AudioLanguagePreset.allCases.map { AudioLanguageChoice.preset($0) }
        return of(priority) == .custom ? presets + [.custom] : presets
    }

    /// Neuer gespeicherter Vorrang; `.custom` gibt den alten unverändert zurück (Rundreise).
    public func apply(to priority: [String]) -> [String] {
        switch self {
        case .preset(let p): p.priority
        case .custom: priority
        }
    }

    public static let customTitle = "Eigene Reihenfolge"

    /// Titel in der Auswahlliste.
    public var title: String {
        switch self {
        case .preset(let p): p.label
        case .custom: Self.customTitle
        }
    }

    /// Wert rechts in der Zeile; bei eigener Reihenfolge steht der alte Wert in der Beschreibung.
    public static func valueText(_ priority: [String]) -> String {
        of(priority).title
    }

    /// Kurzform für die Kategorie-Zusammenfassung.
    public static func shortText(_ priority: [String]) -> String {
        switch of(priority) {
        case .preset(let p): p.shortLabel
        case .custom: customTitle
        }
    }
}

/// Welle F-a (E5): Untertitelsprache (`Profile.subtitleLanguage`) sichtbar machen.
/// Unbekannte gespeicherte Werte bleiben erhalten und erscheinen als eigener Eintrag.
public enum SubtitleLanguageChoice {
    /// Angebotene Sprachen (Code, Name).
    public static let known: [(code: String, name: String)] = [("de", "Deutsch"), ("en", "Englisch")]

    /// Codes der Auswahlliste: bekannte, dazu der gespeicherte, wenn er keiner davon ist.
    public static func codes(for stored: String) -> [String] {
        let base = known.map(\.code)
        let s = normalized(stored)
        return s.isEmpty || base.contains(s) ? base : base + [s]
    }

    public static func name(_ code: String) -> String {
        let c = normalized(code)
        if let k = known.first(where: { $0.code == c }) { return k.name }
        return c.isEmpty ? "Keine" : AudioLanguagePreset.languageName(c)
    }

    /// Bekannte Werte werden normalisiert gespeichert; ein fremder Wert bleibt, wie er ist.
    public static func apply(_ code: String, to stored: String) -> String {
        normalized(code) == normalized(stored) ? stored : normalized(code)
    }

    static func normalized(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
}
