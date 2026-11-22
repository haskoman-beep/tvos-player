import Foundation

// Welle F-d: Anzeige- und VoiceOver-Texte der Plaketten (Plan §4.5, A7) und Kopf der Quellenliste (X3).
// Die gespeicherten Texte (`RatingBadge.text`, `QualityBadge.text`) bleiben unverändert; hier entsteht nur,
// was der Bildschirm zeigt und VoiceOver spricht.

extension RatingBadge {
    /// Wert mit deutschem Komma und geschütztem Leerzeichen vor „%“: „7.4“ → „7,4“, „85%“ → „85 %“, „76“ → „76“.
    /// Nicht lesbarer Text bleibt, wie er ist.
    public var displayValue: String {
        let raw = text.trimmingCharacters(in: .whitespaces)
        if raw.hasSuffix("%") {
            let number = raw.dropLast().trimmingCharacters(in: .whitespaces)
            return number.isEmpty ? raw : number + "\u{00A0}%"
        }
        guard raw.contains(".") || raw.contains(",") else { return raw }
        let digits = raw.split(whereSeparator: { $0 == "." || $0 == "," }).last.map(\.count) ?? 1
        return DesignText.decimal(parsing: raw, fractionDigits: digits) ?? raw
    }

    /// Gesprochener Name der Quelle („🍅“ → „Rotten Tomatoes“).
    public var spokenSource: String {
        switch source {
        case "imdb": "IMDb"
        case "tomatoes": "Rotten Tomatoes"
        case "popcorn": "Rotten Tomatoes Publikum"
        case "metacritic": "Metacritic"
        case "letterboxd": "Letterboxd"
        case "trakt": "Trakt"
        case "tmdb": "TMDB"
        case "myanimelist": "MyAnimeList"
        default: label
        }
    }

    /// VoiceOver-Text der Plakette („IMDb 7,1“).
    public var accessibilityText: String {
        [spokenSource, displayValue.replacingOccurrences(of: "\u{00A0}", with: " ")]
            .filter { !$0.isEmpty }.joined(separator: " ")
    }
}

extension QualityLogoKind {
    /// Einzeilige Wortmarke (gezeichnet als Text, kein fremdes Logo).
    public var wordmark: String {
        switch self {
        case .uhd4K: "4K"
        case .dolbyVision: "DV"
        case .dolbyAtmos: "ATMOS"
        case .dtsHDMA: "DTS-HD MA"
        case .dtsX: "DTS:X"
        case .hdr10: "HDR10"
        case .hdr10Plus: "HDR10+"
        case .remux: "REMUX"
        }
    }

    /// Gesprochener Name.
    public var spokenName: String {
        switch self {
        case .uhd4K: "4K Ultra HD"
        case .dolbyVision: "Dolby Vision"
        case .dolbyAtmos: "Dolby Atmos"
        case .dtsHDMA: "DTS-HD Master Audio"
        case .dtsX: "DTS:X"
        case .hdr10: "HDR10"
        case .hdr10Plus: "HDR10+"
        case .remux: "Remux"
        }
    }
}

extension QualityBadge {
    /// Status-Plakette (Cache-Zustand) statt Technik: eigene Form (Kapsel in Zustandsfarbe, §4.5).
    public var isStatus: Bool { tone != .neutral }

    /// Sichtbarer Text ohne vorangestelltes Symbol-Emoji („⚡ sofort“ → „sofort“; das Symbol zeichnet die App).
    public var displayText: String {
        text.hasPrefix("⚡") ? text.dropFirst().trimmingCharacters(in: .whitespaces) : text
    }

    /// VoiceOver-Text (A7): Logo-Name bzw. ausgeschriebene Kürzel („DV“ → „Dolby Vision“).
    public var spokenText: String {
        if let logo { return logo.spokenName }
        switch tone {
        case .ready: return "sofort abspielbar"
        case .pending: return "lädt erst"
        case .neutral: break
        }
        switch text {
        case "DV": return "Dolby Vision"
        case "Atmos": return "Dolby Atmos"
        case "HDR": return "HDR"
        default: return text
        }
    }
}

extension AddonSearchProgress {
    /// Dauer der ganzen Suche (Addons laufen parallel: die längste Antwortzeit); nil, solange keins fertig ist.
    public var elapsedMilliseconds: Int? {
        statuses.compactMap(\.milliseconds).max()
    }
}

/// Kopf der Quellenliste (X3): „161 Quellen · 8,4 s“.
public enum StreamListSummary {
    public static func text(count: Int, milliseconds: Int?) -> String {
        let sources = count == 1 ? "1 Quelle" : "\(count) Quellen"
        let time = milliseconds.map { DesignText.decimal(Double($0) / 1000) + " s" }
        return DesignText.metaLine([sources, time])
    }
}
