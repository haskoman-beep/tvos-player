import Foundation

/// Welle E-b: Quellenliste folgt dem Addon (Reihenfolge, Text, Filter). Reine Regeln, die App zeigt nur an.

/// Anzeige-Reihenfolge der Quellenliste (Einstellung „Quellen sortieren“).
public enum StreamOrderMode: String, Codable, Sendable, CaseIterable {
    /// Reihenfolge, in der die Addons liefern (Addon-Reihenfolge im Profil, darin die Liste des Addons).
    case addon
    /// Ordnung der App aus Welle C-d (`SourceRanking`).
    case smart

    public var label: String {
        switch self {
        case .addon: "Wie Addon"
        case .smart: "Smart (App)"
        }
    }
}

/// Eigene Plaketten der App in der Quellenliste (Einstellung „App-Plaketten in der Quellenliste“).
public enum StreamListBadgeMode: String, Codable, Sendable, CaseIterable {
    case off
    /// Nur „sofort“ und Größe, und nur, wenn der Addon-Text sie nicht schon zeigt.
    case compact

    public var label: String {
        switch self {
        case .off: "Aus"
        case .compact: "Kompakt"
        }
    }
}

/// Dubletten in einer Quellenliste. Schlüssel einer Quelle: infoHash+fileIdx, Adresse, Dateiname+Größe (je nur,
/// wenn vorhanden). Zwei Einträge desselben Addons sind gleich, sobald einer ihrer Schlüssel übereinstimmt: AIOStreams
/// verpackt dieselbe Datei aus mehreren Scrapern hinter verschiedenen, verschlüsselten Abspiel-Adressen; dort trifft
/// erst Dateiname+Größe. Der erste Eintrag bleibt (Reihenfolge und `id` der übrigen unverändert).
public enum StreamDedupe {
    public static func keys(_ s: StreamItem) -> [String] {
        var out: [String] = []
        if let h = s.infoHash?.trimmingCharacters(in: .whitespaces).lowercased(), !h.isEmpty {
            out.append("h|\(h)|\(s.fileIdx.map(String.init) ?? "-")")
        }
        if let u = s.url?.trimmingCharacters(in: .whitespaces), !u.isEmpty { out.append("u|\(u)") }
        if let f = s.behaviorHints?.filename?.trimmingCharacters(in: .whitespaces), !f.isEmpty,
           let size = s.behaviorHints?.videoSize, size > 0 {
            out.append("f|\(f.lowercased())|\(size)")
        }
        return out
    }

    /// Dubletten je Addon entfernen; über die ganze Liste nie zwei Einträge mit gleicher `id` (ForEach-Identität).
    public static func unique<T>(_ list: [(addon: String, stream: T)], stream: (T) -> StreamItem) -> [(addon: String, stream: T)] {
        var seen: [String: Set<String>] = [:]
        var ids = Set<String>()
        return list.filter { e in
            let s = stream(e.stream)
            let k = keys(s)
            let dup = k.contains { seen[e.addon, default: []].contains($0) }
            // Auch die Schlüssel einer verworfenen Dublette merken (A~B über Datei, B~C über Adresse → C ist A).
            seen[e.addon, default: []].formUnion(k)
            return ids.insert(s.id).inserted && !dup
        }
    }

    public static func unique(_ list: [(addon: String, stream: StreamItem)]) -> [(addon: String, stream: StreamItem)] {
        unique(list) { $0 }
    }
}

/// Reihenfolge für Anzeige und automatische Wahl.
public enum StreamListOrder {
    /// Anzeige: Dubletten raus, dann je nach Einstellung Addon-Reihenfolge oder `SourceRanking`.
    public static func display(_ list: [(addon: String, stream: StreamItem)], mode: StreamOrderMode,
                               context: SourceRankContext) -> [(addon: String, stream: StreamItem)] {
        let u = StreamDedupe.unique(list)
        return mode == .smart && u.count > 1 ? SourceRanking.order(u, context: context) : u
    }

    /// Automatische Wahl (Weiterschauen, Rückfall, nächste Folge): immer `SourceRanking`, unabhängig von der Anzeige.
    /// Die Ordnung ist stabil und hält die Addon-Reihenfolge innerhalb gleicher Stufe; sie schiebt nur nach hinten,
    /// was die App besser weiß als das Addon (Dekoder des Geräts, Wunschsprache, sicher ungecacht).
    public static func automatic(_ list: [(addon: String, stream: StreamItem)],
                                 context: SourceRankContext) -> [(addon: String, stream: StreamItem)] {
        let u = StreamDedupe.unique(list)
        return u.count > 1 ? SourceRanking.order(u, context: context) : u
    }
}

/// Text einer Zeile genau wie vom Formatter des Addons: `name` und `description` (ältere Addons: `title`),
/// Zeilenumbrüche und Emoji bleiben, je höchstens `maxLines` Zeilen.
public struct StreamRowText: Equatable, Sendable {
    public static let maxLines = 4
    public var name: String
    public var body: String

    public init(_ s: StreamItem) {
        name = Self.capped(s.name ?? "")
        var b = Self.capped(s.label)
        if b.isEmpty, let f = s.behaviorHints?.filename { b = Self.capped(f) }
        body = b
    }

    /// CR/LF vereinheitlichen, Leerraum außen weg; mehr als `lines` Zeilen → die ersten, letzte mit „…“.
    public static func capped(_ text: String, lines: Int = maxLines) -> String {
        let t = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = t.components(separatedBy: "\n")
        guard parts.count > lines else { return t }
        return parts.prefix(lines).joined(separator: "\n") + " …"
    }
}

/// Kompakte App-Plaketten der Quellenliste: nur „sofort“ (gecacht) und Größe, jeweils nur, wenn der Addon-Text
/// sie nicht schon zeigt und der Typ in den Plaketten-Einstellungen an ist.
public enum StreamListBadges {
    public static func badges(_ s: StreamItem, mode: StreamListBadgeMode, settings: BadgeSettings) -> [QualityBadge] {
        guard mode == .compact else { return [] }
        let t = StreamTraits.parse(s)
        let text = [s.name, s.description ?? s.title].compactMap { $0 }.joined(separator: "\n")
        var out: [QualityBadge] = []
        if t.cached == true, settings.shows(.cacheStatus), !showsCached(text) {
            out.append(QualityBadge(type: .cacheStatus, text: "⚡ sofort", tone: .ready))
        }
        if let b = t.sizeBytes, b > 0, settings.shows(.size), !showsSize(text) {
            out.append(QualityBadge(type: .size, text: QualityBadges.formatSize(b)))
        }
        return out
    }

    /// Addon-Text nennt den Cache-Status schon (⚡, [RD+], „Cached“, „Instant“; „Uncached“ zählt nicht).
    public static func showsCached(_ text: String) -> Bool {
        let up = text.uppercased()
        return text.contains("⚡") || up.contains("+]") || StreamTraits.containsToken(up, "CACHED")
            || StreamTraits.containsToken(up, "INSTANT") || StreamTraits.containsToken(up, "SOFORT")
    }

    /// Addon-Text nennt eine Größe („5.93 GB“, „1,4 GiB“, „850MB“).
    public static func showsSize(_ text: String) -> Bool {
        text.range(of: #"\d+(?:[.,]\d+)?\s*(?:[KMGT]i?B)(?![A-Za-z])"#, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
