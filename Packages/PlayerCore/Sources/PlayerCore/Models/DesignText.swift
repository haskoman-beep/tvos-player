import Foundation

/// Textregeln des Designsystems (Plan §4.2, §4.5): Meta-Zeile, deutsches Dezimalkomma, VoiceOver-Texte.
/// Reine Logik, damit die Bausteine in `Views/Design` sie testbar teilen.
public enum DesignText {
    /// Trenner der Meta-Zeile („2018 · 97 min · FSK 0 · Animation“).
    public static let metaSeparator = " · "

    /// Meta-Zeile aus Einzelteilen; leere oder fehlende Teile fallen weg, Leerraum am Rand wird entfernt.
    public static func metaLine(_ parts: [String?]) -> String {
        cleaned(parts).joined(separator: metaSeparator)
    }

    /// Zahl mit deutschem Dezimalkomma, unabhängig von der Gerätesprache („7,1“, nie „7.1“).
    /// Nicht endliche Werte ergeben einen leeren Text; „-0,0“ wird zu „0,0“.
    /// Gerundet wird wie `String(format:)` (POSIX, binärer Wert): exakte Hälften auf die gerade Ziffer
    /// (0,25 → „0,2“, 2,5 ohne Stellen → „2“). Für Bewertungen unkritisch; im Test festgehalten.
    public static func decimal(_ value: Double, fractionDigits: Int = 1) -> String {
        guard value.isFinite else { return "" }
        let digits = max(0, min(fractionDigits, 6))
        var text = String(format: "%.\(digits)f", value)
        if text.hasPrefix("-"), text.dropFirst().allSatisfy({ $0 == "0" || $0 == "." }) { text.removeFirst() }
        return text.replacingOccurrences(of: ".", with: ",")
    }

    /// Zahl aus Text („7.1“, „7,1“, „ 8 “) mit deutschem Dezimalkomma; nicht lesbarer Text ergibt `nil`.
    /// Rundung wie `decimal(_:)`.
    public static func decimal(parsing text: String?, fractionDigits: Int = 1) -> String? {
        guard let raw = text?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
              let value = Double(raw.replacingOccurrences(of: ",", with: ".")), value.isFinite else { return nil }
        return decimal(value, fractionDigits: fractionDigits)
    }

    /// Bewertungstext aus einem Textwert (z. B. `MetaItem.imdbRating` „7.1“); nicht lesbar oder leer → `""`.
    public static func rating(source: String?, text: String?, fractionDigits: Int = 1, suffix: String = "") -> String {
        guard let number = decimal(parsing: text, fractionDigits: fractionDigits) else { return "" }
        return cleaned([source, number + suffix]).joined(separator: " ")
    }

    /// Bewertungstext „IMDb 7,1“: Quelle und Wert, ohne Quelle nur der Wert.
    public static func rating(source: String?, value: Double, fractionDigits: Int = 1, suffix: String = "") -> String {
        let number = decimal(value, fractionDigits: fractionDigits)
        guard !number.isEmpty else { return "" }
        return cleaned([source, number + suffix]).joined(separator: " ")
    }

    /// VoiceOver-Text eines Bausteins: Teile in Lesereihenfolge, durch Komma getrennt, leere Teile fallen weg.
    public static func accessibilityLabel(_ parts: [String?]) -> String {
        cleaned(parts).joined(separator: ", ")
    }

    private static func cleaned(_ parts: [String?]) -> [String] {
        parts.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
}
